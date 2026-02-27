import json
import sys
import os
import subprocess

# Read stdin to prevent broken pipe
sys.stdin.read()

# Display welcome message to stderr
sys.stderr.write("=" * 50 + "\n")
sys.stderr.write("🎯 CCB Team Lead Mode Activated\n")
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
        # Show only active tasks
        lines = result.stdout.split('\n')
        active_tasks = [l for l in lines if 'active-task' in l and ('BACKEND' in l or 'SHOP' in l or 'ADMIN' in l)]
        if active_tasks:
            sys.stderr.write("\n📊 当前任务状态:\n")
            for task in active_tasks[:5]:  # Show max 5 tasks
                sys.stderr.write(f"   {task}\n")
except Exception:
    pass

sys.stderr.write("\n✅ 环境变量: CCB_CALLER=claude (已自动设置)\n")
sys.stderr.write("✅ Team Lead 角色定义已注入\n")
sys.stderr.write("\n💡 下一步: python scripts/assign_task.py --standard-entry\n")
sys.stderr.write("=" * 50 + "\n\n")

# Read team-lead.md and STARTUP-CHECKLIST.md for context injection
try:
    # Read team-lead role definition
    team_lead_path = os.path.join('.claude', 'agents', 'team-lead.md')
    with open(team_lead_path, 'r', encoding='utf-8') as f:
        team_lead_content = f.read()

    # Read startup checklist
    checklist_path = os.path.join('.claude', 'STARTUP-CHECKLIST.md')
    startup_reminder = ""
    if os.path.exists(checklist_path):
        with open(checklist_path, 'r', encoding='utf-8') as f:
            startup_reminder = f"\n\n---\n\n# 启动提醒\n\n{f.read()}"

    # Combine context
    full_context = f"{team_lead_content}{startup_reminder}\n\n---\n\n**重要**: CCB_CALLER 环境变量已自动设置为 'claude'，Codex 完成任务后会自动通知你，无需手动轮询 `pend codex`。"

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
            "additionalContext": "Team Lead mode active. CCB_CALLER=claude is set."
        }
    }))
