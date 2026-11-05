# BACKEND-033 验收摘要

**任务：** 运营助手问卷统计摘要去重
**Attempt：** 1
**结论：** `dev_verified`，主会话复核后 completed；按低风险助手文本调整未触发独立 QA。

## 结果

- 同一请求的问卷统计结果在非分组筛选与总数相同时，兜底答复合并成一个自然摘要，只报告一次问卷总数，并说明下方卡片中的统计维度。多选选项数不相加成提交数。
- 经事实检查的模型回答会移除完全重复的行；系统提示要求合并相关工具结果、避免复述总数、自然作答且不照抄用户问题。
- API 响应、查询、数据来源与只读边界未变。

## 验证

- `pnpm exec vitest run --config vitest.config.ts tests/api/agent.spec.ts -t '相同问卷总数'`：1/1 通过，202 项跳过。
- `pnpm exec vitest run --config vitest.config.ts tests/api/agent.spec.ts -t '三个问卷分组被拒绝'`：1/1 通过，202 项跳过。
- `npx tsc --noEmit --pretty false --skipLibCheck`：退出码 0。
- `git diff --check`：退出码 0。

## 限制

未运行全量后端测试或真实模型网关联调；用例使用合成数据库与合成模型响应。
