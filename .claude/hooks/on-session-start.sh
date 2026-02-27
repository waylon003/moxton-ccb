#!/bin/bash
# CCB Team Lead Session Initialization Hook
# This hook runs when Claude Code starts in E:\moxton-ccb

# Read stdin (hook input from Claude Code) to prevent broken pipe
cat > /dev/null

# Display welcome message to user (stderr only, won't interfere with JSON)
echo "CCB Team Lead Mode Activated" >&2

# Output JSON with additionalContext using Python for reliable JSON encoding
python -c "
import json, sys
try:
    with open('.claude/agents/team-lead.md', 'r', encoding='utf-8') as f:
        content = f.read()
    result = {'hookSpecificOutput': {'hookEventName': 'SessionStart', 'additionalContext': content}}
    print(json.dumps(result, ensure_ascii=False))
except Exception as e:
    print(json.dumps({'hookSpecificOutput': {'hookEventName': 'SessionStart', 'additionalContext': 'Team Lead mode active'}}))
"
