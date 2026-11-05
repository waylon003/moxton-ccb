# 运营助手客户业务信息查询实施计划

> **代理执行要求：**采用已约定的主会话指挥、跨仓子代理开发与独立 QA。执行时使用 `subagent-driven-development`，主会话直接实施时使用 `executing-plans`；按复选框跟踪，每个仓库只设一个开发写入者。

**目标：**允许有效 admin/operator 在现有助手业务域中查询客户信息，必要字段可交给当前模型处理，聊天显示真实记录，持久历史只保留摘要。

**架构：**保留现有 Koa 服务、六个工具和 Vue/Pinia 浮窗。后端撤销客户信息禁查规则，扩充结构化筛选和白名单业务投影；响应兼容增加 `records` 与结构化 `historySummary`。后台把完整结果留在内存，专门序列化不含客户详情的历史摘要。

**技术栈：**Koa、TypeScript、Prisma/MySQL、Vitest/Supertest；Vue 3、Pinia、Naive UI、Playwright。

**规格：**[已批准设计](../specs/2026-11-04-customer-aware-operations-assistant-design.md)。规格优先于实施细节。用户已批准本计划及跨仓子代理并行执行；执行记录见 runtime/agent-customer-round-20261104/progress.md。

## 全局约束

- 用户明确授权必要客户信息发送当前模型网关；测试仍仅使用合成身份/数据和 mock，不自动查询真实客户、调用真实模型或操作线上。
- 模型固定 `gpt-6.1-sol`；后端180000ms、前端190000ms；最多4次模型请求、6次工具执行，不自动重试。
- 六个现有工具不新增写能力，只覆盖商品、预售线索、测试申请及问卷；不增加订单/支付/系统用户域。
- 有效 admin/operator 在接口和每次工具调用中复核；普通用户、失效/停用账号保持拒绝。history仍只接受user/assistant文本，最多20条/10轮，消息长度等现有校验保持。
- 不改 schema、不迁移、不发信、不支付、不改生产配置、不新增依赖、不修改用户级Codex配置。
- 不自动提交、推送、部署；本轮冻结差异和SHA-256代替技能示例中的提交步骤。
- 关闭浮窗/切换业务页面不中止；显式取消、登出、换号、撤权仍中止。保留已完成 ADMIN-FE-025 的不透明背景、气泡、拖动/缩放/刷新几何。
- 会话按账号7天、最近10会话、每会话最近10轮；完整客户数据只留当前内存，localStorage和运行日志不写原始客户问题/回答/详情。
- Windows命令使用PowerShell 7，临时日志、截图、trace、备份全部放文档中心runtime或对应任务证据目录。

## 复核重点

1. 邮箱、电话、邮编和地址数字不能再触发隐私拒绝，也不能被当成编造统计；对应 Task 1 的输入/有依据回答回归。
2. 地址/备注/问卷里含提示注入、HTML或长文本时，只能当数据；对应 Task 1 工具边界、Task 2 转义及窄屏回归。
3. localStorage不能残留客户详情，包括原问题、模型回答、筛选条件、分组标签和旧缓存；对应 Task 2 序列化/恢复测试。
4. 在查询中换号、撤权或关闭再打开，旧详情不可进入新账号，迟到结果不得保存；对应 Task 2 门控请求测试。
5. 旧后端/旧响应缺少新字段，以及错误JSON/日志/query string含客户标记时，兼容或安全失败；对应 Task 1 日志、Task 2 旧响应兼容测试。

## 文件与职责

| 归属 | 文件 | 职责 |
|---|---|---|
| 后端 | 新建 `src/services/agent/customer-records.ts` | 客户字段白名单、记录DTO、受限文本/问卷投影、结构化历史摘要 |
| 后端 | 修改 `src/services/agent/security.ts` | 撤销PII禁查；保留请求结构/身份/长度边界 |
| 后端 | 修改 `src/services/agent/tools.ts` | 受控客户筛选、实际数据库投影、列表/统计条件一致 |
| 后端 | 修改 `src/services/agent/AgentService.ts` | 新DTO聚合、允许真实客户字段解释、数字依据、模型提示 |
| 后端 | 修改 `src/app.ts`、`src/utils/logger.ts` | 仅对agent路径去除日志URL查询串，避免客户信息进入访问日志 |
| 后端 | 修改 `tests/api/agent.spec.ts` | 将旧“客户信息必须422”改为新合同，保留其余安全/预算回归 |
| 后端 | 新建 `tests/api/agent-customer-records.spec.ts` | 纯投影、摘要、超长/注入文本测试 |
| 后台 | 修改 `src/typings/operations-assistant.ts` | records/historySummary及摘要恢复标记类型 |
| 后台 | 修改 `src/store/modules/operations-assistant/history.ts`、`index.ts` | 内存结果与持久摘要分离，旧缓存迁移与账号隔离 |
| 后台 | 修改 `src/layouts/modules/operations-assistant/chat-panel.vue`、`labels.ts` | 客户记录卡片、摘要提示、字段标签和纯文本展示 |
| 后台 | 修改 `src/locales/langs/zh-cn.ts`、`en-us.ts`、`src/typings/app.d.ts` | 移除禁查提示、补客户字段/历史摘要中英文及类型 |
| 后台 | 修改 `tests/e2e/operations-assistant.spec.ts` | 客户查询、历史无详情和现有浮窗完整回归 |
| 主会话 | `02-api/operations-assistant.md`、`03-guides/operations-assistant-local.md` | 同步公开合同与使用方法，保留历史证据 |
| 主会话 | 正式任务、STATUS、CURRENT-ROUND、验证summary | 唯一维护状态、集成、恢复入口 |

不修改后台浮窗容器 `layouts/modules/operations-assistant/index.vue`，也不改非助手业务页；如实际发现必要范围外依赖，先报父会话裁定，不自行扩改。

## 固定跨仓合同

### 1. 响应兼容扩展

旧字段的意义和包装不变。后端新版总是返回以下两个字段，前端对旧响应按空数组/空摘要兼容：

```ts
type AgentDomain = 'products' | 'preorder_leads' | 'testing_applications' | 'feedback';
type CustomerEntity = 'preorder_lead' | 'testing_application';
type CustomerValue = string | number | null;

interface CustomerRecord {
  entityType: CustomerEntity;
  id: string;
  fields: Array<{ key: CustomerFieldKey; value: CustomerValue }>;
  truncated: boolean;
}

type SummaryMetricKey =
  | 'products.total'
  | 'preorder_leads.total'
  | 'preorder_leads.submissions'
  | 'testing_applications.total'
  | 'feedback.submissions';

interface AgentHistorySummary {
  version: 1;
  domains: AgentDomain[];
  totals: Array<{ key: SummaryMetricKey; value: number }>;
}

interface HistorySummarySource {
  domain: AgentDomain;
  totals: AgentHistorySummary['totals'];
}

// 以下helper从customer-records.ts导出，由工具和AgentService使用。
// makeCustomerRecord(entityType: CustomerEntity, id: string,
//   fields: Partial<Record<CustomerFieldKey, CustomerValue>>): CustomerRecord | null
// buildHistorySummary(sources: HistorySummarySource[]): AgentHistorySummary

// 后端 AgentResponse 新增必需字段；后台 AssistantResult 允许旧响应缺失。
// records: CustomerRecord[]
// historySummary: AgentHistorySummary
```

`CustomerFieldKey`固定白名单：

```ts
type CustomerFieldKey =
  | 'firstName' | 'lastName' | 'email' | 'phone' | 'ranchName'
  | 'country' | 'stateRegion' | 'locality' | 'postcode'
  | 'address' | 'ranchAddress' | 'formattedAddress' | 'placeId'
  | 'sheepCount' | 'sheepBreed' | 'productId' | 'productName'
  | 'emailStatus' | 'status' | 'notificationStatus' | 'createdAt'
  | 'adminNotes' | 'interestedProduct'
  | 'woolPrioritizedFeatures' | 'woolOptimizationSuggestions'
  | 'woolPriceRange' | 'woolIntendedUseLocations' | 'woolIdealTestingTime'
  | 'woolDesktopVersionInterest' | 'sheepCountingPrioritizedFeatures'
  | 'sheepCountingOptimizationSuggestions' | 'sheepCountingPriceRange'
  | 'sheepCountingStationaryVersionInterest';
```

数组型问卷枚举投影为逗号分隔的字符串，保留缺失值null。只读取 `interestedProduct`、`woolAnalyzerSurvey`、`sheepCountingSurvey` 已有合法路径；JSON未知键、系统凭据、邮件错误原文、商品metadata不转发。

记录来自列表工具实际返回行，按实体+ID去重，整轮最多50条；超出时明确截断。每个业务字符串最多5000字符；超长字符串裁切并设置记录 `truncated=true`。每次模型工具消息列表数据最多64KiB UTF-8，超出时按返回顺序减少展示行并标记截断，`total`保持数据库完整匹配数；不得把截断样本冒充全集。

`historySummary`由工具名称、服务器计数/指标构造，不含任意自由文本、筛选值、分组标签或客户名。重复同类查询可保留多项totals，不将其错误相加；最多20项。引用仍由服务器生成，路径不受模型控制。

### 2. 客户筛选

| 参数 | 作用/校验 | 适用工具 |
|---|---|---|
| `recordId` | 实际记录ID，现有safeId，最长128 | 预售/测试列表及统计 |
| `keyword` | 最长200，trim后非空；匹配姓名、邮箱、电话、牧场、城市/邮编、地址等实际文本列 | 预售/测试列表及统计；问卷统计按预售条件 |
| `name` | 最长200；空白分词后每个词必须匹配firstName或lastName，最多10词 | 同上 |
| `email` | 最长254；trim+小写，匹配已有normalizedEmail | 同上 |
| `phone` | 最长80；按数据库原存格式contains，不推测国家区号 | 同上 |
| `ranchName`、`address` | 最长200/1000，contains；预售address与formattedAddress、测试ranchAddress与formattedAddress | 同上 |
| `locality`、`postcode`、`sheepBreed` | 最长100/20/200；按已有字段contains | 同上 |
| `notes` | 最长1000；匹配adminNotes | 仅测试列表及统计 |
| `feedbackKeyword` | 最长1000；匹配两款问卷的optimizationSuggestions/priceRange及羊毛idealTestingTime | 预售列表/统计、问卷统计 |
| `includeDetails` | boolean，默认false；增加完整地址、城市/邮编、placeId及测试备注投影 | 仅预售/测试列表 |
| `includeFeedback` | boolean，默认false；增加合法问卷路径投影 | 仅预售列表 |

原有产品、国家/州、时间、规模、状态、邮件状态、分页/排序保持。新筛选按AND组合，keyword内部OR；name按词AND。空字符串、未知键、非法类型和不适用参数返回400，不能把“有客户信息”本身当错误。列表默认20/最多50；统计继续全量计数。问卷统计仍按submissionId去重。

后端Filters扩展为 `Record<string,string|number|boolean>`，validator显式处理boolean；客户文本使用长度/类型/控制字符校验，不能继续使用会拒绝邮箱和详细地址的旧隐私正则。includeDetails/includeFeedback只影响列表选择字段，统计工具不接受这两个参数。模型工具消息只序列化一次列表投影，不把同一批客户详情以list与records重复发送。

`get_feedback_statistics`增加与预售相同的客户条件；原SQL查询继续只提取结构化问卷路径，新增条件均使用 `Prisma.sql` 参数，LIKE中的 `%`、`_`、反斜线按字面转义。Prisma列表contains/姓名分词与SQL统计语义必须用同组合条件测试对照，不能拼接用户SQL。

### 3. 浏览器摘要存储

- `cleanResult()`负责当前内存完整响应，支持records和historySummary；不得直接用于写入客户详情到localStorage。
- 新增 `serializeSessions(sessions: AssistantSession[], now?: number): AssistantSession[]`：只返回已清理的摘要副本，绝不改写内存会话。保存通用查询标题/摘要、结构化historySummary、无breakdown的受控计数指标、实体/ID构造的引用、时间；`records=[]`、`appliedFilters=[]`，没有原问题/回答/字段值。
- 新增 `restoreSessions(value: unknown, now?: number): AssistantSession[]`：先形状/期限清理，再摘要化。兼容旧数组会话，旧自由文本也转换为通用摘要并回写清理，不能把未经清理的旧缓存恢复到模型上下文。
- `AssistantTurn`增加可选 `summaryOnly: true`，供刷新后的摘要标识；当前内存中的新查询不设该标记。
- historySummary缺失/畸形时使用 `{version:1,domains:[],totals:[]}` 和通用摘要，不回退持久化原问题/回答。totals只接受白名单key和非负安全整数；引用label重新从实体/ID生成，持久化的session/reference/request标识需按实际UUID/CUID或已有合成ID格式校验，不能把旧缓存任意自由文本当标识原样保存。
- 当前内存多轮history仍仅user/assistant文本，允许必要客户信息；刷新后只发送已恢复的摘要文本，不发送缓存详情。
- 会话条数/过期清理、删除、清空、quota降级和账号隔离行为不变。存储失败只影响恢复，不影响当前查询。

---

## 执行前准备（主会话）

- [ ] **步骤1：核对准确基线和旧任务。**后端当前HEAD `234a7f5f26745d301fca0eb45ebf5a19e3e98d90`，后台 `f25449024a7cb63525fae8cbcabfdc7963b52179`；二者均包含大量已集成未提交文件，HEAD不能代替实际交付版本。分别运行Git根/HEAD/status，保存tracked、untracked、删除项和授权文件SHA-256；不要读取真实客户数据或输出密钥。
- [ ] **步骤2：使用模板创建正式任务。**拟用 `BACKEND-032-customer-aware-agent.md`、`ADMIN-FE-026-agent-customer-records.md`，初始化 `planned / attempt 0 / QA_LEVEL=full`。派遣时递增attempt并推进ready/in_progress；状态仅父会话维护。原四项migration_hold不变。
- [ ] **步骤3：准备隔离工作区。**优先检查已有适用worktree及其当前内容；需要新worktree时遵循 using-git-worktrees 和已有用户偏好。逐文件复制完整业务基线、验证哈希及删除状态，不再只复制上轮有限集成清单；包含问卷标签、测试申请service/types/modules等依赖。复用依赖前核对Junction，禁止复制 `.env`、密钥或生产配置。
- [ ] **步骤4：保存私有恢复资料和执行账本。**目录 `runtime/agent-customer-round-20261104/`；开发、QA证据分别 `05-verification/BACKEND-032/attempt-1/`、`ADMIN-FE-026/attempt-1/`。跨仓接口预检记录本计划DTO、字段key、summary版本和默认值。
- [ ] **步骤5：先检查业务基线。**后端mock单测/tsc、后台typecheck、现有25项助手E2E、文档中心16项工作流回归。已知失败写明准确命令/退出码/范围，不伪装整体绿色。派遣包含任务绝对路径、角色TOML、准确worktree、基线及dirty overlay、允许文件和证据。

---

## Task 1：客户查询工具与模型合同（拟 BACKEND-032）

**负责人：**backend-dev；冻结后新上下文backend-qa，QA_LEVEL=full。

**文件：**本计划“文件与职责”中的全部后端文件；不改Prisma schema或客户业务写API。

**消费：**现有AgentSettings、AgentTools、Prisma客户表、JSON问卷合法路径和员工JWT。

**产出：**兼容扩展的AgentResponse、上文客户筛选；`customer-records.ts`导出DTO、`makeCustomerRecord(entityType, id, fields)`及 `buildHistorySummary(sources)`。sources只含已知domain和受控totals，不含数据库自由文本；工具和AgentService共用，避免循环导入tools.ts。

- [ ] **步骤1：先替换旧禁查测试，并观察RED。**原 `tests/api/agent.spec.ts` 有一大组“客户信息必须422/网关零调用”断言。仅将这些旧合同改为允许message及user/assistant文本，保留畸形history/长度/角色/未知工具/权限/数字真实性和预算回归。

  ```ts
  it.each(['fixture.customer@example.test', '+61 400 000 001', '姓名：合成客户', '地址：1 Fixture Road', '备注：希望回访'])
    ('客户业务文本可以进入模型请求：%s', async message => {
      const { service, fetcher } = setup(); // 本文件已有mock数据库、网关和Koa setup
      await service.chat('admin-1', {
        message,
        history: [{ role: 'user', content: message }, { role: 'assistant', content: message }]
      });
      expect(fetcher).toHaveBeenCalledTimes(1);
      const payload = JSON.parse(fetcher.mock.calls[0][1].body);
      expect(payload.messages.filter((item: {content: string}) => item.content === message)).toHaveLength(3);
    });
  ```

  运行 `npm.cmd test -- tests/api/agent.spec.ts`。预期旧实现422导致这些允许查询用例失败；保存退出1和实际断言，不把环境错误当RED。

- [ ] **步骤2：撤销客户文本禁查。**从validateChatInput、工具普通文本验证、safeLabel及supportedAnalysis中清除以姓名/邮箱/电话/地址为拒绝依据的调用；废弃helper无调用后删除，避免两套相反规则。message/history结构校验、safeId、withAbort、工具键枚举保持。再次运行定向单测，允许文本用例GREEN；其余失败逐项分辨旧合同与回归。

- [ ] **步骤3：先补DTO/投影与摘要纯测试。**在新 `tests/api/agent-customer-records.spec.ts` 验证允许字段保留、未知键排除、null、5000字符截断、枚举数组展平、只有受控domain/totals进入摘要。

  ```ts
  import { expect, it } from 'vitest';
  import { makeCustomerRecord, buildHistorySummary } from '../../src/services/agent/customer-records';

  it('客户字段允许返回但未知字段不进入记录', () => {
    const fields = {email: 'fixture.customer@example.test', phone: '+61 400 000 001', adminNotes: '合成备注', apiKey: 'SYNTHETIC-EXCLUDED'};
    const record = makeCustomerRecord('testing_application', 'fixture-customer-1', fields);
    expect(record?.fields).toContainEqual({ key: 'email', value: 'fixture.customer@example.test' });
    expect(JSON.stringify(record)).not.toContain('apiKey');
    expect(JSON.stringify(record)).not.toContain('SYNTHETIC-EXCLUDED');
  });
  it('历史摘要没有客户原文或筛选值', () => {
    const summary = buildHistorySummary([{
      domain: 'testing_applications', totals: [{ key: 'testing_applications.total', value: 1 }]
    }]);
    expect(summary).toEqual({version: 1, domains: ['testing_applications'], totals: [{key: 'testing_applications.total', value: 1}]});
  });
  ```

  先运行 `npm.cmd test -- tests/api/agent-customer-records.spec.ts` 观察缺少模块/接口的RED，再按固定DTO实现helper。补运行时畸形字段测试，不能只测TypeScript正常调用。

- [ ] **步骤4：先补实际查询条件测试。**在agent.spec.ts使用已有mock db查看findMany/count参数：组合email+国家+状态；姓名分词；phone/keyword含单引号；recordId；仅测试工具接受notes；预售/问卷接受feedbackKeyword。非法参数仍400。

  ```ts
  it('邮件筛选同时用于列表和总数', async () => {
    const { tools, db } = setup();
    await tools.execute('search_preorder_leads', { email: ' FIXTURE.CUSTOMER@EXAMPLE.TEST ' }, 'admin-1');
    const listWhere = db.preorderDiscountLead.findMany.mock.calls[0][0].where;
    const countWhere = db.preorderDiscountLead.count.mock.calls[0][0].where;
    expect(listWhere).toEqual(countWhere);
    expect(JSON.stringify(listWhere)).toContain('fixture.customer@example.test');
  });
  ```

  原实现不接受新键应RED。随后实现固定筛选，列表/总数/统计复用同where构造，问卷SQL只用已知路径和Prisma.sql参数；对 `%_\\'` 文本检查SQL text和values分离及LIKE字面转义。姓名条件按各词AND、first/last OR构造，不依赖不存在的fullName列。

- [ ] **步骤5：加入按需投影并验证RED/GREEN。**列表默认新增姓名/邮箱/电话/牧场和既有概览字段；`includeDetails`时选择完整地址/备注，`includeFeedback`时读取合法问卷路径。统计不选择联系人/备注/完整问卷JSON；匹配条件可引用这些列但返回投影仍最小。测试用mock的select核对，与功能相关的旧“不选PII”断言改为新“只选本次必要字段”。

  为列表建立真实records，与model data.list来自同一受限投影；校验ID、字段key，按实体+ID去重。补长中文/备注导致64KiB预算截断、total不变、references只指向真实行、空结果records=[]的测试。

- [ ] **步骤6：更新模型指令与回答依据。**去掉“Never request contact details/names/addresses/notes”，明确可以根据本轮实际记录回答，私有配置/系统凭据不属于工具数据。客户文本和问卷提示注入一律数据。supportedAnalysis允许从本轮字段中找到的邮箱/电话号码/邮编，不把它们作为统计数；只移除精确来源值后再核对统计数字，未经验证的联系信息不作为结果来源。无依据/非法模型结果时回退真实摘要，客户records仍可展示。

  ```ts
  it('模型可以解释本轮实际联系人，records不接受模型伪造', async () => {
    const db = database([lead('fixture-lead-1', {email:'fixture.customer@example.test', firstName:'Fixture', lastName:'Customer'})]);
    const fetcher = vi.fn()
      .mockResolvedValueOnce(modelTool('search_preorder_leads', {email:'fixture.customer@example.test'}))
      .mockResolvedValueOnce(modelAnswer('客户邮箱是fixture.customer@example.test。'));
    const response = await setup(db, fetcher).service.chat('admin-1', {message:'查询fixture.customer@example.test'});
    expect(response.records[0].id).toBe('fixture-lead-1');
    expect(response.answer).toContain('fixture.customer@example.test');
    expect(JSON.stringify(response.historySummary)).not.toContain('fixture.customer');
  });
  ```

  对照增加“模型编造邮箱/数量、notes含忽略系统指令/发信要求”用例：实际records不变、没有写DB/邮件调用、未知工具400、权限持续复核。

- [ ] **步骤7：日志与失败边界验证。**只对 `/agent` 和 `/agent/` 路径，访问日志URL及app console使用ctx.path，不保留query string。保留现有agentErrorBoundary在bodyParser之前，避免错误日志记录body。测试POST含合成客户body/query、畸形JSON、模型错误原文时，通过spy确认日志和错误响应不出现该唯一标记；其他路由日志语义不变。

- [ ] **步骤8：完整开发验证与冻结。**

  ```powershell
  $env:CLEANUP_JOB_ENABLED = 'false'
  npm.cmd test
  npx.cmd tsc -p tsconfig.json --noEmit --pretty false
  npm.cmd run build
  git diff --check
  ```

  预期均退出0，dist/app.js存在。使用mock config/db/fetch，不读真实私有凭据。保存命令退出码、TDD RED/GREEN、受影响旧断言的理由、JSON合同、范围哈希；开发不得改任务状态。

- [ ] **步骤9：独立后端QA。**新backend-qa上下文验证准确worktree和冻结哈希，重点做权限、数据投影、真实工具循环/客户出站、错误日志和预算，而不是机械复跑已可靠验证命令。保存contract/network/failure_path/result.json，运行backend validator；PASS后父会话进入qa_passed，不由开发自行归档。

---

## Task 2：客户记录卡片与摘要历史（拟 ADMIN-FE-026）

**负责人：**admin-fe-dev；冻结后新上下文admin-fe-qa，QA_LEVEL=full。

**文件：**本计划“文件与职责”中的全部后台文件；不修改浮窗容器、路由、业务详情页或后端。

**消费：**上文records/historySummary合同、现有API service、safeReference、Pinia身份和25项浮窗E2E。

**产出：**客户卡片、允许查询的新提示、`serializeSessions()`与`restoreSessions()`，保留纯内存完整当前会话及旧响应兼容。Task 1/2可按固定合同跨仓并行，后台先mock。

- [ ] **步骤1：扩展类型和mock，先验证卡片RED。**在AssistantResult中增加可选records/historySummary，新增CustomerFieldKey等与后端完全一致的类型；AssistantTurn加 `summaryOnly?: true`。`cleanResult`为旧响应赋records=[]，新记录只能接受允许实体/ID/key与受限value，未知键丢弃、非法值不渲染。更新测试fixture：

  ```ts
  const customerResult = {
    ...result,
    answer: '找到1条测试申请。',
    records: [{entityType:'testing_application',id:'fixture-customer-1',truncated:false,fields:[
      {key:'firstName',value:'Fixture'}, {key:'lastName',value:'Customer'},
      {key:'email',value:'fixture.customer@example.test'},
      {key:'phone',value:'+61 400 000 001'},
      {key:'ranchAddress',value:'1 Fixture Road'}, {key:'adminNotes',value:'合成回访备注'}
    ]}],
    historySummary: {version:1,domains:['testing_applications'],totals:[{key:'testing_applications.total',value:1}]}
  };
  ```

  新用例从现有boot/ask发起姓名/邮箱问题，mock成功，期望 `assistant-customer-record` 出现邮箱/电话/地址。旧界面无卡片应RED，不能把原合成422场景继续当客户输入的预期行为。

- [ ] **步骤2：实现只读客户卡片。**在对应助手回复下方、统计旁加入紧凑卡片；记录标题为实体+ID，字段按白名单标签有序展示。email/phone是普通文本，备注和问卷长文本pre-wrap；不使用v-html，不接受模型URL。卡片详情操作复用后端references和safeReference。truncated显示中英文提示。保留当前浮窗CSS尺寸、非模态和待查询气泡，避免重写已验收容器。

  ```vue
  <section data-testid="assistant-customer-record" class="assistant-customer-record">
    <dl>
      <template v-for="field in record.fields" :key="field.key">
        <dt>{{ fieldLabel(field.key, t) }}</dt>
        <dd>{{ field.value ?? t('page.operationsAssistant.unknown') }}</dd>
      </template>
    </dl>
  </section>
  ```

- [ ] **步骤3：移除相反文案并补边界场景。**中英文description/empty改为权限内客户查询；新增字段标签、历史摘要提示和截断提示。422若后端仍返回，显示通用“请求无法处理”，不能提示客户信息禁止查询；旧后端/旧响应fallback仍可显示原统计。测试查询email成功、旧响应可用、非法records不渲染、HTML/URL/长备注只作文本；390px无新增卡片溢出，底部输入可达。

- [ ] **步骤4：先写持久化无PII回归，观察RED。**当前persist直接保存完整turn，新增行为测试应在此处发现真实缓存问题。

  ```ts
  test('客户详情仅在内存，刷新恢复摘要', async ({ page }) => {
    await boot(page);
    await page.route('**/agent/admin/chat', route => route.fulfill({json:success(customerResult)}));
    await ask(page, '查找fixture.customer@example.test的详细地址');
    await expect(page.getByTestId('assistant-customer-record')).toContainText('fixture.customer@example.test');
    const stored = await page.evaluate(() => Object.entries(localStorage)
      .filter(([key]) => key.includes('operations-assistant:')).map(([,value]) => value).join(''));
    for (const marker of ['fixture.customer@example.test','+61 400 000 001','1 Fixture Road','合成回访备注'])
      expect(stored).not.toContain(marker);
    await reloadAssistant(page);
    await expect(page.getByTestId('assistant-summary-only')).toBeVisible();
    await expect(page.getByTestId('assistant-customer-record')).toHaveCount(0);
    await expect(page.getByText('fixture.customer@example.test',{exact:true})).toHaveCount(0);
  });
  ```

- [ ] **步骤5：实现摘要序列化/恢复。**history.ts中保留cleanResult/pruneSessions处理内存；新增固定签名serializeSessions与restoreSessions。序列化基于受控historySummary重建通用文本，records/filters清空，计数无breakdown，引用label从实体/ID重建，不复制任意字符串。store.persist写serializeSessions(sessions)，不将摘要重新赋给sessions；setIdentity加载restoreSessions并回写清理。旧数组历史按同规则转成摘要，保持合法时间、7天/10会话/10轮与坏存储清理。

  ```ts
  // 关键调用关系，完整白名单转换在history.ts实现，不能用JSON深拷贝代替。
  // persist(): storage.set('sessions', serializeSessions(sessions.value))
  // setIdentity(): sessions.value = restoreSessions(assistantStorage(userId).get('sessions'))
  // 当前结果进入内存时：session.turns.push({message,result,createdAt:Date.now()})
  // 只给已恢复条目加summaryOnly:true，当前会话仍显示完整客户资料。
  ```

  增加缺失/畸形historySummary不缓存原文、旧缓存内含合成邮箱/姓名时清除、localStorage quota/不可用、非受控metric key/分组标签不能落盘、当前内存仍可多轮引用的断言。历史展示中由summaryOnly切换到中英文通用摘要，不承诺恢复客户详情。

- [ ] **步骤6：身份与取消门控回归。**发起含客户信息的延迟请求；关闭/跨页/重开响应只完成一次；显式取消无保存。通过现有auth store action切换合成账号或撤销角色后释放旧响应，断言新账号内存/输入/历史无旧客户标记。保持客户端190000ms截止与超过100秒成功回归，全部用虚拟时钟。

- [ ] **步骤7：完整开发验证与冻结。**

  ```powershell
  pnpm.cmd exec playwright test tests/e2e/operations-assistant.spec.ts --workers=2 --trace on --reporter=list --output=E:/moxton-ccb/05-verification/ADMIN-FE-026/attempt-1/dev-e2e
  pnpm.cmd typecheck
  pnpm.cmd exec eslint . --no-fix
  pnpm.cmd build:test
  git diff --check
  ```

  预期全部退出0；ESLint 0 errors、warnings不高于82；不运行全仓自动修复lint。统计显示/历史恢复旧断言按摘要新合同调整，不能仅删掉失败测试。构建前后检查生成types/路由，授权外生成差异只恢复本次可确认产物，不覆盖原脏改动。保存desktop/390px/en/等待与摘要截图、trace、命令退出码与文件哈希。

- [ ] **步骤8：独立后台QA。**新admin-fe-qa对准确冻结worktree跑真实浏览器，实际查看卡片、等待与刷新摘要截图；聚焦权限、客户信息出站/展示、存储无客户标记、伪造响应、长备注/窄屏和原浮窗生命周期。正常console错误0，预期网络错误独立记录；保存ui/console/network/failure_path/result.json并运行frontend validator。

---

## Task 3：联合合同验证、文档及归档（主会话）

**消费：**两个任务冻结哈希、独立QA报告、固定DTO及summary存储合同。

**产出：**本地主工作区可用的新功能、准确API/使用说明、完成任务和可恢复集成清单；不提交/推送/部署。

- [ ] **步骤1：冻结预检。**两任务开发完成后分别waiting_qa→qa；检查实际JSON字段、投影key、summary版本和旧响应默认值一致；其他任务的PASS不能代替本轮。任何返修新attempt，拒收旧attempt的回报。
- [ ] **步骤2：用合成数据做跨仓HTTP往返。**仅本机隔离端口，后端使用真实Koa路由和AgentTools但合成db/fetch替身，前端接此接口；不可用Playwright只返回一整份伪造成功结果代替联合合同。至少查询合成email、姓名、notes、feedback，核对实际工具条件、客户卡片、总数/截断与localStorage无详情。网关替身输出实际现有六工具之一，记录200/400/401/403及预期超时。
- [ ] **步骤3：文档同步。**重写 `02-api/operations-assistant.md` 中422禁查、仅脱敏字段、PII禁令与历史说明；补所有筛选及records/historySummary例子。更新本地使用说明和提示，旧QA证据不改写。任务已验证“客户输入可查询”，不能只删提示但后端仍拒绝。
- [ ] **步骤4：验证证据。**读取两份QA报告及实际截图/日志；分别执行下列validator，预期valid=true/退出0。只检查合同的validator不替代内容审阅。

  ```powershell
  python scripts/validate-desktop-result.py --result 05-verification/BACKEND-032/attempt-1/result.json --task-id BACKEND-032 --attempt 1 --kind backend --evidence-root E:\moxton-ccb\05-verification
  python scripts/validate-desktop-result.py --result 05-verification/ADMIN-FE-026/attempt-1/result.json --task-id ADMIN-FE-026 --attempt 1 --kind frontend --evidence-root E:\moxton-ccb\05-verification
  python -m unittest discover -s tests -p test_desktop_workflow.py -v
  ```

- [ ] **步骤5：最终只读审查。**新上下文核对仅授权文件、查询参数化、客户来源、PII不落日志/历史、权限与取消；Critical/Important先修复，保存审查报告。真实客户/真实模型未测限制如实记录，不推断生产可用。
- [ ] **步骤6：受控集成。**对比原主工作区是否仍匹配开始快照；备份被替换文件，按授权清单复制差异并复核SHA-256；不复制.env、密钥、产物或非任务文件。保留主工作区既有源码与私有配置。复核实际本地服务所加载模块/接口，避免只修改worktree却交付旧页面。
- [ ] **步骤7：状态和交接。**两任务qa_passed、父会话文档/集成复核完成后才completed，移到completed目录；写任务summary、STATUS、CURRENT-ROUND及 `runtime/agent-customer-round-20261104/progress.md`，记录准确命令、退出码、哈希/备份、剩余限制和下次入口。原四项migration_hold不动。

## 计划自检

- 规格每项均映射：客户输入/筛选/模型/记录在Task 1，卡片/文案/摘要/历史在Task 2，独立QA/联合合同/文档/集成在Task 3。
- fixed DTO、CustomerFieldKey、historySummary版本、默认值和两个serializer签名在跨仓合同一次定义，任务分别引用同一来源。
- 五项复核重点均有归属测试；既有隐私拒绝用例改为允许查询，不削弱权限/未知工具/失败路径测试。
- 执行顺序：主会话基线与接口预检→Task 1/2按合同跨仓并行→分别独立full QA→Task 3联合验证/审查/集成。沿用此前子代理执行方式，用户已批准，按下述执行账本持续推进。
