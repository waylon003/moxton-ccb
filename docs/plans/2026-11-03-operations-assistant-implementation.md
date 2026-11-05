# 后台只读运营助手实施记录

用户已明确要求执行，主模型固定 `gpt-6.1-sol`。详细需求以本文件、四份正式任务和 `02-api/operations-assistant.md` 为准。

## 交付顺序

1. BACKEND-029 后端类型/完整构建修复；ADMIN-FE-022 后台 lint 修复，跨仓并行。
2. 两项分别通过新的独立 QA，冻结基线差异后执行 BACKEND-030 与 ADMIN-FE-023。
3. 使用本地数据库、合成身份和记录，真实网关仅处理合成数据，完成联合独立 QA。
4. 主会话复核、将验证过的工作区改动安全集成原工作区、保存任务和证据。不自动提交、推送或部署。

## 隔离与恢复

- 快照：`runtime/assistant-round-20261103/`，1040 个文件 SHA-256 校验通过，包括后台未跟踪源码、四仓当前源码和私有配置；客户内容和凭据不进入公开文档。
- 后端工作区：`E:\moxton-ccb\runtime\worktrees\backend-assistant`，分支 `codex/operations-assistant-backend`，HEAD `234a7f5f26745d301fca0eb45ebf5a19e3e98d90`。
- 后台工作区：`E:\moxton-ccb\runtime\worktrees\admin-assistant`，分支 `codex/operations-assistant-admin`，HEAD `f25449024a7cb63525fae8cbcabfdc7963b52179`，已恢复原工作区16份修改和7份未跟踪业务源码，未复制 dist.zip。
- 原工作区和商城不参与并发开发。依赖 junction 复用本机已安装依赖；若需要更改依赖，先解除该工作区 junction 再独立安装，不改原工作区依赖。
- 原有四项 migration_hold 保持原状。本轮没有数据库迁移或线上变更。

## 预检与裁定

| 任务/接口 | 检查与裁定 |
|-----------|------------|
| BACKEND-029 → BACKEND-030 | 共用 app、路由、配置及构建；先完成并独立验收基线，再交给新的开发者；不并发写同仓 |
| ADMIN-FE-022 → ADMIN-FE-023 | 共用路由、国际化和已有预售源码；同仓顺序执行，原有未提交代码是验证基线 |
| BACKEND-030 ↔ ADMIN-FE-023 | 共享契约固定在 operations-assistant.md；契约修改只能由主会话协调，不各自猜测 |
| 四项任务自身 | 基线修复不放宽检查；助手只读；浏览器历史不新增表；功能默认关闭、本地开启；独立 QA 验准确工作区 |

裁定：用户授权跨仓并行，覆盖技能中禁止多个实现代理并行的通用提示；每个仓库仍只有一个写入者。

裁定：原生 worktree 工具只能为当前文档仓创建，不能指定两个业务仓，故使用 git worktree fallback，目录放既有忽略的 runtime。未在 main/master 上实现。

裁定：用户明确禁止自动提交，故使用快照、精确工作区和文件哈希作为开发/QA基线，不执行技能中的自动提交或删除工作区动作。

裁定：本项目任务和 runtime 进度文件作为技能 ledger/brief 的项目内替代，避免引入额外隐藏目录。开发者不得改正式状态；新的独立 QA 兼任需求和代码质量审查，末轮再执行跨仓审查。

## 默认产品决策

- 独立 `/operations-assistant` 页面；admin/operator；中英文。
- 浏览器按账号隔离，保留7天/10会话/每会话最近10轮；删除与全部清空；登出清空内存但保留本人历史，同账号再登录可恢复。
- 首期完整JSON返回；请求上限4次模型/6次工具/90秒；客户端100秒。取消通过 AbortSignal 中止当前及后续调用，不自动重试收费请求。
- 统计使用匹配全集，不以第一页代替；列表默认20、最多50，结果明确 total/returned；日期UTC查询，用户相对日期按 Asia/Shanghai 解释。
- 真实网关联调只限定合成数据，查询工具测试使用mock或本地合成产品ID限制；不得将克隆库的真实客户内容发送模型。

## 状态

四任务创建于2026-11-03，初始 planned / attempt 0。开始派遣时由主会话更新。持续进度见 `runtime/assistant-round-20261103/progress.md` 和 CURRENT-ROUND。
