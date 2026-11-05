# ADMIN-FE-028 验收摘要

**任务：** 运营助手合并问卷统计分组展示
**Attempt：** 1
**结论：** `dev_verified`，主会话复核后 completed；按低风险展示调整未触发独立 QA。

## 结果

- 相同统计键、总数、单位和非分组筛选范围的多个指标合并为一张卡片，总数只显示一次。
- 每种可识别的 `groupBy` 都显示对应中英文标题；不同总数、不同筛选条件保持单独卡片。
- API 合同和数据库查询未改。

## 验证

- `PLAYWRIGHT_BASE_URL=http://127.0.0.1:9527`、`PLAYWRIGHT_SKIP_WEBSERVER=1` 下运行分组/国家范围定向 E2E：1/1 通过。
- 同一环境下运行既有英文统计展示 E2E：1/1 通过，覆盖总数相同的分组归并、总数不同的分布分离和英文标签。
- `pnpm typecheck`：退出码 0。
- 改动文件 ESLint `--no-fix`：0 errors、0 warnings；只有 `baseline-browser-mapping` 依赖数据过期提示。
- `git diff --check`：退出码 0。
- 浏览器截图：[统计分组展示](./attempt-1/ui-feedback-groups.png)。

## 限制

未运行全量 Playwright、全仓 lint 或构建；使用助手接口合成响应，没有真实模型/客户联调。
