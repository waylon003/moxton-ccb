# BACKEND-028 接管核查

核查日期：2026-11-03（Asia/Shanghai）。执行者：文档中心主会话。

> 本文保留初次接管核查的执行边界和环境状态。随后用户确认开发与线上共用数据库，主会话按要求建立了当前库的本地副本，19 张表、146 条记录恢复及校验通过；见 [本地副本交付记录](2026-11-03-local-database-copy.md)。隔离数据库前置条件现已满足，尚未执行业务 QA。

## 结论与范围

结构化地址的主要实现已经提交，不需要重新开发。源码与现有 mock 测试支持继续补验收，但隔离联调环境、迁移交付和完整构建仍有缺口，暂不进入 `waiting_qa`。

本次属于主会话接管核查，保持 `migration_hold / attempt 0`；未派遣开发或独立 QA，未签发业务 PASS，未重复已完成的指挥迁移。三个业务仓只读，正式文档和本地核查日志保存在文档中心。

## 核查基线

| 仓库 | HEAD | 核查前后状态 |
|------|------|--------------|
| 文档中心 | `1477256` | 核查开始时干净；本次只新增核查记录及更新交接入口 |
| 后端 | `234a7f5` | `master`，工作区干净，领先本地 `origin/master` 1 个提交 |
| 后台 | `f2544902` | 保留 16 个已跟踪文件修改和 8 个未跟踪文件 |
| 商城 | `cf1afe8` | 保留 19 个已跟踪文件修改，包含 Playwright 报告 |

本轮未 fetch；远程领先数基于本地引用。业务仓 HEAD、Git 状态与核查前相同；另核对 7 个后端关键源文件的 SHA-256，无变化。工具版本为 Node.js `v25.6.0`、npm `11.8.0`。

## 接口与源码核对

| 验收点 | 已有实现及证据位置（后端仓相对路径） | 本次能确认的范围 |
|--------|----------------------------------------|------------------|
| 根级地址字段与规范化 | `src/controllers/PreorderDiscount.ts:134`、`:455` | 六个结构化字段可省略或为 null；trim、空字符串转 null；长度限制为 100/100/100/20/500/255，非字符串返回校验错误；`address` 限长 500 并兼容 `ranchAddress` |
| 单产品与多产品保存 | `src/models/PreorderDiscountLead.ts:100`、`:125`、`:153` | `claim`、`claimMany` 共用 `claimProduct`；新 lead 保存同一组地址，重复领取沿用旧记录 |
| 列表、详情与搜索 | `src/models/PreorderDiscountLead.ts:304`、`:350`、`:387` | 查询没有排除地址标量字段；keyword 包含国家、地区、城市、邮编、地址、标准化地址；数据库实际查询效果待验 |
| 路由和权限 | `src/routes/index.ts:52`、`src/routes/preorder-discounts.ts:12` | `/preorder-discounts/claim` 使用可选认证；后台列表、详情和重发有认证及 admin/operator 门禁；本次未执行这些路由的 HTTP 权限验收 |
| 数据模型和地址迁移 | `prisma/schema.prisma:99`、`:149`；`20260710000000`、`20260713000000` 迁移 | 两个模型均有六个可空字段；预约 lead 的地址迁移已跟踪，只添加可空列，不解析旧地址；没有连接数据库确认实际表结构或历史记录 |
| 测试申请及 CSV | `src/controllers/PreorderDiscount.ts:506`、`src/models/ProductTestingApplication.ts:66`、`src/controllers/ProductTestingApplication.ts:217` | 根级结构化字段传入测试申请；CSV 表头和数据包含六个地址字段，现有 mock 导出用例通过 |

跨仓只读比对确认：商城 `components/preorder/PreorderDiscountForm.vue:421` 提交上述根级字段，后台 `src/service/api/preorder-discount.ts:89` 已声明对应可空类型。这只说明字段名可对接，不能替代浏览器或端到端验收。

文档中心 `02-api/preorder-discounts.md` 的字段、长度、空值和搜索说明与当前代码一致。另发现 `02-api/product-testing-applications.md` 仍为 6 月版本，缺少六个地址字段的提交、返回及 CSV 说明；后端 `API-DOCS/api/product-testing-applications.md` 已有这些内容。本次记录差异，未改接口文档。

## 本轮实际验证

命令工作目录均为 `E:\moxton-lotapi`，通过 PowerShell 7 执行。类型检查使用 `--noEmit`，没有生成或覆盖构建产物。

| 命令 | 退出码 | 结果及限制 |
|------|--------|------------|
| `npm test` 的默认 Vitest 流程（实际命令 `vitest run --config vitest.config.ts`） | 0 | 7 个文件、48 项测试通过；其中预约 24 项、测试申请 7 项。数据库、邮件和支付调用采用 mock；health/version 仅 smoke 路由 |
| `node node_modules/typescript/bin/tsc -p tsconfig.backend008.json --noEmit --pretty false --listFiles` | 0 | 局部类型检查通过；文件列表不包含 `src/app.ts` 或 `src/routes/index.ts` |
| `node node_modules/typescript/bin/tsc -p tsconfig.json --noEmit --pretty false` | 2 | 156 条错误、20 个文件，与迁移前报告的数量一致；不能声明全量构建通过 |
| `node node_modules/prisma/build/index.js validate --schema=prisma/schema.prisma` | 0 | schema 有效；未连接数据库或执行迁移 |

测试进程显式覆盖 `DATABASE_URL=mysql://audit:audit@127.0.0.1:1/backend028_audit`，并设置测试用邮件、支付和 JWT 占位配置；日志目录指向本次 runtime 目录。Prisma validate 同样覆盖数据库地址。未启动业务服务、连接现有业务数据库、发信、支付或操作生产状态。

测试调用曾附加 `--reporter=verbose --reporter=json --outputFile.json=E:\moxton-ccb\runtime\audits\backend-028-20261103\vitest-result.json`，但 npm 将这些参数识别为未知配置，实际运行了默认 Vitest 流程，未生成 JSON；以上测试数量和结果以 `mock-tests.log` 为准。重现测试时使用普通 `npm test` 即可。

## 尚未满足的条件

1. **隔离联调环境尚未确认。** 本机 `3033`、`3002`、`3666`、`3306`、`3307`、`6379` 未发现监听；后端没有 `.env.test`，`.env` 的数据库目标为非 loopback。`.env.production` 虽指向 loopback，也没有核实其用途或连接。Docker CLI 存在，但本轮未检查守护进程或容器，因此不据此认定可用。真实保存、多产品落库、历史 null、实际搜索、权限失败路径及 HTTP 正常链路均未完成验收。
2. **迁移交付不完整。** 本机有 6 份 SQL，Git 仅跟踪 3 份；`.gitignore:131` 忽略了 `20260629000000_add_product_testing_applications`、`20260629010000_add_preorder_lead_ranch_fields`、`20260703000000_add_preorder_feedback_survey`。预约地址自身的 `20260710000000` 已跟踪，但缺失的建表、羊群字段、Survey/永久有效期迁移会影响整个预售链路复现；已跟踪 SQL 也没有完整建库基线。本轮未执行 migrate、db push、seed 或历史回填。
3. **完整构建仍失败。** 全量错误主要涉及角色/路由与 Prisma 模型不符、旧 Payment/Cart/Inquiry 模型、路由 Context 类型、缺失导出/类型声明、定时任务参数和地址校验变量。没有诊断定位到本任务地址控制器/模型，但全项目仍失败。`package.json` 的默认 build 只编译局部配置，start 却要求 `dist/app.js`，不能用局部通过证明干净构建后可启动。
4. **专项测试覆盖仍有限。** 现有测试覆盖空白字段规范化、多产品字段保存、keyword 查询条件和详情地址；未覆盖真实数据库行为、完整 HTTP 门禁、历史记录返回 null，以及每个地址字段的全部类型/边界组合。测试通过不能当成专项业务 QA PASS。

## 下次入口

1. 正式执行前，由主会话定义隔离数据库、合成测试记录、邮件替身及允许文件范围；只核查环境时不复用现有业务数据库。补齐可追溯迁移资产与建库/升级方案，数据库操作须在明确授权的任务中执行。
2. 全量构建与可重复启动作为单独修复范围处理，不扩入“重新实现结构化地址”；发布前必须解决。
3. 条件就绪后为 `BACKEND-028` 开启新的正整数 attempt，优先补运行验收：手填、空字段、长度/类型失败、多产品落库、历史 null、列表/详情/搜索及角色门禁；关联测试申请和导出采用合成数据验证。
4. 再派独立后端 QA，证据按 `05-verification/BACKEND-028/attempt-<N>/` 保存，执行 `scripts/validate-desktop-result.py` 后由主会话决定状态；此时才接续前端专项联调。本轮没有正式 QA result，不运行校验器来制造 PASS。

## 本地证据

目录：`runtime/audits/backend-028-20261103/`（被忽略，不提交）。包含四仓 Git 前后状态、关键源码哈希、测试日志、完整/局部类型检查日志、schema 校验日志、命令退出码和脱敏核查摘要。正式任务见 [BACKEND-028](../../01-tasks/active/backend/BACKEND-028-preorder-ranch-address-country-region-locality-postcode.md)。
