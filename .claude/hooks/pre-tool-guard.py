import json
import os
import re
import sys

PROTECTED_REPO_ROOTS = [
    os.path.normcase(os.path.normpath(r"E:\moxton-lotapi")),
    os.path.normcase(os.path.normpath(r"E:\nuxt-moxton")),
    os.path.normcase(os.path.normpath(r"E:\moxton-lotadmin")),
]


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


def deny_if_assign_task_misuse(command: str) -> bool:
    cmd = (command or "").strip()
    cmd_lower = cmd.lower()
    if "assign_task.py" not in cmd_lower:
        return False

    # Team Lead 仅允许只读/诊断类调用，禁止通过 assign_task.py 创建任务、改锁、拆分任务等写入动作。
    readonly_flags = [
        "--doctor",
        "--standard-entry",
        "--list",
        "--scan",
        "--show-lock",
        "--show-task-locks",
        "--team-prompt",
    ]
    has_readonly_flag = any(flag in cmd_lower for flag in readonly_flags)
    if has_readonly_flag:
        return False

    emit_deny(
        "禁止 Team Lead 直接使用 assign_task.py 执行写入/派遣前置动作。"
        "任务创建与派遣请走主链路：planning-gate + teamlead-control.ps1。"
    )
    return True


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


def deny_if_teamlead_touches_code_repo(tool_name: str, tool_input: dict) -> bool:
    if tool_name in {"Write", "Edit", "MultiEdit"}:
        file_path = tool_input.get("file_path")
        if file_path:
            f = normalize_path(str(file_path))
            for root in PROTECTED_REPO_ROOTS:
                if f.startswith(root + os.sep) or f == root:
                    emit_deny(
                        "Team Lead 禁止直接修改业务仓库代码。"
                        "请通过 dispatch/dispatch-qa 派遣 worker 执行开发或 QA。"
                    )
                    return True

    if tool_name == "Bash":
        command = str((tool_input or {}).get("command", ""))
        cmd = command.lower()
        repo_hits = [
            r for r in [r"e:\moxton-lotapi", r"e:\nuxt-moxton", r"e:\moxton-lotadmin"]
            if r in cmd
        ]
        if repo_hits:
            forbidden_patterns = [
                r"\bgit\s+(add|commit|push|pull|checkout|switch|merge|rebase|cherry-pick|reset|clean|restore)\b",
                r"\b(npm|pnpm|yarn)\s+(install|add|remove|update|up|run\s+build|run\s+dev)\b",
                r"\bpython\b.*\b(setup|migrate|seed)\b",
                r"\bRemove-Item\b",
                r"\bMove-Item\b",
                r"\bCopy-Item\b",
                r"\bSet-Content\b",
                r"\bAdd-Content\b",
                r"\bOut-File\b",
                r"\bNew-Item\b",
                r"\brm\b",
                r"\bdel\b",
                r"\bmv\b",
                r"\bcp\b",
                r"\btee\b",
            ]
            for pat in forbidden_patterns:
                if re.search(pat, command, flags=re.IGNORECASE):
                    emit_deny(
                        "Team Lead 在业务仓库仅允许只读分析，禁止写入/变更命令。"
                        "请通过 dispatch/dispatch-qa 派遣 worker 执行修改。"
                    )
                    return True

            readonly_patterns = [
                r"\brg\b",
                r"\bfindstr\b",
                r"\bselect-string\b",
                r"\bcat\b",
                r"\btype\b",
                r"\bget-content\b",
                r"\bls\b",
                r"\bdir\b",
                r"\bget-childitem\b",
                r"\bgit\s+(-c\s+\S+\s+)*(-C\s+\S+\s+)?(status|diff|log|show|rev-parse|describe|ls-files|branch\s+--show-current)\b",
            ]
            if any(re.search(pat, command, flags=re.IGNORECASE) for pat in readonly_patterns):
                return False

            emit_deny(
                "Team Lead 在业务仓库仅允许只读分析命令。"
                "可用示例：rg / Get-Content / git status|diff|log|show。"
            )
            return True
    return False


def deny_if_route_tool_misuse(tool_name: str, tool_input: dict) -> bool:
    name = (tool_name or "").lower()
    if "report_route" in name:
        emit_deny(
            "Team Lead 禁止直接调用 report_route。"
            "report_route 仅用于 Worker 回传；请改用 teamlead-control.ps1 执行调度/审批动作。"
        )
        return True

    if "clear_route" in name and bool((tool_input or {}).get("clear_all")):
        emit_deny(
            "禁止 clear_route(clear_all=true) 批量清空回调。"
            "请使用 clear_route(route_id) 精确清理，或由统一流程自动处理。"
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

    if deny_if_teamlead_touches_code_repo(tool_name, tool_input):
        return 0

    if deny_if_route_tool_misuse(tool_name, tool_input):
        return 0

    if tool_name == "Bash":
        command = str(tool_input.get("command", ""))
        if deny_if_direct_dispatch(command):
            return 0
        if deny_if_assign_task_misuse(command):
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
