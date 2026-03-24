import json
import os
import sys
import tempfile

sys.stdin.read()

flag = os.path.join(tempfile.gettempdir(), "moxton-bootstrap-done.flag")

if not os.path.exists(flag):
    result = {
        "hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": (
                "=== BOOTSTRAP 未完成 ===\n"
                "你必须先执行 bootstrap，之后再进入任何调度或复审动作：\n\n"
                "```bash\n"
                'powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action bootstrap\n'
                "```\n\n"
                "bootstrap 之前，不要直接 dispatch / dispatch-qa / qa-pass / requeue / archive。\n"
                "若你已执行 bootstrap 仍提示限制，请检查 $env:TEMP\moxton-bootstrap-done.flag 是否存在。\n"
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
                'powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action <action>\n'
                "主链常用 Action: status / dispatch / dispatch-qa / qa-pass / requeue / recover / add-lock / archive\n"
                "当前主链默认无审批弹窗；不要主动建议任何审批动作，直接围绕 status / dispatch / dispatch-qa / qa-pass / requeue / recover / archive 决策。\n"
                "规划阶段禁止使用 assign_task.py 写入任务文件（--intake/--split-request/--lock-task 等）。\n"
                "规划阶段只输出任务草案；确认后按模板写入 01-tasks/active/*，再用 teamlead-control add-lock + dispatch 进入执行链路。\n"
                "禁止在 01-tasks/active 下用 rm/del 批量删除临时任务文件。\n"
                "禁止无退出条件轮询 worker 输出；同一 get-text/check_routes 无变化最多 3 轮，随后必须转 status/recover。\n"
                "符合既有链路的决策（如 qa-pass / requeue / recover / archive）必须直接执行，不要反问用户。\n"
                "禁止直接调用子脚本。禁止 powershell -Command 执行复杂逻辑。"
            )
        }
    }

print(json.dumps(result, ensure_ascii=False))
