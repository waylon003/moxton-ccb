import json
import sys

# Read hook input from stdin
try:
    hook_input = json.loads(sys.stdin.read())
    prompt = hook_input.get("prompt", "")
except:
    prompt = ""

# Exit cleanly - context guidance is already in CLAUDE.md and team-lead.md
sys.exit(0)
