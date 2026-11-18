#!/usr/bin/env python3
"""collab-kit-init 的 git pre-commit 文件檢查。與 agent 無關，人和任何 agent 的 commit 都適用。

只檢查這次暫存的檔案：
  1. 任意 Markdown 不超過 32 KiB
  2. STATE.md 不超過 6 KiB
  3. 專案文件（STATE.md、DECISIONS.md、QUESTIONS.md、ROADMAP、docs/procedures 等）裡用反引號寫的檔案路徑都存在
  4. CLAUDE.md 有匯入 AGENTS.md 與 STATE.md（CLAUDE.md 或 AGENTS.md 這次有動時才查）

有問題時列出全部、以結束碼 1 擋下 commit；確定要略過時用 git commit --no-verify。
腳本自己出錯（git 失敗等）也以 1 結束並說明原因：不能靜默放行，也不吞錯。
"""
import os
import re
import subprocess
import sys

sys.dont_write_bytecode = True

MD_MAX = 32 * 1024
STATE_MAX = 6 * 1024

REF_CHECKED = re.compile(
    r"^(CLAUDE\.md|AGENTS\.md|STATE\.md|DECISIONS\.md|QUESTIONS\.md|ROADMAP\.md|ROADMAP/[^/]+\.md"
    r"|docs/procedures/[^/]+\.md|docs/(plans/README|testing|cold-review|project-rules|spec)\.md)$"
)
REF_ALLOW = re.compile(
    r"^(docs/troubleshooting\.md|docs/environment\.md|docs/spec\.proposed\.md|docs/specs/.*|docs/plans/.+|\.github/.*|archive/)$"
)
BACKTICK = re.compile(r"`([^` <>]+)`")


class CheckError(Exception):
    pass


def git(args, text=True):
    done = subprocess.run(["git"] + args, capture_output=True, text=text)
    if done.returncode != 0:
        err = done.stderr if text else done.stderr.decode("utf-8", "replace")
        raise CheckError("git %s 失敗：%s" % (" ".join(args), err.strip()))
    return done.stdout


def staged_files():
    out = git(["diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z"], text=False)
    return [p for p in out.decode("utf-8", "replace").split("\0") if p]


def staged_blob(path):
    return subprocess.run(["git", "show", ":" + path], capture_output=True).stdout


def imports(text):
    """整行只有 @<路徑> 的匯入；略過 code fence（``` 與 ~~~，同字元且不短於開頭才算關閉）與 HTML 註解。"""
    found, fence, in_comment = [], None, False
    if text.startswith("﻿"):
        text = text[1:]
    for raw in text.replace("\r", "").split("\n"):
        if fence:
            m = re.match(r"^[ \t]*(`{3,}|~{3,})[ \t]*$", raw)
            if m and m.group(1)[0] == fence[0] and len(m.group(1)) >= fence[1]:
                fence = None
            continue
        line, out = raw, ""
        while True:
            if in_comment:
                i = line.find("-->")
                if i < 0:
                    line = ""
                    break
                line, in_comment = line[i + 3:], False
            else:
                i = line.find("<!--")
                if i < 0:
                    break
                out += line[:i]
                rest = line[i + 4:]
                j = rest.find("-->")
                if j < 0:
                    line, in_comment = "", True
                    break
                line = rest[j + 3:]
        line = out + line
        m = re.match(r"^[ \t]*(`{3,}|~{3,})", line)
        if m:
            fence = (m.group(1)[0], len(m.group(1)))
            continue
        if re.fullmatch(r"@\S+\s*", line):
            name = line.strip()[1:]
            while name.startswith("./"):
                name = name[2:]
            found.append(name)
    return found


def referenced_paths(text):
    refs = set()
    for token in BACKTICK.findall(text):
        if not ("/" in token or re.search(r"\.(md|json|jsonl|py)$", token)):
            continue
        if re.match(r"^(cd |-|git|npm|node|https?:)", token):
            continue
        if re.search(r"[*$…／]", token):
            continue
        token = re.sub(r"[#:].*$", "", token)
        if token and not REF_ALLOW.match(token):
            refs.add(token)
    return sorted(refs)


def run():
    root = git(["rev-parse", "--show-toplevel"]).strip()
    os.chdir(root)
    files = staged_files()
    tracked = set(git(["ls-files", "--cached", "-z"], text=False).decode("utf-8", "replace").split("\0"))
    problems = []

    for path in files:
        size = len(staged_blob(path))
        if path.lower().endswith(".md") and size > MD_MAX:
            problems.append("%s 有 %d 位元組，超過 32 KiB，請拆分" % (path, size))
        if path == "STATE.md" and size > STATE_MAX:
            problems.append("STATE.md 有 %d 位元組，超過 6 KiB 上限，請刪去沿革與過時內容" % size)

    for path in files:
        if not REF_CHECKED.match(path):
            continue
        text = staged_blob(path).decode("utf-8", "replace")
        for ref in referenced_paths(text):
            if not (os.path.exists(ref) or ref in tracked):
                problems.append("%s 引用的 %s 不存在" % (path, ref))

    if ("CLAUDE.md" in files or "AGENTS.md" in files) and os.path.isfile("CLAUDE.md"):
        with open("CLAUDE.md", "rb") as handle:
            found = imports(handle.read().decode("utf-8", "replace"))
        for need in ("AGENTS.md", "STATE.md"):
            if need not in found:
                problems.append("CLAUDE.md 沒有整行 @%s 匯入" % need)

    if problems:
        sys.stderr.write("collab pre-commit：%d 個問題（確定要略過時用 git commit --no-verify）\n" % len(problems))
        for item in problems:
            sys.stderr.write("  - %s\n" % item)
        return 1
    return 0


if __name__ == "__main__":
    try:
        sys.exit(run())
    except CheckError as exc:
        sys.stderr.write("collab pre-commit：檢查本身失敗，commit 被擋下：%s\n" % exc)
        sys.exit(1)
