# Codex 桌面指挥迁移验收摘要

日期：2026-11-02。任务：CCB-MIGRATION-001，attempt 1。

状态：workflow QA PASS，主会话复核后归档；业务功能不在本轮验收范围。

## 改动和范围

- 文档中心新增项目规则、六个开发/QA 角色、工作流、会话恢复入口和结果校验器。
- 三个业务仓库仅更新 AGENTS.md 的协作协议及失效测试说明；业务源码未改动。
- 原有任务/API/产品资料基线为 `4e24b15`，迁移前四仓快照保存在本地 runtime，1106 个文件已校验。
- 旧入口和 hooks 配置保留副本；9 个运行态、身份或原始证据文件取消 Git 跟踪，磁盘原文件保留。客户表格和部署包保持本地。

## 已执行检查

- 新测试先失败；独立审查指出 Windows 目录别名缺口后再新增回归，观察失败并修复。`python -m unittest discover -s tests -v`：15 项通过。
- Python 编译检查、活动文档链接和差异空白检查通过。
- 本地 codex.exe 的 `debug prompt-input` 成功加载根规则及六个角色名；无 stderr。未修改终端全局 Codex 包装。
- 独立本地 app-server 只读 `config/read` 返回六个项目角色的描述和正确 config_file 路径；未创建模型线程，探针进程已退出。prompt-input 中的角色名本身不单独作为注册成功依据。
- 原生开发子代理实际新增恢复检查单和开发回报；7 个相对链接验证通过。开发回报直接到父会话，没有旧 MCP route。
- 792 个业务文件（不含三份授权 AGENTS.md）与迁移前快照 SHA-256 一致；用户级 Codex config.toml 和 AGENTS.md 哈希一致。

## 证据索引

原始证据位于本任务本地 `attempt-1/`：config.json、effective-config.json、prompt-input.json、scope.json、scope-final.json、native-dispatch.json、recovery.json、dev-result.json、tests.log、qa-findings.md、qa-review.md 和 result.json。

最终独立验收者 desktop-acceptance 已运行 15 项测试、配置/链接/恢复和两份受保护配置哈希核对。主会话再次运行结果校验器，退出 0，valid=true。归档后另核对最终任务路径和交接入口；旧 recovery.json 是归档前检查快照。

原始配置渲染和快照可能包含本机上下文，不纳入公开版本管理；本摘要不复制凭据或客户资料。

## 限制

本轮验证的是指挥流程，不是商城、支付或邮件的业务验收。未执行生产写入、发信、支付、推送或部署。

当前桌面工具未暴露自定义角色选择参数，本轮通过明确角色/职责文件和原生子代理完成派遣；新会话应加载项目配置，不能将 CLI 解析成功等同于当前桌面会话热加载。未强制重启桌面应用，恢复通过新 CLI 进程和独立 QA 上下文检查。

四个业务 active 任务保持 migration_hold，后续先核对代码和依赖，再按目标补验收或开发。
