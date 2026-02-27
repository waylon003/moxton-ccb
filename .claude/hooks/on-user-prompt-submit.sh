#!/bin/bash
# CCB Team Lead Prompt Analysis Hook
# Analyzes user input and suggests appropriate actions

USER_INPUT="$1"

# Check if user is requesting development plan creation
if echo "$USER_INPUT" | grep -qiE "(编写|创建|写|生成).*(开发计划|任务|plan|task)|(开发计划|任务).*(编写|创建|写|生成)|拆分.*需求|split.*request"; then
    echo ""
    echo "💡 Detected: Development plan request"
    echo "📝 Recommendation: Use /development-plan-guide skill for proper task template and role assignment"
    echo ""
fi

# Check if user is requesting task dispatch
if echo "$USER_INPUT" | grep -qiE "dispatch|分派|执行|开始|start.*task"; then
    echo ""
    echo "💡 Detected: Task dispatch request"
    echo "🚀 Recommendation: Use 'python scripts/assign_task.py --dispatch-ccb <TASK-ID>'"
    echo ""
fi

# Check if user is requesting status check
if echo "$USER_INPUT" | grep -qiE "状态|status|进度|progress|poll"; then
    echo ""
    echo "💡 Detected: Status check request"
    echo "📊 Recommendation: Use 'python scripts/assign_task.py --poll-ccb <REQ-ID>'"
    echo ""
fi

# Check if user is trying to edit code directly
if echo "$USER_INPUT" | grep -qiE "(修改|编辑|改|fix|update|edit).*(nuxt-moxton|lotadmin|lotapi|E:\\\\nuxt|E:\\\\moxton)"; then
    echo ""
    echo "⚠️  WARNING: Team Lead should NOT directly edit business code"
    echo "✅ Correct approach: Create task → Dispatch to worker via CCB"
    echo ""
fi

# Check if user wants to see active tasks
if echo "$USER_INPUT" | grep -qiE "有.*任务|任务.*列表|list.*task|active.*task|show.*task"; then
    echo ""
    echo "💡 Detected: Task list request"
    echo "📋 Recommendation: Use 'python scripts/assign_task.py --list'"
    echo ""
fi
