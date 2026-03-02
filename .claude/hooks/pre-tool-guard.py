import json
import os
import re
import sys


def normalize_path(path: str) -> str:
    return os.path.normcase(os.path.normpath(path))


def build_lock_path(payload: dict) -> str:
    project_dir = os.environ.get("CLAUDE_PROJECT_DIR") or payload.get("cwd") or os.getcwd()
    return normalize_path(os.path.join(project_dir, "01-tasks", "TASK-LOCKS.json"))


def build_approval_requests_path(payload: dict) -> str:
    project_dir = os.environ.get("CLAUDE_PROJECT_DIR") or payload.get("cwd") or os.getcwd()
    return normalize_path(
        os.path.join(project_dir, "mcp", "route-server", "data", "approval-requests.json")
    )


def emit_deny(reason: str) -> None:
    result = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }
    print(json.dumps(result, ensure_ascii=False))


def is_safe_approval_send(command: str) -> bool:
    cmd = command.strip()
    # 仅放行最小审批按键（y/n）与回车，不允许任意文本 send-text
    safe_patterns = [
        r'^\s*wezterm\s+cli\s+send-text\b.*--no-paste\s+(?:"y"|\'y\'|y)\s*$',
        r'^\s*wezterm\s+cli\s+send-text\b.*--no-paste\s+(?:"n"|\'n\'|n)\s*$',
        r'^\s*wezterm\s+cli\s+send-text\b.*--no-paste\s+(?:"`r"|\'`r\'|\$\'\\r\')\s*$',
    ]
    for pattern in safe_patterns:
        if re.search(pattern, cmd, flags=re.IGNORECASE):
            return True
    return False


def deny_if_direct_dispatch(command: str) -> bool:
    cmd = (command or "").lower()
    blocked_patterns = ["dispatch-task.ps1", "start-worker.ps1"]
    for pattern in blocked_patterns:
        if pattern in cmd:
            emit_deny(
                "禁止绕过统一控制器直接派遣。请使用: "
                "powershell -NoProfile -ExecutionPolicy Bypass -File "
                "\"E:\\moxton-ccb\\scripts\\teamlead-control.ps1\" -Action dispatch|dispatch-qa|recover"
            )
            return True

    if "wezterm cli send-text" in cmd and not is_safe_approval_send(command):
        emit_deny(
            "禁止直接 send-text 派遣任务文本。审批请优先走 "
            "teamlead-control.ps1 -Action approve-request/deny-request；"
            "仅允许最小 y/n 回应。"
        )
        return True
    return False


def has_pending_approvals(approval_path: str) -> bool:
    if not approval_path or not os.path.exists(approval_path):
        return False
    try:
        with open(approval_path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        reqs = data.get("requests") or []
        for req in reqs:
            if str(req.get("status", "")).lower() == "pending":
                return True
        return False
    except Exception:
        # 文件损坏时不阻塞流程
        return False


def is_wait_command(command: str) -> bool:
    cmd = (command or "").strip()
    patterns = [
        r"^\s*sleep\b",
        r"^\s*start-sleep\b",
        r"^\s*timeout\s+/t\b",
    ]
    return any(re.search(p, cmd, flags=re.IGNORECASE) for p in patterns)


def deny_if_editing_task_locks(tool_name: str, tool_input: dict, lock_path: str) -> bool:
    if tool_name not in {"Write", "Edit", "MultiEdit"}:
        return False

    file_path = tool_input.get("file_path")
    if not file_path:
        return False

    if normalize_path(str(file_path)) == lock_path:
        emit_deny(
            "禁止直接编辑 TASK-LOCKS.json。请通过 teamlead-control.ps1 执行 "
            "add-lock / recover(reset-task|normalize-locks) 等动作。"
        )
        return True
    return False


def main() -> int:
    raw = sys.stdin.read()
    if not raw.strip():
        return 0

    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return 0

    tool_name = payload.get("tool_name", "")
    tool_input = payload.get("tool_input", {}) or {}
    lock_path = build_lock_path(payload)
    approval_path = build_approval_requests_path(payload)

    if tool_name == "Bash":
        command = str(tool_input.get("command", ""))
        if deny_if_direct_dispatch(command):
            return 0
        if is_wait_command(command) and has_pending_approvals(approval_path):
            emit_deny(
                "检测到存在 pending 审批请求，禁止先 sleep/wait。"
                "请先执行 teamlead-control.ps1 -Action status 并 approve-request/deny-request。"
            )
            return 0

    if deny_if_editing_task_locks(tool_name, tool_input, lock_path):
        return 0

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
