#!/usr/bin/env python3
"""把 collab hook 設定冪等地合併進 .claude/settings.json 或 .codex/hooks.json。

用法：
    merge_hooks.py --target FILE --agent claude|codex [--allow-push-main] (--check | --dry-run | --apply)

  --check    只驗證既有檔案是不是可合併的 JSON（壞掉結束碼 3，不寫任何東西）
  --dry-run  印出會發生什麼，不寫檔
  --apply    寫入；既有檔案內容有變時，舊檔先留成 .bak（已存在就用 .bak.1、.bak.2……）

stdout 一行：created、updated<TAB>備份檔路徑、unchanged。
只動 SessionStart 與 PreToolUse 兩個事件裡「命令含 tools/hooks/collab_hook.py」的項目：先移除舊的、再加新的，
其他事件、其他項目原封不動；移除後變成空陣列的事件就刪掉那個鍵；重跑結果相同。
Claude 只裝 PreToolUse（STATE.md 已經由 CLAUDE.md 的 @STATE.md 載入，SessionStart 再注入是重複）；
Codex 裝 SessionStart 與 PreToolUse。
"""
import json
import os
import shutil
import sys
import tempfile

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
    return {"PreToolUse": [{"matcher": "Bash|Edit|Write|MultiEdit|Read", "hooks": [pre]}]}


def is_ours(handler):
    return isinstance(handler, dict) and MARK in str(handler.get("command", ""))


def merged(existing, agent, allow_push_main):
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
    # lexists：斷掉的 symlink 也算已佔用，否則 copy2 會寫穿到連結的另一端
    base = path + ".bak"
    if not os.path.lexists(base):
        return base
    n = 1
    while os.path.lexists("%s.%d" % (base, n)):
        n += 1
    return "%s.%d" % (base, n)


def parse(argv):
    opts = {"target": None, "agent": None, "allow": False, "mode": None}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("--target", "--agent") and i + 1 < len(argv):
            opts[a[2:]] = argv[i + 1]
            i += 2
        elif a == "--allow-push-main":
            opts["allow"] = True
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
        result = merged(existing, opts["agent"], opts["allow"])
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
    # 暫存檔用 mkstemp（O_EXCL、名稱唯一）：固定名稱會截斷或寫穿任何已佔用該名稱的檔案或 symlink
    fd, tmp = tempfile.mkstemp(prefix=os.path.basename(target) + ".collab-tmp.", dir=os.path.dirname(target) or ".")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(result, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
        os.chmod(tmp, (os.stat(target).st_mode & 0o777) if existed else 0o644)  # mkstemp 預設 0600，維持原權限
        os.replace(tmp, target)
    except BaseException:
        if os.path.lexists(tmp):
            os.unlink(tmp)
        raise
    print(("updated\t" + bak) if existed else "created")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
