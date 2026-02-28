import json
import sys
import os
import subprocess
import tempfile

# Read stdin to prevent broken pipe
sys.stdin.read()

# Clear old bootstrap flag on session start
flag = os.path.join(tempfile.gettempdir(), "moxton-bootstrap-done.flag")
if os.path.exists(flag):
    try:
        os.remove(flag)
        sys.stderr.write("Bootstrap flag cleared (new session).\n")
    except Exception:
        pass

# Display welcome message to stderr
sys.stderr.write("=" * 50 + "\n")
sys.stderr.write("Team Lead Mode Activated\n")
sys.stderr.write("=" * 50 + "\n")

# Get current task status
try:
    result = subprocess.run(
        ["python", "scripts/assign_task.py", "--show-task-locks"],
        capture_output=True,
        text=True,
        timeout=5
    )
    if result.returncode == 0:
        lines = result.stdout.split('\n')
        active_tasks = [l for l in lines if 'active-task' in l and ('BACKEND' in l or 'SHOP' in l or 'ADMIN' in l)]
        if active_tasks:
            sys.stderr.write("\n当前任务状态:\n")
            for task in active_tasks[:5]:
                sys.stderr.write(f"   {task}\n")
except Exception:
    pass

sys.stderr.write("\nTeam Lead 角色定义已注入\n")
sys.stderr.write("\n下一步: powershell -File scripts/teamlead-control.ps1 -Action bootstrap\n")
sys.stderr.write("=" * 50 + "\n\n")

# Read team-lead.md for context injection
try:
    team_lead_path = os.path.join('.claude', 'agents', 'team-lead.md')
    with open(team_lead_path, 'r', encoding='utf-8') as f:
        team_lead_content = f.read()

    # Read startup checklist
    checklist_path = os.path.join('.claude', 'STARTUP-CHECKLIST.md')
    startup_reminder = ""
    if os.path.exists(checklist_path):
        with open(checklist_path, 'r', encoding='utf-8') as f:
            startup_reminder = f"\n\n---\n\n# 启动提醒\n\n{f.read()}"

    # Bootstrap instruction
    bootstrap_instruction = (
        "\n\n---\n\n"
        "# 必须执行 Bootstrap\n\n"
        "新会话启动后，你必须首先执行 bootstrap：\n\n"
        "```bash\n"
        'powershell -NoProfile -ExecutionPolicy Bypass -File "E:\\moxton-ccb\\scripts\\teamlead-control.ps1" -Action bootstrap\n'
        "```\n\n"
        "**禁止**直接调用 start-worker.ps1、dispatch-task.ps1 等子脚本。\n"
        "**禁止**使用 powershell -Command 执行复杂逻辑。\n"
        "所有操作必须通过 teamlead-control.ps1 统一入口。"
    )

    full_context = f"{team_lead_content}{startup_reminder}{bootstrap_instruction}"

    result = {
        "hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": full_context
        }
    }
    print(json.dumps(result, ensure_ascii=False))
except Exception as e:
    sys.stderr.write(f"Hook error: {e}\n")
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": "Team Lead mode active. Run: powershell -File scripts/teamlead-control.ps1 -Action bootstrap"
        }
    }))
