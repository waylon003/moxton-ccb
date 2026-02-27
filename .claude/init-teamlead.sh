#!/usr/bin/bash
# Team Lead 快速启动脚本
# 用法: source .claude/init-teamlead.sh

echo "=========================================="
echo "🎯 Team Lead 初始化"
echo "=========================================="

# 1. 设置环境变量
export CCB_CALLER=claude
export PATH="$PATH:/d/WezTerm-windows-20240203-110809-5046fc22"

echo "✅ 环境变量已设置"
echo "   CCB_CALLER=$CCB_CALLER"

# 2. 验证工具
echo ""
echo "🔍 验证工具..."

if command -v wezterm &> /dev/null; then
    echo "   ✅ WezTerm: $(wezterm --version 2>&1 | head -1)"
else
    echo "   ❌ WezTerm 未找到"
fi

if command -v ccb &> /dev/null; then
    echo "   ✅ CCB: $(ccb --version 2>&1 | head -1)"
else
    echo "   ❌ CCB 未找到"
fi

# 3. 确认角色
echo ""
echo "=========================================="
echo "📋 你的角色: Team Lead"
echo "=========================================="
echo "✅ 允许: 需求分析、任务拆分、CCB协调"
echo "❌ 禁止: 直接修改业务代码（必须通过Codex）"
echo ""

# 4. 显示当前任务状态
echo "📊 当前任务状态:"
python scripts/assign_task.py --show-task-locks 2>/dev/null | grep -E "BACKEND|SHOP|ADMIN" | head -10

echo ""
echo "=========================================="
echo "🚀 下一步: 运行标准入口点"
echo "=========================================="
echo "   python scripts/assign_task.py --standard-entry"
echo ""
