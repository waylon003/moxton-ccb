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
                "当前只允许 bootstrap 和 status 操作。\n"
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
                "可用 Action: dispatch / dispatch-qa / status / recover / add-lock\n"
                "禁止直接调用子脚本。禁止 powershell -Command 执行复杂逻辑。"
            )
        }
    }

print(json.dumps(result, ensure_ascii=False))
