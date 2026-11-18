#!/usr/bin/env python3
"""把 collab hook 設定冪等地合併進 .claude/settings.json 或 .codex/hooks.json。

用法：
    merge_hooks.py --target FILE --agent claude|codex [--allow-push-main] [--allow-github-mcp-writes]
                   (--check | --dry-run | --apply)

  --check    只驗證既有檔案是不是可合併的 JSON（壞掉結束碼 3，不寫任何東西）
  --dry-run  印出會發生什麼，不寫檔
  --apply    寫入；既有檔案內容有變時，舊檔先留成 .bak（已存在就用 .bak.1、.bak.2……）

stdout 一行：created、updated<TAB>備份檔路徑、unchanged。
只動 SessionStart 與 PreToolUse 兩個事件裡「命令含 tools/hooks/collab_hook.py」的項目：先移除舊的、再加新的，
其他事件、其他項目原封不動；移除後變成空陣列的事件就刪掉那個鍵；重跑結果相同。
Claude：hook 只裝 PreToolUse，而且只看 Bash（STATE.md 已由 CLAUDE.md 的 @STATE.md 載入，SessionStart 再注入是重複）；
        密鑰檔、受保護檔、force push 改用 permissions.deny 靜態規則（Claude Code 自己執行，deny 優先於 hook，
        涵蓋檔案工具與 Bash 的 cat／sed／tee／重導向，解析 symlink，不會逾時放行）；
        hook 只負責靜態規則寫不出來的「目前分支是 main 時的 git push」。
Codex： 裝 SessionStart 與 PreToolUse（Codex 沒有等價的靜態規則可管檔案編輯）。

permissions.deny 的合併：先移除「完全等於我們可能寫過的規則」，再把這次要的規則接成連續一段加在最後
（! 否定規則必須排在它要排除的規則後面）；其他規則與其他設定原封不動。
"""
import json
import os
import shutil
import sys

MARK = "tools/hooks/collab_hook.py"

# 兩邊命令的差異（抽出來的部分）：
#   Claude 有 CLAUDE_PROJECT_DIR，沒有就退回 git 根目錄；Codex 文件建議以 git 根目錄解析路徑。
# 腳本缺檔時以結束碼 1 收場（非阻擋錯誤）；結束碼 2 在兩邊都代表「阻擋」，不能出現在這裡。
_SCRIPT_CHECK = '[ -f "$f" ] || { echo "collab hook: 找不到 $f" >&2; exit 1; }'


def command(agent, allow_push_main):
    extra = " --allow-push-main" if allow_push_main else ""
    if agent == "claude":
        base = 'f="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/' + MARK + '"'
    else:
        base = 'f="$(git rev-parse --show-toplevel 2>/dev/null)/' + MARK + '"'
    return "sh -c '%s; %s; exec python3 \"$f\" --agent %s%s'" % (base, _SCRIPT_CHECK, agent, extra)


OUR_EVENTS = ("SessionStart", "PreToolUse")


def desired(agent, allow_push_main):
    cmd = command(agent, allow_push_main)
    pre = {"type": "command", "command": cmd, "timeout": 10, "statusMessage": "檢查 collab 規則"}
    if agent == "codex":
        start = {"type": "command", "command": cmd, "timeout": 10, "statusMessage": "載入 STATE.md"}
        # Codex 預設只讓每個 hook 的 additionalContext 佔約 2500 token，STATE.md 可能被截成預覽。
        start["additionalContextLimit"] = 6000
        return {
            "SessionStart": [{"matcher": "startup|resume|clear|compact", "hooks": [start]}],
            "PreToolUse": [{"matcher": "Bash|apply_patch", "hooks": [pre]}],
        }
    return {"PreToolUse": [{"matcher": "Bash", "hooks": [pre]}]}


# ---- Claude 的 permissions.deny（路徑寫法見官方 permissions 文件）----
# /path 以「設定檔所在專案的主要工作目錄」為起點；裸檔名依 gitignore 語意在任何深度都匹配。
# Read 的 deny 同時擋 Edit／Write；Read／Edit 規則涵蓋 Bash 的 cat、head、tail、sed、tee 與重導向目標。
DENY_SECRETS = [
    "Read(.env)",
    "Read(.env.*)",
    "Read(!.env.example)",
    "Read(!.env.sample)",
    "Read(!.env.template)",
    "Read(!.env.dist)",
    "Read(*.pem)",
    "Read(*.key)",
    "Read(*.p12)",
    "Read(*.pfx)",
    "Read(*.jks)",
    "Read(*.keystore)",
    "Read(id_rsa)",
    "Read(id_dsa)",
    "Read(id_ecdsa)",
    "Read(id_ed25519)",
    "Read(credentials)",
    "Read(credentials.json)",
    "Read(.netrc)",
    "Read(.npmrc)",
    "Read(.pypirc)",
]
DENY_KIT_FILES = [
    "Edit(/AGENTS.md)",
    "Edit(/docs/procedures/**)",
    "Edit(/docs/spec.md)",
]
DENY_FORCE_PUSH = [
    "Bash(git push --force*)",
    "Bash(git push -f)",
    "Bash(git push -f *)",
    "Bash(git push * --force*)",
    "Bash(git push * -f)",
    "Bash(git push * -f *)",
]
# GitHub MCP 的寫入工具能不經 git push 直接動分支；靜態規則看不出目標分支，所以整個擋掉。
# MCP 規則不能帶括號（帶括號的會被 Claude Code 略過）。只涵蓋名為 github 的 MCP 伺服器。
DENY_GITHUB_MCP = [
    "mcp__github__push_files",
    "mcp__github__create_or_update_file",
    "mcp__github__delete_file",
    "mcp__github__merge_pull_request",
]
DENY_ALL = DENY_SECRETS + DENY_KIT_FILES + DENY_FORCE_PUSH + DENY_GITHUB_MCP


def desired_deny(allow_github_mcp_writes):
    rules = DENY_SECRETS + DENY_KIT_FILES + DENY_FORCE_PUSH
    if not allow_github_mcp_writes:
        rules = rules + DENY_GITHUB_MCP
    return rules


def is_ours(handler):
    return isinstance(handler, dict) and MARK in str(handler.get("command", ""))


def merged(existing, agent, allow_push_main, allow_github_mcp_writes=False):
    if existing is None:
        existing = {}
    if not isinstance(existing, dict):
        raise ValueError("最上層不是 JSON 物件")
    hooks = existing.get("hooks", {})
    if not isinstance(hooks, dict):
        raise ValueError("hooks 不是物件")
    result = dict(existing)
    new_hooks = {}
    for event, groups in hooks.items():
        if not isinstance(groups, list):
            raise ValueError("hooks.%s 不是陣列" % event)
        if event not in OUR_EVENTS:
            new_hooks[event] = groups
            continue
        kept, removed = [], False
        for group in groups:
            if isinstance(group, dict) and isinstance(group.get("hooks"), list):
                handlers = [h for h in group["hooks"] if not is_ours(h)]
                if len(handlers) != len(group["hooks"]):
                    removed = True
                    if not handlers:
                        continue
                    group = dict(group, hooks=handlers)
            kept.append(group)
        if kept or not removed:
            new_hooks[event] = kept
    for event, groups in desired(agent, allow_push_main).items():
        new_hooks.setdefault(event, []).extend(groups)
    result["hooks"] = new_hooks
    if agent == "claude":
        permissions = result.get("permissions", {})
        if not isinstance(permissions, dict):
            raise ValueError("permissions 不是物件")
        deny = permissions.get("deny", [])
        if not isinstance(deny, list) or not all(isinstance(x, str) for x in deny):
            raise ValueError("permissions.deny 不是字串陣列")
        kept = [x for x in deny if x not in DENY_ALL]
        new_deny = kept + desired_deny(allow_github_mcp_writes)
        permissions = dict(permissions, deny=new_deny)
        result["permissions"] = permissions
    return result


def load(target):
    if not os.path.exists(target):
        return None, False
    with open(target, "rb") as handle:
        raw = handle.read().decode("utf-8")
    if not raw.strip():
        return None, True
    return json.loads(raw), True


def next_bak(path):
    base = path + ".bak"
    if not os.path.exists(base):
        return base
    n = 1
    while os.path.exists("%s.%d" % (base, n)):
        n += 1
    return "%s.%d" % (base, n)


def parse(argv):
    opts = {"target": None, "agent": None, "allow": False, "mcp": False, "mode": None}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("--target", "--agent") and i + 1 < len(argv):
            opts[a[2:]] = argv[i + 1]
            i += 2
        elif a == "--allow-push-main":
            opts["allow"] = True
            i += 1
        elif a == "--allow-github-mcp-writes":
            opts["mcp"] = True
            i += 1
        elif a in ("--check", "--dry-run", "--apply"):
            opts["mode"] = a[2:]
            i += 1
        else:
            raise ValueError("未知參數：%s" % a)
    if not opts["target"] or opts["agent"] not in ("claude", "codex") or not opts["mode"]:
        raise ValueError("需要 --target、--agent claude|codex，以及 --check／--dry-run／--apply 其中之一")
    return opts


def main(argv):
    try:
        opts = parse(argv)
    except ValueError as exc:
        sys.stderr.write("merge_hooks: %s\n" % exc)
        return 2
    target = opts["target"]
    try:
        existing, existed = load(target)
        result = merged(existing, opts["agent"], opts["allow"], opts["mcp"])
    except (ValueError, UnicodeDecodeError) as exc:
        sys.stderr.write("%s 不是可合併的設定檔：%s\n" % (target, exc))
        return 3
    if opts["mode"] == "check":
        return 0
    if existed and existing == result:
        print("unchanged")
        return 0
    if opts["mode"] == "dry-run":
        print("updated" if existed else "created")
        return 0
    bak = ""
    if existed:
        bak = next_bak(target)
        shutil.copy2(target, bak)
    os.makedirs(os.path.dirname(target) or ".", exist_ok=True)
    tmp = target + ".collab-tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(result, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    os.replace(tmp, target)
    print(("updated\t" + bak) if existed else "created")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
