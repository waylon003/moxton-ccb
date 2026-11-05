# Tech-Spec: 后台运营助手页面与浏览器会话

**任务ID:** ADMIN-FE-023
**创建时间:** 2026-11-03
**状态:** completed
**执行模式:** codex-desktop
**当前 attempt:** 2
**角色:** admin-fe-dev / admin-fe-qa
**项目:** moxton-lotadmin
**优先级:** P1
**QA_LEVEL:** full

## 上下文与范围

- 目录：`E:\moxton-ccb\runtime\worktrees\admin-assistant`；依赖两基线任务独立QA通过。API契约固定可与BACKEND-030并行，先mock后真实联调。
- 必读：工作区AGENTS、开发/QA角色TOML、实施计划和`E:\moxton-ccb\02-api\operations-assistant.md`。
- 允许：新增operations-assistant页面/子组件/store/API/type，中英文、菜单/生成路由、必要权限和认证重置hook、预售/产品详情ID入口。原有业务功能保留。不改商城/数据库/后端。
- 证据：`05-verification/ADMIN-FE-023/attempt-1/`；dev-report.md；独立QA result.json与ui/console/network/failure_path。不得改任务主记录、不提交推送或派下级。

## 产品与交互

新增admin/operator独立页面菜单；桌面会话列表+消息，窄屏会话选择折叠。沿用Naive UI和主题；中英文完整。提供4条预售/测试申请/问卷示例问题，回答纯文本，工具统计卡片、筛选条件、时间与实际记录引用。capabilities未启用时显示明确不可用，不发送聊天。

POST JSON按合同，history最近10轮且仅脱敏文本；请求100秒独立timeout并传AbortSignal。loading防连点、取消/重试/空状态/错误；取消或换号后不能追加旧响应。返回references只允许合同规定本地路径，禁止任意外链或执行HTML。

按环境+登录userId隔离历史，保留7天/最近10会话/会话10轮；成功响应后才落盘用户文本和必要结构化结果，422原文不落盘。复用现有storage封装，明确用户切换时abort+清内存、本人再登录可恢复。过期/损坏数据清理、quota错误降级内存并提示。支持新会话、删除、全部清空。

预售增加route.query.id打开详情，测试申请复用现有id逻辑（支持同页query切换）；product引用按id打开详情或定位该产品，保持原列表/修改操作。详情页面中的客户数据不进入聊天history/local storage。

## 验收

先写有意义Playwright行为测试，覆盖权限、示例问题、filters/metrics/引用、history刷新恢复/账号隔离/7天/10会话、删除清空、坏存储、422/503/超时/取消、窄屏/中英文、注入HTML不执行。

pnpm typecheck、eslint --no-fix（0errors、warnings不新增）、pnpm build:test通过。mock API和真实本地后端分开记录；独立QA真实问答与合成记录核对，console0、正常network无5xx，失败路径明记。原有4任务状态不由本任务推进。

## 派遣基线

两基线任务独立PASS/校验器通过。助手阶段准确起点按 runtime/assistant-round-20261103/backend-feature-baseline.json 或 admin-feature-baseline.json核对，不按HEAD回退。attempt1证据和开发报告按任务规定。

## 开发交付

源码冻结14修改+8新增，15E2E/typecheck/eslint/build:test均0，lint0errors/82warnings；待新的独立QA及受保护真实后端联合验收。主会话接收waiting_qa后派admin-fe-qa，状态qa/attempt1。

## attempt 1 独立FAIL / attempt 2返修

独立QA及最终代码审查确认英文metric卡片直接显示后端中文label，属于本轮i18n缺口。旧FAIL result和截图留在attempt-1；后端有安全返修，真实联合未测。首轮E2E瞬态资源失败不能追溯URL，后续15/15已复核，保留诊断不伪造。

attempt2只改助手labels/页面/对应中英文类型与有意义E2E回归：按稳定metric.key映射标题，恢复已有会话和切语言也生效；分布枚举（邮件/申请状态、问卷选项）同样映射为用户当前语言，地区名/实际ID/日期原值保留。不要用mock英文label掩盖真实后端中文label。先写英文统计标题/历史恢复测试RED，再修并跑全量typecheck/lint/build/E2E。冻结新manifest后独立QA复验及新后端真实浏览器联合方能PASS。不改旧业务页面、不新增依赖。新证据仅attempt-2，不覆盖旧attempt。

## attempt 2开发冻结

仅6授权文件修复标题/分布翻译，18E2E、typecheck/lint/build均0，0errors82warnings；完整22助手文件manifest冻结。等待独立复验和后端修复后联合验收，状态qa/attempt2。

## attempt 2独立QA PASS

18项E2E、typecheck、eslint、build及真实本地联合验收通过；三类真实查询、引用详情、同页ID、英文历史恢复和敏感输入422均有证据，validator valid=true。复杂复合问题一次网关延迟504按失败路径保留，不影响只读预算保护结论。

## 集成复验与归档

2026-11-04 在集成后的 `E:\moxton-lotadmin` 复验：`pnpm typecheck`、`pnpm exec eslint . --no-fix`、`pnpm build:test` 均退出0；lint 为0 errors、82条既有 warnings。attempt 2 独立QA和结果校验器通过。真实复合问题的一次90秒预算504仍按失败路径保留，现标记 completed。
