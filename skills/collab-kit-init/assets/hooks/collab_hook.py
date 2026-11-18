#!/usr/bin/env python3
"""collab-kit-init 的 agent hook 共用核心，Claude Code 與 Codex 共用同一份。

用法（由 hook 設定呼叫，從 stdin 讀 JSON）：
    collab_hook.py --agent claude|codex [--allow-push-main]

事件：
  SessionStart  把專案根目錄的 STATE.md 以純文字 stdout 注入上下文（兩邊都會成為上下文）
  PreToolUse    依〈必須先問 user〉擋下：
                  - git push 到 main／預設分支（--allow-push-main 時略過這一條）
                  - force push
                  - 讀取、寫入、提交 .env 與金鑰、憑證類檔案
                  - 改動 kit 擁有的檔（AGENTS.md、docs/procedures/*.md）與 docs/spec.md

只輸出兩邊共同支援的合約：阻擋用 hookSpecificOutput.permissionDecision = "deny"。
Codex 不支援 "ask"（回 ask 會讓工具照樣執行），所以一律 deny，理由裡寫明
「請用內建問答工具問 user，user 同意後由 user 自己執行」。

hook 只是護欄，不是強制邊界：兩邊的文件都說明 hook 逾時或出錯時工具會照常執行。
本腳本出錯一律以結束碼 1 加 stderr 說明收場（兩邊都視為非阻擋錯誤、會顯示出來），
絕不使用結束碼 2：兩邊都把 2 當成「阻擋」，腳本缺檔或壞掉不能變成整個工作被擋死。
"""
import json
import os
import re
import subprocess
import sys

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import collab_adapters as adapters  # noqa: E402

AGENTS = ("claude", "codex")
STATE_MAX_CHARS = 9000  # Claude 的 additionalContext 上限是 10,000 字元，留一點餘裕

REASON_PUSH_MAIN = (
    "需 user 同意：push 到 main 或預設分支（規則檔〈必須先問 user〉）。"
    "請用內建問答工具向 user 確認；user 同意後，由 user 自己執行這條指令。"
)
REASON_FORCE = (
    "需 user 同意：force push（規則檔〈必須先問 user〉）。"
    "請用內建問答工具向 user 確認；user 同意後，由 user 自己執行這條指令。"
)
REASON_SECRET = (
    "需 user 同意：讀取、寫入或提交 .env、金鑰、憑證類檔案（規則檔〈必須先問 user〉）。"
    "請用內建問答工具向 user 確認；user 同意後，由 user 自己處理。"
)
REASON_KIT = (
    "{path} 由 kit 擁有，每次安裝整份覆寫，不要直接改。"
    "專案專屬的規則寫進 docs/project-rules.md；要改規則檔本身，請 user 修改 kit 後重裝。"
)
REASON_SPEC = (
    "docs/spec.md（公開契約與驗收）只由 user 修改，user 要求你改時也一樣。"
    "請把修改後的完整內容寫進 docs/spec.proposed.md，並在 QUESTIONS.md 開一題，由 user 自己套用。"
)

# 檔名（basename）符合就視為密鑰或憑證類檔案。.env.example 之類的範本不算。
SECRET_NAME = [
    re.compile(p, re.I)
    for p in (
        r"^\.env$",
        r"^\.env\.(?!example$|sample$|template$|dist$).+$",
        r"\.pem$",
        r"\.key$",
        r"\.(p12|pfx|jks|keystore)$",
        r"^id_(rsa|dsa|ecdsa|ed25519)$",
        r"^credentials(\.json)?$",
        r"^\.(netrc|pypirc|npmrc)$",
        r"^service[-_]?account.*\.json$",
        r"^secrets?\.(json|ya?ml|toml)$",
    )
]

_WORD = re.compile(r"[^\s'\"`<>|;&()=]+")
_PUSH = re.compile(
    r"\bgit\b((?:\s+(?:-C\s+\S+|-c\s+\S+|--[A-Za-z][\w-]*(?:=\S+)?|-[pP]))*)\s+push\b([^;&|\n]*)"
)
_WRITE_INTENT = re.compile(
    r">>?\s*\S|\btee\b|\bsed\b[^;&|\n]*\s-[A-Za-z]*i|\bperl\b[^;&|\n]*\s-[A-Za-z]*i"
    r"|\b(?:mv|cp|rm|truncate|install|ln|dd)\b"
)
_SAFE_FIRST_WORDS = ("ls", "stat", "test", "[", "[[")


def fail(message):
    sys.stderr.write("collab_hook: " + message + "\n")
    return 1


def emit(text):
    sys.stdout.buffer.write(text.encode("utf-8"))
    sys.stdout.buffer.flush()


def deny(reason):
    emit(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": reason,
                }
            },
            ensure_ascii=False,
        )
    )
    return 0


def git(args, cwd):
    """跑 git，回傳去尾的 stdout；失敗回傳 None（不吞錯誤：呼叫端依 None 走保守路徑）。"""
    try:
        done = subprocess.run(
            ["git"] + args, cwd=cwd, capture_output=True, text=True, timeout=5
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if done.returncode != 0:
        return None
    return done.stdout.strip()


def project_root(cwd):
    return git(["rev-parse", "--show-toplevel"], cwd) or cwd


def rel_to_root(path, cwd, root):
    """路徑換成相對專案根目錄的正斜線形式；在專案外回傳 None。"""
    full = path if os.path.isabs(path) else os.path.join(cwd, path)
    rel = os.path.relpath(os.path.normpath(full), root).replace(os.sep, "/")
    if rel == ".." or rel.startswith("../"):
        return None
    return rel


def is_secret_name(path):
    base = path.replace("\\", "/").rsplit("/", 1)[-1]
    return any(p.search(base) for p in SECRET_NAME)


def protected_reason(rel):
    if rel == "AGENTS.md" or (rel.startswith("docs/procedures/") and rel.endswith(".md")):
        return REASON_KIT.format(path=rel)
    if rel == "docs/spec.md":
        return REASON_SPEC
    return None


def protected_branches(cwd):
    names = {"main", "master"}
    head = git(["symbolic-ref", "--short", "refs/remotes/origin/HEAD"], cwd)
    if head:
        names.add(head.split("/", 1)[-1])
    return names


def check_push(command, cwd, allow_push_main):
    for match in _PUSH.finditer(command):
        args = [t.strip("'\")") for t in match.group(2).split()]
        args = [t for t in args if t]
        force = False
        for t in args:
            if t in ("--force", "-f", "--mirror") or t.startswith(
                ("--force-with-lease", "--force-if-includes")
            ):
                force = True
            elif re.fullmatch(r"-[A-Za-z]*f[A-Za-z]*", t):
                force = True
            elif t.startswith("+"):
                force = True
        if force:
            return REASON_FORCE
        if allow_push_main:
            continue
        positional = [t for t in args if not t.startswith("-")]
        refspecs = positional[1:]
        current = git(["symbolic-ref", "--short", "-q", "HEAD"], cwd)
        protected = protected_branches(cwd)
        if "--all" in args:
            return REASON_PUSH_MAIN
        if not refspecs:
            if current is None or current in protected:
                return REASON_PUSH_MAIN
            continue
        for spec in refspecs:
            dst = spec.split(":", 1)[-1] if ":" in spec else spec
            if dst.startswith("refs/heads/"):
                dst = dst[len("refs/heads/"):]
            if dst == "HEAD":
                dst = current or "main"
            if dst in protected:
                return REASON_PUSH_MAIN
    return None


def check_shell(command, cwd, root, allow_push_main):
    reason = check_push(command, cwd, allow_push_main)
    if reason:
        return reason
    words = _WORD.findall(command)
    first = words[0] if words else ""
    ignore_edit = ".gitignore" in command or ".dockerignore" in command
    if first not in _SAFE_FIRST_WORDS and not ignore_edit:
        if any(is_secret_name(w) for w in words):
            return REASON_SECRET
    if _WRITE_INTENT.search(command):
        for word in words:
            if "/" not in word and "." not in word:
                continue
            rel = rel_to_root(word, cwd, root)
            if rel:
                reason = protected_reason(rel)
                if reason:
                    return reason
    return None


def check_files(agent, tool_name, tool_input, cwd, root):
    targets = adapters.file_targets(agent, tool_name, tool_input)
    for action, path in targets:
        if is_secret_name(path):
            return REASON_SECRET
        if action == "edit":
            rel = rel_to_root(path, cwd, root)
            if rel:
                reason = protected_reason(rel)
                if reason:
                    return reason
    patch = adapters.patch_text(agent, tool_name, tool_input)
    if patch is not None and not targets:
        # 解析不到檔案標頭：不依賴 patch 格式，改用整段文字保守比對。
        if any(is_secret_name(w) for w in _WORD.findall(patch)):
            return REASON_SECRET
        if "AGENTS.md" in patch or "docs/procedures/" in patch:
            return REASON_KIT.format(path="AGENTS.md 或 docs/procedures/")
        if "docs/spec.md" in patch:
            return REASON_SPEC
    return None


def session_start(root):
    path = os.path.join(root, "STATE.md")
    if not os.path.isfile(path):
        return 0
    with open(path, "rb") as handle:
        text = handle.read().decode("utf-8", "replace")
    note = ""
    if len(text) > STATE_MAX_CHARS:
        text = text[:STATE_MAX_CHARS]
        note = "\n\n（STATE.md 超過 %d 字元，上面只注入前段；請自行讀取完整檔案）" % STATE_MAX_CHARS
    emit("【STATE.md：開工自動注入】\n" + text + note + "\n")
    return 0


def pre_tool_use(agent, data, root, allow_push_main):
    tool_name = data.get("tool_name") or ""
    tool_input = data.get("tool_input")
    cwd = data.get("cwd") or root
    command = adapters.shell_command(agent, tool_name, tool_input)
    if command is not None:
        reason = check_shell(command, cwd, root, allow_push_main)
    else:
        reason = check_files(agent, tool_name, tool_input, cwd, root)
    if reason:
        return deny(reason)
    return 0


def parse_args(argv):
    agent, allow = None, False
    i = 0
    while i < len(argv):
        if argv[i] == "--agent" and i + 1 < len(argv):
            agent = argv[i + 1]
            i += 2
        elif argv[i] == "--allow-push-main":
            allow = True
            i += 1
        else:
            return None, False, "未知參數：%s" % argv[i]
    if agent not in AGENTS:
        return None, False, "--agent 必須是 %s" % " 或 ".join(AGENTS)
    return agent, allow, None


def main(argv):
    agent, allow_push_main, error = parse_args(argv)
    if error:
        return fail(error)
    try:
        data = json.loads(sys.stdin.buffer.read().decode("utf-8"))
    except (ValueError, OSError) as exc:
        return fail("stdin 不是有效的 JSON：%s" % exc)
    if not isinstance(data, dict):
        return fail("stdin 的 JSON 不是物件")
    cwd = data.get("cwd") if isinstance(data.get("cwd"), str) else os.getcwd()
    root = project_root(cwd)
    event = data.get("hook_event_name")
    if event == "SessionStart":
        return session_start(root)
    if event == "PreToolUse":
        return pre_tool_use(agent, data, root, allow_push_main)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as exc:  # 非預期錯誤：說明原因並以 1 結束，不能變成 2（阻擋）
        sys.exit(fail("非預期錯誤：%r" % (exc,)))
