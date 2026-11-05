# Tech-Spec: 管理后台 lint 基线修复

**任务ID:** ADMIN-FE-022
**创建时间:** 2026-11-03
**状态:** completed
**执行模式:** codex-desktop
**当前 attempt:** 1
**角色:** admin-fe-dev / admin-fe-qa
**项目:** moxton-lotadmin
**优先级:** P1
**QA_LEVEL:** full

## 执行上下文

- 目录：`E:\moxton-ccb\runtime\worktrees\admin-assistant`；HEAD `f25449024a7cb63525fae8cbcabfdc7963b52179` 加已恢复原未提交/未跟踪业务源码。不得按HEAD覆盖它们，不改原仓。
- 必读：本任务、工作区AGENTS.md、文档中心工作流、角色TOML、实施计划。
- 允许：eslint报错23文件及必要调用方/测试/路由类型生成；不实现助手、不修旧任务业务缺口。不降低规则、扩大ignore或批量disable。
- evidence：`E:\moxton-ccb\05-verification\ADMIN-FE-022\attempt-1\`，开发dev-report.md；QA result.json与ui/console/network/failure_path。只父会话改正式状态；不提交/推送/再派代理。

## 目标与实现

清零100 errors，88 warnings分类记录且不新增。主要38 unused、36 use-before-define、7 namespace、4 process、3 no-void及条件/模板规则；修正真正引用与类型，不删除必要业务行为，不用批量lint --fix改全仓。现有测试申请/Survey/地址源码必须保留。

类型、接口、列render与模板事件保持兼容。vue/no-deprecated-filter检查可能是模板位运算/表达式识别，按实意修正。命名空间改普通模块导出同时保留既有命名导入/默认服务兼容。

依赖junction复用原仓，不通过其安装；pnpm工作区工具可能要求包node_modules，缺失时先报告具体入口由父会话准备，不能改全局配置。

## 验收

- `pnpm typecheck`、`pnpm exec eslint . --no-fix`、`pnpm build:test`退出0；warnings≤88且无新增类别/来源，编译前后核对生成源码差异。
- 针对修改的分类、商品、用户、咨询订单、在线订单、预售搜索及原测试申请页面做业务交互回归；使用Playwright网络mock或本地只读接口，不能写生产。
- 独立QA浏览器检查正常、空值、长文本、筛选、详情、权限与错误提示；console error_count=0、正常network无5xx。不能仅首页挂载PASS。

## 恢复

planned/attempt0。按快照保留来源不明原改动；新错误或阻塞回报主会话，不擅自结束或扩范围。

## 开发交付与QA

开发者已冻结源码，23个报错文件修复，lint0errors/82warnings、typecheck/build:test通过，7页mock交互已跑完。主会话接收waiting_qa后派新的admin-fe-qa独立审查及复跑，状态qa/attempt1；准确报告随后保存dev-report.md。

## 独立QA结果

2026-11-03 attempt1 PASS；0errors/82warnings，typecheck/build/34交互/11权限与窄屏检查通过，正式console0/network无5xx，validator valid=true。主会话已阅读限制与来源哈希。

## 集成复验与归档

2026-11-04 在集成后的 `E:\moxton-lotadmin` 复验：`pnpm typecheck`、`pnpm exec eslint . --no-fix`、`pnpm build:test` 均退出0；lint 为0 errors、82条既有 warnings。独立QA及结果校验器通过，现标记 completed。
