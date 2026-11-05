# 全局运营助手实施计划

> **代理执行要求：**按任务逐项实施；推荐使用 `superpowers:subagent-driven-development`，也可由主会话使用 `superpowers:executing-plans`。各步骤使用复选框跟踪。

**目标：**把只读运营助手移入后台全局悬浮聊天窗，使请求在业务页面导航和窗口隐藏期间继续运行，并将单轮预算提高至3分钟。

**架构：**助手悬浮按钮和抽屉挂载于持久的 `BaseLayout`，复用现有 Pinia 会话、助手 API、认证身份和结果渲染。删除独立助手页、菜单项和 URL；后端总预算设为180秒，浏览器等待预算设为190秒。

**技术栈：**Vue 3、Pinia、Vue Router、Naive UI、Playwright、Koa、TypeScript、Vitest。

**规格：**[全局运营助手设计规格](../specs/2026-11-04-global-operations-assistant-design.md)

## 全局约束

- 仅 `admin` 和 `operator` 可以使用助手。
- 后端单轮总预算180秒；前端 HTTP 与 store 截止时间190秒。
- 单轮最多4次模型请求、6次工具执行；不自动重试。
- 模型固定 `gpt-6.1-sol`；数据源保持本地 `moxton_local`。
- 保留会话按账号隔离、7天、最近10个会话、每会话最近10轮。
- 关闭悬浮窗和切换管理页面不取消请求；显式取消、登出、账号变化或权限撤销会取消请求。
- 删除旧菜单、`/operations-assistant` 路由及生成类型，不添加重定向入口。
- 不改商城、数据库结构、认证合同或业务查询工具；不访问真实客户数据或真实模型。
- 保留两个业务仓与文档中心现有未提交改动；不切换分支、不自动提交、推送或部署。

## 复核重点

- 请求中关闭抽屉并跨页面导航，再打开后必须看到同一请求的最终结果，且网络请求只发出一次。
- 190秒前返回的响应不能被客户端本地截止误取消；190秒后必须中止且不保存迟到结果。
- 退出或切换账号时，旧账号的请求响应不能写入新账号会话。
- 悬浮面板中的引用必须仍经过 `safeReference` 校验，且跳转后不覆盖目标详情。
- 普通账号及空白登录布局不能显示悬浮入口。

---

### Task 1: 后端助手预算改为三分钟（BACKEND-031）

**文件：**
- 修改：`E:\moxton-lotapi\src\services\agent\AgentService.ts`
- 测试：`E:\moxton-lotapi\tests\api\agent.spec.ts`
- 任务及证据：`E:\moxton-ccb\01-tasks\active\backend\BACKEND-031-agent-timeout-budget.md`、`E:\moxton-ccb\05-verification\BACKEND-031\attempt-1\`

**接口：**
- 消费：当前能力接口 `{ limits: { timeoutMs: 90000 } }`；聊天模型循环最多4次、工具最多6次。
- 产出：能力接口报告 `timeoutMs: 180000`；同一 AbortSignal 覆盖鉴权、模型和工具的180秒总预算。

- [ ] **步骤1：创建正式任务记录**

创建 `BACKEND-031` 为 `planned / attempt 0 / QA_LEVEL=full`，记录后端当前 HEAD `234a7f5f26745d301fca0eb45ebf5a19e3e98d90`、既有集成改动和精确允许文件。开始实施时由主会话更新为 `in_progress / attempt 1`。

- [ ] **步骤2：先改能力与超时回归断言**

在 `tests/api/agent.spec.ts` 中把能力断言改为 `timeoutMs: 180000`，把模型超时和数据库授权超时测试分别改为推进虚拟时钟 `180001` 毫秒，并将标题改为180秒。现有实现仍为90000时运行定向测试，必须因能力值不符而失败。

```powershell
npm.cmd test -- tests/api/agent.spec.ts
```

预期：测试失败，实际能力仍返回90000；超时测试的新180秒断言也不能通过。

- [ ] **步骤3：调整最小生产配置**

只将 `AgentService.ts` 中 `LIMITS.timeoutMs` 改为 `180000`。保留请求/工具上限、AbortSignal 传播、并发控制和错误包装。

```ts
const LIMITS = { historyTurns: 10, modelRequests: 4, toolCalls: 6, timeoutMs: 180000 };
```

- [ ] **步骤4：运行后端测试及构建**

```powershell
npm.cmd test -- tests/api/agent.spec.ts
npm.cmd test
npx.cmd tsc -p tsconfig.json --noEmit --pretty false
npm.cmd run build
```

预期：定向与全量测试、全量类型检查、完整构建均退出0；能力端点单测报告180000；虚拟时钟推进180001后模型和数据库授权均返回504，且正在进行的模型收到abort。

- [ ] **步骤5：冻结开发结果**

保存脱敏开发摘要和源码 manifest，进入 `waiting_qa`；不更改任务状态为通过。文档中心 API 契约由主会话在联合集成任务中同步。

- [ ] **步骤6：由独立 backend-qa 验收**

新上下文在准确的 `E:\moxton-lotapi` 验收 `BACKEND-031 / attempt 1`，复核超时、能力合同、AbortSignal 与调用上限，运行必要全量命令。证据必须含 contract、network、failure_path 和 `result.json`，并由 `validate-desktop-result.py --kind backend` 校验。

### Task 2: 全局浮窗、前端预算与旧路由移除（ADMIN-FE-024）

**文件：**
- 新建：`E:\moxton-lotadmin\src\layouts\modules\operations-assistant\index.vue`
- 新建：`E:\moxton-lotadmin\src\layouts\modules\operations-assistant\chat-panel.vue`
- 移动：`src\views\operations-assistant\labels.ts` 至 `src\layouts\modules\operations-assistant\labels.ts`
- 修改：`src\layouts\base-layout\index.vue`、`src\store\modules\operations-assistant\index.ts`、`src\service\api\operations-assistant.ts`
- 移除：`src\views\operations-assistant\index.vue`
- 更新生成路由：`src\router\elegant\routes.ts`、`imports.ts`、`transform.ts`、`src\typings\elegant-router.d.ts`
- 修改：`src\router\routes\index.ts`、`src\locales\langs\zh-cn.ts`、`src\locales\langs\en-us.ts`
- 测试：`tests\e2e\operations-assistant.spec.ts`
- 任务及证据：`E:\moxton-ccb\01-tasks\active\admin-frontend\ADMIN-FE-024-global-operations-assistant.md`、`E:\moxton-ccb\05-verification\ADMIN-FE-024\attempt-1\`

**接口：**
- 消费：后端 `timeoutMs: 180000`；既有 store 的 `send`、`cancel`、`setIdentity`、会话操作和安全引用函数。
- 产出：`BaseLayout` 常驻助手；旧助手路由及其 `RouteKey` 被移除；前端 HTTP 与 Pinia 截止值统一190000；窗口隐藏不调用 `cancel`。

- [ ] **步骤1：创建正式任务记录**

创建 `ADMIN-FE-024` 为 `planned / attempt 0 / QA_LEVEL=full`，记录后台当前 HEAD `f25449024a7cb63525fae8cbcabfdc7963b52179`、既有未提交及未跟踪内容（包括 `dist.zip`）和允许文件。开始实施时由主会话更新为 `in_progress / attempt 1`。此时 `STATUS.md` 从4个活跃/79个完成/83个总计调整为6个活跃/79个完成/85个总计；仅新增这两项跟进任务。

- [ ] **步骤2：先用当前页面复现导航取消**

先不改 `boot` helper，继续从现有 `/operations-assistant` 页面开始。新增一个门控聊天请求：发送问题、通过 Naive 菜单导航到商品页，再经现有“运营助手”菜单返回，释放延迟响应并断言应恢复一条会话。当前页面卸载会调用 `assistant.cancel()`，所以断言应失败且没有会话被保存；这证明测试复现的是导航中断，而非浮窗尚未存在。

```ts
test('路由切换不会丢失助手请求', async ({ page }) => {
  await boot(page);
  let release!: () => void;
  const gate = new Promise<void>(resolve => { release = resolve; });
  let calls = 0;
  await page.route('**/agent/admin/chat', async route => {
    calls += 1;
    await gate;
    await route.fulfill({ json: success(result) }).catch(() => {});
  });
  await ask(page);
  await page.getByRole('menuitem', { name: '商品管理' }).click();
  await expect(page).toHaveURL(/\/product/);
  await page.getByRole('menuitem', { name: '运营助手' }).click();
  release();
  await expect(page.getByTestId('assistant-turn')).toHaveCount(1);
  expect(calls).toBe(1);
});
```

运行单个新用例，预期页面卸载后请求被取消、返回时没有已完成会话；记录 RED 证据，不改生产组件。全局窗口实现后，将此用例改为 `/home` 的助手按钮入口，并在商品页关闭/重开抽屉后断言同一结果。

```powershell
pnpm.cmd exec playwright test tests/e2e/operations-assistant.spec.ts --grep "路由切换不会丢失助手请求"
```

- [ ] **步骤3：建立 BaseLayout 浮窗容器**

创建 `layouts/modules/operations-assistant/index.vue`：使用 `NButton` 固定右下角、`NTooltip`、`NDrawer placement="right" :mask="false" display-directive="show"` 与 `NDrawerContent closable`；桌面宽度受限为520px，窄屏宽度为100vw。管理员和运营角色可见；其他角色不渲染按钮。抽屉关闭只写 `visible=false`，不得调用聊天 store 的 `cancel`。

- [ ] **步骤4：将既有页面提取为常驻聊天面板**

将助手页面现有内容迁移到 `chat-panel.vue`，移动 `labels.ts`，保留统计卡、引用校验、筛选、时间、错误态和中英文。把宽屏侧边会话卡改为适合520px抽屉的会话选择和新建/删除/清空控件。将面板放在 `display-directive="show"` 的抽屉内持续挂载；引用点击先向父组件发 `navigate`，父组件关闭抽屉，再使用 `safeReference` 验证并导航。

登录身份变化仍通过现有 `setIdentity` 清空/恢复账号历史；登出时现有 `resetStore()` 调用 `clearMemory()` 并中止请求。只保留在真正卸载 BaseLayout 时的卸载清理，不在抽屉关闭或业务路由切换时取消。

- [ ] **步骤5：把组件挂到 BaseLayout**

在 `src/layouts/base-layout/index.vue` 的 `AdminLayout` 内容中，作为 `GlobalContent` 的同级挂载助手组件。不要挂到当前路由页面或 blank/login layout。确认页面子路由从商品切换到预售、测试申请时 BaseLayout 实例保持复用。

- [ ] **步骤6：同步180/190秒预算**

将 `src/service/api/operations-assistant.ts` 的 Axios `timeout` 和 Pinia store 的本地 `setTimeout` 都改为190000；API 响应 mock 使用 `timeoutMs: 180000`。保留超时取消和504提示，不增加重试。

- [ ] **步骤7：删除旧页面、菜单、URL和类型**

移除 `src/views/operations-assistant/index.vue`；运行 `pnpm gen-route` 更新 `routes.ts`、`imports.ts`、`transform.ts` 和 `elegant-router.d.ts`；从 `src/router/routes/index.ts` 移除助手特殊角色/菜单逻辑；从中英文 `route` 节点移除 `operations-assistant` 键，但保留 `page.operationsAssistant` 文案。不能添加旧 URL 重定向。

```powershell
pnpm.cmd gen-route
```

E2E 从 `/home` 打开悬浮助手；新增直接访问 `/operations-assistant` 落入现有404处理的断言。检查生成差异只包含移除助手 route key 和 import。

- [ ] **步骤8：调整 E2E 入口和独立证据目录**

将 `boot` helper 与所有直接路径调用改为 `/home` 后点击“打开运营助手”；`reloadAssistant` 刷新后重新打开窗口。将导航 RED 用例改为关闭窗口、切换到商品页、重新打开并释放同一个请求，断言请求完成一次且响应可见。增加虚拟时钟推进100001毫秒后正常释放并保存结果的成功用例；把现有超时用例推进190001毫秒，断言504提示且迟到结果不入历史。新增旧 URL `/operations-assistant` 进入现有404页面的断言。把测试截图和附件路径从 `ADMIN-FE-023/attempt-2` 改到 `ADMIN-FE-024/attempt-1`，保留旧证据不变。保留并改写已有登出、账号隔离、取消、历史、详情和本地化测试，使它们通过全局窗口入口执行。

- [ ] **步骤9：运行前端行为与质量检查**

```powershell
pnpm.cmd exec playwright test tests/e2e/operations-assistant.spec.ts --workers=2 --trace on
pnpm.cmd typecheck
pnpm.cmd exec eslint . --no-fix
pnpm.cmd build:test
```

预期：跨路由延迟查询、关闭/重开、>100秒成功、190秒超时、权限/登出/账号隔离、历史、引用、旧路由404和中英文均通过；桌面与390px视口无新增溢出；ESLint为0 errors且warning不高于82。

- [ ] **步骤10：冻结并由独立 admin-fe-qa 验收**

精确记录授权文件与 SHA-256、Playwright trace、截图、console/network/failure_path。新的 `admin-fe-qa` 上下文复核准确 `E:\moxton-lotadmin`，独立运行全量适用检查并对照设计规格。保存 `result.json` 后运行 `validate-desktop-result.py --kind frontend`。

### Task 3: 联合集成、文档和归档

**文件：**`E:\moxton-ccb\02-api\operations-assistant.md`、`03-guides\operations-assistant-local.md`、`01-tasks\STATUS.md`、`04-projects\CURRENT-ROUND.md`、两份正式任务、`05-verification\<TASK-ID>\summary.md` 和 `runtime\assistant-round-20261104\progress.md`。

**接口：**确认后台 UI 使用能力接口的180000服务预算、客户端190000等待；旧 `/operations-assistant` 路由不存在；不改既有聊天 JSON 合同。

- [ ] **步骤1：并行开发期间只协调固定接口**

BACKEND-031 与 ADMIN-FE-024 可在不同仓库并行；各仓同一时间只有一个开发写入者。开发代理只改本仓授权文件，不编辑文档中心记录；主会话维护任务状态、API/指南和进度。两个源仓当前工作区都已包含未提交集成结果，按此现状工作，不从 `HEAD` 覆盖或重新恢复旧快照。

- [ ] **步骤2：完成跨仓文档同步**

将 API 能力样例和本地使用说明写为180/190秒；注明窗口关闭/导航不取消、显式取消仍有效。保留既有90秒 QA 失败证据，不改写历史结果，增加本次修正摘要。

- [ ] **步骤3：本地主会话复验**

无需启动真实模型、连接数据库或填充业务数据。后端运行 `npm test`、全量 `tsc`、`npm run build`；后台运行任务级 E2E、`pnpm typecheck`、只读 ESLint、`pnpm build:test`；确认旧 route 生成引用已清除且原有未提交文件仍在。

- [ ] **步骤4：核实证据并完成状态迁移**

父会话阅读两份独立 QA 报告和限制、逐项运行结果 validator、复核变更文件与证据。仅在两个任务均 QA PASS 后将 BACKEND-031、ADMIN-FE-024 移入 `completed/`，更新 `STATUS.md` 计数为4个活跃/81个完成/85个总计、`CURRENT-ROUND.md` 和恢复进度。原四项 `migration_hold / attempt 0` 保持不变。

- [ ] **步骤5：检查未提交工作区并收尾**

运行三个仓库的 `git status --short --branch` 与文档 `git diff --check`。保留原有分支及未提交改动；不提交、推送、部署或改生产配置。完成后留下后端3033、后台9527的可用本地入口和未测限制。

