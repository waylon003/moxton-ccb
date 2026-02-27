#!/bin/bash
# CCB Task Completion Hook
# Validates that proper QA evidence exists before allowing task completion

TASK_ID="$1"

if [ -z "$TASK_ID" ]; then
    echo "⚠️  No task ID provided to completion hook"
    exit 0
fi

echo ""
echo "🔍 Validating task completion: $TASK_ID"
echo ""

# Check if task lock exists
LOCK_FILE="01-tasks/TASK-LOCKS.json"
if [ ! -f "$LOCK_FILE" ]; then
    echo "❌ TASK-LOCKS.json not found"
    exit 1
fi

# Check if task is in QA or completed state
TASK_STATE=$(python3 -c "
import json
import sys
try:
    with open('$LOCK_FILE', 'r', encoding='utf-8') as f:
        data = json.load(f)
    locks = data.get('locks', {})
    if '$TASK_ID' in locks:
        print(locks['$TASK_ID'].get('state', 'unknown'))
    else:
        print('not_found')
except Exception as e:
    print('error')
    sys.exit(1)
")

if [ "$TASK_STATE" = "not_found" ]; then
    echo "⚠️  Task $TASK_ID not found in locks"
    exit 0
fi

if [ "$TASK_STATE" != "qa" ] && [ "$TASK_STATE" != "completed" ]; then
    echo "❌ Task state is '$TASK_STATE', must be 'qa' or 'completed'"
    echo "✅ Required: Task must pass through QA verification"
    exit 1
fi

# Check if QA evidence exists
EVIDENCE_DIR="05-verification/ccb-runs"
EVIDENCE_COUNT=$(find "$EVIDENCE_DIR" -name "*$TASK_ID*" 2>/dev/null | wc -l)

if [ "$EVIDENCE_COUNT" -eq 0 ]; then
    echo "⚠️  No QA evidence found in $EVIDENCE_DIR"
    echo "✅ Recommendation: Run QA verification before marking complete"
    exit 1
fi

echo "✅ Task $TASK_ID validation passed"
echo "   - State: $TASK_STATE"
echo "   - Evidence files: $EVIDENCE_COUNT"
echo ""
