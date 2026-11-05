# 共享数据库本地副本交付记录

日期：2026-11-03（Asia/Shanghai）。执行者：文档中心主会话。

## 结果

用户明确说明开发与线上共用一份数据库，并指定以当前数据库内容复制本地隔离环境。已从后端开发配置所指向的共享库做一致性快照导出，恢复到本机独立 MySQL，供后续专项验收使用。

| 项目 | 已交付内容 |
|------|------------|
| 本地服务 | MySQL Community Server `8.4.5`，与源库版本相同 |
| 连接地址 | `127.0.0.1:3307`，仅监听本机回环地址 |
| 本地数据库 | `moxton_local` |
| 应用账号 | `moxton_dev`，独立随机密码，仅授权本地副本 |
| 数据规模 | 19 张 InnoDB 表、146 条记录，记录数来自本次快照 |
| 默认开发配置 | `E:\moxton-lotapi\.env`，`DATABASE_URL` 已指向本地副本 |
| 隔离验收配置 | `runtime/local-db/20261103/local-backend.env`，另含停用外部服务的配置和本地凭据，不提交 |
| 数据文件 | `runtime/local-db/20261103/data/` |
| 原始快照 | `runtime/local-db/20261103/source.sql`，101925 字节，SHA-256 为 `f70780fe57a0ea6dc70f763b06d0c577591a084930a9434ae75184d067934f89` |
| 启停方式 | 独立 Windows 进程，无系统服务、不自动随开机启动 |

本地服务目前运行中；进程信息存于 `runtime/local-db/20261103/process.json`。复制完成后，按用户的后续指令，已将后端默认开发 `.env` 的 `DATABASE_URL` 切换到本地副本，并验证默认应用配置和 Prisma CLI 的实际连接；`.env.production` 保持不变。数据库恢复和开发连接切换不代表 `BACKEND-028` 已通过业务 QA。

## 实际执行和校验

1. 使用切换前的后端连接配置，只读获取版本、表类型、引擎、字段、索引和外键元数据；没有输出凭据或客户记录。源库为 `8.4.5`，19 张表均为 InnoDB，没有触发器、存储程序或事件。
2. Docker Engine 可用，但 `docker pull mysql:8.4.5` 因 Docker Hub 网络连接超时失败。没有修改 Docker 代理或镜像源，改用 MySQL 官方归档：`https://cdn.mysql.com/archives/mysql-8.4/mysql-8.4.5-winx64.zip`。
3. 归档解压到当前项目 `runtime/local-db/mysql-distribution/`；`mysqld.exe`、`mysql.exe`、`mysqldump.exe` 的 Oracle Authenticode 签名均为 Valid，分发包及可执行文件 SHA-256 存于 `installation-result.json`。
4. 通过同版本 `mysqldump` 执行 `--single-transaction --quick --skip-lock-tables --skip-add-locks --set-gtid-purged=OFF --no-tablespaces --column-statistics=0 --hex-blob --complete-insert --skip-extended-insert --routines --triggers --events` 导出指定业务库。数据库名和连接凭据从本地配置读取，不放入公开记录；临时源库客户端凭据文件在导出成功后删除。
5. 在新的本地数据目录初始化 MySQL，绑定 `127.0.0.1:3307`，关闭 MySQL X Protocol、event scheduler 和 binlog。创建独立本地数据库及应用账号后，恢复 SQL；没有向共享库执行建表、数据写入或迁移。
6. 使用本地应用账号核对全部 19 张表。字段定义（含默认值、可空性、字符集、生成表达式）、索引、外键与源库元数据一致；逐表实际行数与快照内独立 INSERT 数一致，共 146 条。该比较针对固定快照，不将仍在变化的线上库作为事后行数基准。
7. 正常停止并重新启动本地进程，再次认证连接并逐表计数，19 张表、146 条记录保持一致；监听地址仍为 `127.0.0.1:3307`。
8. 在本地副本确认 `preorder_discount_leads`、`product_testing_applications` 各自存在 `country`、`stateRegion`、`locality`、`postcode`、`formattedAddress`、`placeId`，全部可空。

| 操作 | 退出码 / 结果 |
|------|---------------|
| `docker pull mysql:8.4.5` | 1，网络超时，已使用官方 Windows 分发包完成替代 |
| 官方归档下载、解压及 Oracle 签名检查 | 0 / Valid |
| `node runtime/local-db/20261103/prepare-and-export.cjs` | 0，快照导出成功 |
| `mysqld.exe --defaults-file=<本地 my.ini> --initialize-insecure` | 0，仅初始化新的本地目录；首次启动已设置随机 root 密码 |
| `node runtime/local-db/20261103/restore-and-verify.cjs` | 0，恢复及结构、行数校验通过 |
| 本地 stop/start、认证 ping、重启后逐表计数 | 0，持久数据保持一致 |

上述 Node 命令的工作目录为 `E:\moxton-ccb`，通过 PowerShell 7 执行。准备/恢复脚本仅用于本次操作，包含防覆盖检查，**不可直接重跑覆盖当前副本**。后续如需刷新，另建新的快照及目标目录，并重新核对授权和当前本地改动。

## 本地使用入口

启动（仅在本地实例已经停止时执行）：

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -File 'E:\moxton-ccb\runtime\local-db\20261103\start-local-db.ps1'
```

停止：

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -File 'E:\moxton-ccb\runtime\local-db\20261103\stop-local-db.ps1'
```

后端默认开发启动 `npm run dev` 和 Prisma CLI 现在均从 `.env` 读取本地数据库连接；生产模式读取 `.env.production` 的原有配置。外部进程若已设置 `DATABASE_URL`，该值会优先于 dotenv 文件；本次验证没有预先注入该变量。

默认开发 `.env` 本次仅修改数据库连接，其他变量保持不变。另存的 `local-backend.env` 用于隔离验收，不会自动加载：它使用独立 JWT secret，将源配置里的其他密钥清空；Resend key 为空，Stripe 使用无效测试占位值，Google key 为空，Redis 禁用。需要停用真实邮件/支付调用的验收进程仍须显式加载这份隔离配置，并明确邮件替身范围；数据库切换不等于这些外部服务已切换。

## 默认开发连接切换验证

- 按用户“将开发环境指向本地数据库”的指令，仅修改 `E:\moxton-lotapi\.env` 的 `DATABASE_URL`，使用已创建的 `moxton_dev` 本地账号；原开发文件备份为 `runtime/local-db/20261103/development-env.before-local-switch`，保持本地。
- 修改前后逐键比对，其他开发变量一致；`.env.production` 修改前后 SHA-256 一致。三个业务仓已跟踪源码均无本次变更，`.env` 按原有规则被 Git 忽略。
- 工作目录 `E:\moxton-lotapi`，通过 `node` 加载 `ts-node/register/transpile-only` 和真实 `src/config/index.ts`，不预先注入 `DATABASE_URL`；Prisma Client 实际查询返回数据库 `moxton_local`、服务端口 `3307`、19 张表，退出 0。
- 同目录执行 `'SELECT 1;' | node node_modules/prisma/build/index.js db execute --schema=prisma/schema.prisma --stdin`，退出 0。该命令只读查询，证明 Prisma CLI 默认配置可连接；未执行 migrate 或 db push。
- 本轮没有启动或重启完整后端服务；默认连接、数据库连通性与业务 HTTP 验收分别记录。

对应证据为 `development-switch-result.json`、`default-development-connection.json`、`default-prisma-cli-connection.json` 及 `.log`，均位于本地证据目录。

## 两个前端开发环境连接复核

用户随后要求验证商城和后台开发环境是否使用本地数据库。主会话分别执行框架的真实配置加载，并通过后端 Prisma Client 再次连接本地副本；三个检查退出码均为 0。

| 项目 | 默认开发命令及页面端口 | 实际加载的 API 目标 |
|------|------------------------|----------------------|
| 商城 `E:\nuxt-moxton` | `pnpm dev`，端口 `3666` | `nuxt.config.ts` 与 `.env` 加载后，`runtimeConfig.public.apiBase` 为 `http://localhost:3033` |
| 后台 `E:\moxton-lotadmin` | `pnpm dev` 即 `vite --mode test`，端口 `9527` | `.env` + `.env.test`，`VITE_HTTP_PROXY=Y`；客户端 `/proxy-default` 经项目代理转到 `http://localhost:3033`，路径重写检查通过 |
| 后端 `E:\moxton-lotapi` | 默认开发 `.env` | Prisma Client 实际只读查询返回 `moxton_local`、端口 `3307`，连接地址为 `127.0.0.1` |

商城使用 `nuxt/kit` 的 `loadNuxtConfig({cwd:process.cwd(),dotenv:true,overrides:{dev:true}})` 加载配置；后台使用 Vite `loadEnv('test',process.cwd())` 并实际执行项目 `getServiceBaseURL` / `createViteProxy`。没有检测到相关 API 环境变量的外部进程覆盖。两前端均通过后端访问数据库，没有直接数据库配置。

六份前端环境配置 SHA-256 前后一致，两个前端的 Git 状态与核查前一致，本次无需修改前端配置。检查时仅本地 MySQL `3307` 在监听，后端 `3033`、商城 `3666`、后台 `9527` 均未启动；本次结论覆盖实际配置解析与后端数据库连接，尚未验证页面运行后的浏览器请求。

本地证据：`runtime/audits/frontend-local-db-20261103/`，含 `inspection-summary.json`、前后配置哈希、端口与工作区核对记录。

## 交付边界与下次入口

本次保存的是用户指定的真实数据副本，包含原有客户内容；快照、数据目录、凭据、原始日志和临时脚本全部位于被忽略的 `runtime`，本地工作目录 ACL 限制为当前用户和 SYSTEM。正式记录仅包含聚合数量与校验结果。三个业务仓 Git 状态与复制前相同，未派遣任务、提交、推送或部署。

本地数据库这一前置条件已满足，可以用该副本接续 `BACKEND-028` 的运行验收；新增测试记录与身份使用合成数据，原始 SQL 快照作为恢复基线。三份迁移未纳入 Git、缺完整建库基线和全量构建 156 条错误仍属独立交付缺口，本次复制未修复这些问题。四项业务任务保持 `migration_hold / attempt 0`。

本地证据目录：`runtime/local-db/20261103/`。主要记录包括 `source-metadata.json`、`source-schema.json`、`snapshot-counts.json`、`export-result.json`、`restore-result.json`、`verification-details.json`、`restart-result.json`、`post-restart-result.json`、`installation-result.json` 和 `business-git-states.json`。
