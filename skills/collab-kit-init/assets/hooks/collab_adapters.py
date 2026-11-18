"""兩個 agent 的 hook 輸入差異，全部集中在這裡。

核心（collab_hook.py）只呼叫這個模組，不直接判斷是哪個 agent。
共用的部分（兩邊格式相同）：
  - Bash 工具：tool_input.command 是指令字串
需要各自處理的部分：
  - 改檔工具：Claude 的 Edit／Write 給 tool_input.file_path；
    Codex 的 apply_patch 給 tool_input.command，內容是整段 patch 文字
  - 讀檔工具：Claude 有 Read 工具；Codex 讀檔走 Bash，沒有 Read
"""
import re

SHELL_TOOLS = ("Bash", "PowerShell")

# apply_patch 的檔案標頭行。格式依 Codex 的 apply_patch 工具慣例撰寫，
# 官方 hooks 文件只說明 tool_input.command 是 patch 文字，沒有列出標頭格式。
# 解析不到任何路徑時，核心改用整段 patch 文字做保守比對，不依賴這個格式。
_PATCH_HEADER = re.compile(
    r"^\*\*\* (?:Add|Update|Delete) File: (.+?)\s*$|^\*\*\* Move to: (.+?)\s*$",
    re.M,
)


def shell_command(agent, tool_name, tool_input):
    """回傳要檢查的 shell 指令字串；不是 shell 工具就回傳 None。"""
    if tool_name in SHELL_TOOLS and isinstance(tool_input, dict):
        command = tool_input.get("command")
        if isinstance(command, str):
            return command
    return None


def file_targets(agent, tool_name, tool_input):
    """回傳 [(動作, 路徑)]。動作是 "edit" 或 "read"，路徑可能是相對路徑。"""
    if not isinstance(tool_input, dict):
        return []
    if agent == "claude":
        path = tool_input.get("file_path")
        if not isinstance(path, str):
            return []
        if tool_name in ("Edit", "Write", "MultiEdit"):
            return [("edit", path)]
        if tool_name == "Read":
            return [("read", path)]
        return []
    if agent == "codex":
        if tool_name == "apply_patch":
            patch = tool_input.get("command")
            if isinstance(patch, str):
                found = [a or b for a, b in _PATCH_HEADER.findall(patch)]
                return [("edit", p) for p in found]
        return []
    return []


def patch_text(agent, tool_name, tool_input):
    """Codex 的 apply_patch 原文；其他情況回傳 None。供保守比對使用。"""
    if agent == "codex" and tool_name == "apply_patch" and isinstance(tool_input, dict):
        patch = tool_input.get("command")
        if isinstance(patch, str):
            return patch
    return None
