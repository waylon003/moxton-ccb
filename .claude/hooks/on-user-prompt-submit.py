import json
import sys
import os
import tempfile

# Read stdin to prevent broken pipe
sys.stdin.read()

flag = os.path.join(tempfile.gettempdir(), "moxton-bootstrap-done.flag")

result = {}

if not os.path.exists(flag):
    result = {
        "hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": (
                "=== BOOTSTRAP 未完成 ===\n"
                "你必须先执行 bootstrap 才能进行任何操作：\n\n"
                "```bash\n"
                'powershell -NoProfile -ExecutionPolicy Bypass -File "E:\\moxton-ccb\\scripts\\teamlead-control.ps1" -Action bootstrap\n'
                "```\n\n"
                "当前仅允许 bootstrap/status + 审批处理（show-approval/approve-request/deny-request）；必要时可用 recover -RecoverAction baseline-clean 清理遗留 pending 审批。\n"
                "若你已执行 bootstrap 仍提示限制，请检查 $env:TEMP\\moxton-bootstrap-done.flag 是否存在。\n"
                "禁止直接调用子脚本（start-worker.ps1、dispatch-task.ps1 等）。\n"
                "禁止使用 powershell -Command 执行复杂逻辑。\n"
                "=== END ==="
            )
        }
    }
else:
    result = {
        "hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": (
                "Bootstrap 已完成。所有操作必须通过统一控制器：\n"
                'powershell -NoProfile -ExecutionPolicy Bypass -File "E:\\moxton-ccb\\scripts\\teamlead-control.ps1" -Action <action>\n'
                "可用 Action: dispatch / dispatch-qa / status / recover / add-lock / archive / approve-request / deny-request\n"
                "规划阶段禁止使用 assign_task.py 写入任务文件（--intake/--split-request/--lock-task 等）。\n"
                "规划阶段只输出任务草案；确认后按模板写入 01-tasks/active/*，再用 teamlead-control add-lock + dispatch 进入执行链路。\n"
                "禁止在 01-tasks/active 下用 rm/del 批量删除临时任务文件。\n"
                "禁止无退出条件轮询 worker 输出；同一 get-text/check_routes 无变化最多 3 轮，随后必须转 status/recover。\n"
                "禁止直接调用子脚本。禁止 powershell -Command 执行复杂逻辑。"
            )
        }
    }

print(json.dumps(result, ensure_ascii=False))
