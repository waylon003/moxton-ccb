# Tech-Spec：运营助手独立浮动聊天卡片

**任务ID:** ADMIN-FE-025  
**创建时间:** 2026-11-04  
**状态:** completed  
**执行模式:** codex-desktop  
**当前 attempt:** 2  
**角色:** admin-fe-dev / admin-fe-qa  
**项目:** moxton-lotadmin  
**优先级:** P1  
**技术栈:** Vue 3 + TypeScript + SoybeanAdmin + Naive UI + Playwright  
**QA_LEVEL:** full

## 执行上下文

- **工作目录**：`E:\moxton-ccb\runtime\worktrees\admin-floating-chat-025`
- **分支**：`codex/admin-floating-chat-025`
- **基线提交**：`f25449024a7cb63525fae8cbcabfdc7963b52179`
- 原后台主工作区含已验收但未提交的业务集成和助手实现，已复制到隔离 worktree。清单、初始状态和入口文件 SHA-256 见 `runtime/assistant-round-20261104/admin-025-baseline.json`；主工作区未改。依赖通过本地 `node_modules` junction 复用，不复制 `.env`、密钥或运行态文件。
- **允许文件仅限**：
  - `src/layouts/modules/operations-assistant/index.vue`
  - `src/layouts/modules/operations-assistant/chat-panel.vue`
  - `tests/e2e/operations-assistant.spec.ts`
- **依赖**：已完成 `ADMIN-FE-024`；保持既有 `/agent/admin/capabilities`、`/agent/admin/chat`、180000毫秒后端预算、190000毫秒前端截止、Pinia 会话/权限/安全引用合同。
- **必读**：`E:\moxton-ccb\AGENTS.md`、本任务、`E:\moxton-lotadmin\AGENTS.md`、`E:\moxton-ccb\03-guides\codex-desktop-workflow.md`、`desktop-smoke-checklist.md`、`.codex\agents\admin-fe-dev.toml` 或 `admin-fe-qa.toml`、`02-api\operations-assistant.md`、已完成任务 `ADMIN-FE-024`。
- **证据**：`E:\moxton-ccb\05-verification\ADMIN-FE-025\attempt-2\`；attempt 1 及其 QA 报告保留。主会话视觉复核发现背景透字、等待阶段无用户气泡，返修后重新验收。
- 开发者只改授权文件，不改任务状态、STATUS、CURRENT-ROUND 或其他仓；不提交、推送、部署、不派下级代理。QA 使用新上下文复核准确 worktree，父会话唯一维护主状态。

## 问题陈述

目前全局运营助手使用右侧 `NDrawer`。用户确认希望采用常见客服/AI 助手式的独立浮动聊天卡片：不遮罩主页面，支持拖动和调整大小；发送查询时需要清楚的用户/助手消息气泡和聊天布局。

## 解决方案

保留助手挂载在 `BaseLayout`、现有 Pinia/API、权限、账号隔离历史、引用安全和请求生命周期，只替换窗口容器与聊天呈现。桌面默认约 `420x640`，标题栏拖动，右下角拖动手柄调整大小；位置/尺寸按当前浏览器保存并在刷新后恢复。窗口关闭只隐藏，不卸载 `ChatPanel`、不取消请求。窄屏采用视口内安全尺寸，防止卡片不可达或横向溢出。

消息区按对话呈现：用户气泡靠右，助手气泡靠左；统计、筛选、引用及查询时间属于助手消息内容；消息区独立滚动，底部输入区固定。保留加载、取消、重试、不可用和失败状态及中文/英文。

## 范围

**包含：**

- 在 `index.vue` 将抽屉替换为固定浮动卡片，实现打开/隐藏、拖动、缩放、边界限制、尺寸/位置恢复与窄屏约束。
- 在 `chat-panel.vue` 将现有 `<p>` 对话展示调整为可辨识的左右聊天气泡，重排统计/筛选/引用，保持输入栏固定在卡片底部。
- 更新 `operations-assistant.spec.ts`，覆盖拖动、缩放、刷新恢复、关闭/页面切换请求持续、消息样式、窄屏、权限和既有失败路径；截图、trace 和附件保存到 attempt-1。

**不包含：**

- 不改后端、API 响应、数据库、商城、认证、会话合同、模型/工具策略或生产配置。
- 不改变请求取消规则：关闭/导航不取消；显式取消、登出、换号或权限撤销仍取消。
- 不新增第三方依赖。

## 实施要求

- 浮窗始终挂载在 `BaseLayout`；隐藏使用 `v-show` 等不卸载方式。拖动和缩放用 Pointer Events/CSS 实现，遵循现有 Vue 模式。
- 默认桌面尺寸约 `420x640`；最小宽高 `340x420`；最大尺寸不超过视口安全边界。窗口位置始终可拖回视口内。窄屏时采用接近全屏但留出安全边距的布局。
- 拖动仅由标题栏非按钮区域触发；关闭按钮不触发拖动。缩放手柄有可访问名称与稳定 `data-testid`。
- 存储位置/尺寸时校验数值和边界；本地存储失败时降级到默认尺寸/位置，不影响会话。
- 现有 `assistant-launcher`、`assistant-question`、`assistant-turn` 等钩子兼容保留；新增 `assistant-window`、drag/resize 手柄和消息角色钩子用于 E2E。

## 验收标准

- [x] 浮窗为非模态独立卡片，主页面无遮罩且可继续操作；默认尺寸、最小/最大尺寸符合边界。
- [x] 标题栏可拖动，拖动不会误触关闭；窗口不会移出视口，刷新恢复位置/尺寸。
- [x] 右下角手柄可调整宽高；助手卡片在窄屏无横向溢出，窗口和关闭按钮始终可达。
- [x] 用户消息右对齐、助手回复左对齐；发送后立即呈现用户/等待气泡；统计/筛选/引用属于对应回复，输入区固定在底部。
- [x] 关闭窗口、跨管理页面导航和重开不取消请求、不重复调用；显式取消/登出/身份变化仍中止请求。
- [x] admin/operator 可见，普通用户和登录布局不可见；引用仍经 `safeReference`，统计、失败、重试和历史合同不回归。
- [x] 中文、英文、桌面及390px助手布局通过；正常链路 console error_count=0，正常请求无未处理5xx；预期失败独立记录。
- [x] E2E 25/25、typecheck、全仓只读 ESLint（0 errors/82条旧 warnings）、build:test、diff-check 均成功。
- [x] 独立 admin-fe-qa full 验收，补充8/8，frontend validator valid=true。

## TDD 与证据

先新增拖动/缩放/气泡 E2E，旧 Drawer 预期 RED 后实现；attempt 2 补不透明表面和即时气泡 RED/GREEN。最新证据使用 `--output=E:\moxton-ccb\05-verification\ADMIN-FE-025\attempt-2\...`，attempt 1 与 ADMIN-FE-024 证据保留。

## 最终交付

- attempt 2 独立 QA PASS，`05-verification/ADMIN-FE-025/attempt-2/result.json` 和 `qa-report.md`；最终只读代码审查 Clean。
- 三个授权文件已按冻结 SHA-256 集成到 `E:\moxton-lotadmin`，备份和前后哈希见 `runtime/assistant-round-20261104/admin-025-integration-applied.json`。
- 已重新启动原后台9527开发服务；两个实际 Vue 模块 HTTP 200 且包含新浮窗/即时气泡标识，见 `admin-025-live-modules.json`。
- 未提交、推送、部署。未联调真实模型/客户数据，未进行实机软键盘/触控测试；底层原页头在窄屏仍有既有超宽，助手自身及后代无越界，详见 QA 报告。

## 风险与回退

拖动手势可能影响触屏和标题栏按钮，使用 pointer capture 并将拖动区域限定在标题栏空白区；触屏窄屏禁用拖动/缩放或确保控制柄易用。若浮动交互导致请求生命周期问题，可回退窗口外观但必须保留此前已验收的 BaseLayout 挂载与会话行为。
