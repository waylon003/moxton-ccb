# 后台只读运营助手 API

版本：v1，兼容扩展客户查询；模型固定 `gpt-6.1-sol`。仅有效 admin/operator，复用员工JWT，每次工具调用前复核数据库账号状态与角色。沿用 `{code,message,data,timestamp,success}` 包装，无数据库表结构变更。

## 能力

`GET /agent/admin/capabilities` 需认证，成功data：

```json
{"enabled":true,"model":"gpt-6.1-sol","readOnly":true,"domains":["products","preorder_leads","testing_applications","feedback"],"limits":{"historyTurns":10,"modelRequests":4,"toolCalls":6,"timeoutMs":180000}}
```

总预算包含授权、模型和工具执行；浏览器等待190000毫秒。不自动降级模型或重试。功能关闭/未配置时capabilities返回enabled=false、chat返回503；未登录401，普通、停用或失效账号403。

## 对话

`POST /agent/admin/chat`，JSON：

```json
{"message":"查询fixture.customer@example.test的测试申请和详细地址","history":[{"role":"user","content":"先看测试申请"},{"role":"assistant","content":"请提供筛选条件"}],"locale":"zh-CN"}
```

message去空白后1–2000字符；history最多20条/10轮，仅user/assistant文本，每条最多4000字符，总字符最多24000。未知键、system/tool角色或客户端工具结果400；locale仅zh-CN/en-US。姓名、邮箱、电话、地址和备注是合法业务内容，不再触发隐私422。用户已允许必要客户信息交给当前模型网关处理，权限和只读边界继续生效。

成功data示例（全部为合成数据）：

```json
{
  "answer":"找到1条测试申请。",
  "references":[{"entityType":"testing_application","id":"fixture-customer-1","label":"测试申请 fixture-customer-1","path":"/product-testing-application?id=fixture-customer-1"}],
  "metrics":[{"key":"testing_applications.total","label":"测试申请数","value":1,"unit":"applications"}],
  "appliedFilters":[{"tool":"search_testing_applications","filters":{"email":"fixture.customer@example.test","includeDetails":true,"pageNum":1,"pageSize":20,"sortBy":"createdAt","sortOrder":"desc"}}],
  "queriedAt":"2026-11-04T00:00:00.000Z",
  "requestId":"12345678-1234-4234-8234-123456789012",
  "records":[{"entityType":"testing_application","id":"fixture-customer-1","fields":[{"key":"firstName","value":"Fixture"},{"key":"email","value":"fixture.customer@example.test"},{"key":"ranchAddress","value":"1 Fixture Road"}],"truncated":false}],
  "historySummary":{"version":1,"domains":["testing_applications"],"totals":[{"key":"testing_applications.total","value":1}]}
}
```

references/metrics/appliedFilters/records为空时返回[]；前端兼容旧响应缺少records/historySummary。引用只由实际工具结果ID生成，实体product/preorder_lead/testing_application对应 `/product?id=...`、`/preorder-discount?id=...`、`/product-testing-application?id=...`，ID编码，前端再验证。模型任意链接不能成为记录入口，答案和客户字段按纯文本显示。

模型可解释本轮真实客户字段；业务数量、分组、趋势由后端计算，分页样本不能当全集。无依据或无效回答回退为服务器摘要，不编造联系人/统计。备注与问卷中的指令仅作数据，不能改变工具权限。

失败：400参数无效，401/403认证权限，429同用户并发，502网关/响应无效，503关闭/缺配置，504超时/预算耗尽。不回传供应商原文、客户正文、历史或密钥。显式取消、登出、换号、撤权中止后续调用；隐藏窗口和业务导航继续等待。

## 六个只读工具

| 函数 | 用途 |
|------|------|
| search_products | 未删除预售商品；keyword按名称、productId；返回id/name/purchaseMode/status，无metadata全文 |
| search_preorder_leads | 客户线索列表及完整匹配total，按需地址/问卷投影 |
| get_preorder_statistics | 完整lead数、去重提交次数和分组 |
| search_testing_applications | 客户测试申请列表及完整匹配total，按需地址/备注投影 |
| get_testing_application_statistics | 完整申请数和分组 |
| get_feedback_statistics | 按提交去重的结构化问卷枚举统计，可按客户条件过滤 |

原有条件：country、stateRegion、createdFrom/createdTo（ISO UTC闭区间）、sheepCountMin/Max（0–999999）；productId仅预售/问卷；线索emailStatus=PENDING/SENT/FAILED；测试status=APPLIED/SELECTED/REJECTED、notificationStatus=NOT_SENT/SENT/FAILED。测试没有productId关联。

客户条件按AND组合；keyword内部OR，姓名按词AND：

| 参数 | 语义/上限 | 适用范围 |
|------|-----------|----------|
| recordId | 实际safeId，128字符 | 预售/测试列表与统计、问卷统计 |
| keyword | trim后非空，200字符；姓名/邮箱/电话/牧场/城市/邮编/实际地址列contains | 同上 |
| name | 200字符，最多10个空白分词，每词匹配firstName或lastName | 同上 |
| email | 254字符，trim+小写后匹配normalizedEmail | 同上 |
| phone | 80字符，按原存格式contains，不推测区号 | 同上 |
| ranchName | 200字符，contains | 同上 |
| address | 1000字符，预售address/formattedAddress、测试ranchAddress/formattedAddress | 同上 |
| locality/postcode/sheepBreed | 100/20/200字符，contains | 同上 |
| notes | 1000字符，匹配adminNotes | 仅测试列表/统计 |
| feedbackKeyword | 1000字符，合法问卷optimizationSuggestions/priceRange及羊毛idealTestingTime | 预售列表/统计、问卷统计 |
| includeDetails | boolean默认false，增加完整地址/城市/邮编/placeId及测试备注 | 仅预售/测试列表 |
| includeFeedback | boolean默认false，增加合法问卷投影 | 仅预售列表 |

空字符串、未知键、非法类型、不适用参数400。pageNum默认1，pageSize默认20最大50；sortBy为createdAt/sheepCount，sortOrder默认desc，ID稳定排序。统计使用同筛选计算全部匹配，不受分页限制。

groupBy：预售country/stateRegion/emailStatus/product/day（默认emailStatus）；测试country/stateRegion/status/notificationStatus/day（默认status）；问卷interestedProduct/woolPrioritizedFeatures/sheepCountingPrioritizedFeatures（默认interestedProduct）。无日期即全部时间；相对日期按上海时区解释并转UTC，空地区计unknown。lead条数和提交次数区分：非空submissionId去重，空submissionId按独立lead计一次，问卷跨产品按提交去重。

Prisma安全参数构造所有条件；问卷SQL的LIKE特殊字符按字面转义，禁止任意SQL/URL/文件工具。

## 客户记录与摘要

records每项为 `{entityType,id,fields:[{key,value}],truncated}`，实体仅preorder_lead/testing_application，value仅string/number/null。字段白名单：

```text
firstName lastName email phone ranchName country stateRegion locality postcode
address ranchAddress formattedAddress placeId sheepCount sheepBreed productId productName
emailStatus status notificationStatus createdAt adminNotes interestedProduct
woolPrioritizedFeatures woolOptimizationSuggestions woolPriceRange woolIntendedUseLocations
woolIdealTestingTime woolDesktopVersionInterest sheepCountingPrioritizedFeatures
sheepCountingOptimizationSuggestions sheepCountingPriceRange sheepCountingStationaryVersionInterest
```

问卷只读取已有interestedProduct/woolAnalyzerSurvey/sheepCountingSurvey合法路径，枚举数组转逗号分隔字符串，缺失null。不转发未知JSON键、凭据、邮件错误原文或商品metadata。记录按实体+ID去重，整轮最多50；字符串最多5000字符，超长标记truncated。每次模型工具消息列表最多64KiB UTF-8，超出减少展示行并标记，total保留完整计数，同批客户详情不重复序列化。

historySummary为 `{version:1,domains,totals:[{key,value}]}`，由服务端工具和计数生成，无客户原文、筛选值或分组标签。domain仅products/preorder_leads/testing_applications/feedback；key仅products.total、preorder_leads.total、preorder_leads.submissions、testing_applications.total、feedback.submissions。值为非负安全整数，最多20项，同类重复查询可并列但不能错误相加。

## 配置、日志与历史

后端私有变量AGENT_ENABLED=false默认，AGENT_BASE_URL、AGENT_API_KEY及AGENT_MODEL=gpt-6.1-sol；网关目标由部署配置确定，模型无权改变，密钥不能进入前端或版本库，生产配置不因本轮改变。

日志仅存账号/请求ID、工具名、耗时、条数、错误类型等元数据；agent访问日志使用path，不带query string，不记录客户字段、对话或上游错误正文。

浏览器按环境和账号保存7天、最近10个会话、每会话最近10轮的完整清洗后会话，包括问题、回答、客户卡片、统计和筛选；刷新后恢复已保存内容。当前版本用版本化格式，旧版摘要记录迁移后仍显示为摘要，已丢弃的详情无法恢复。回答、客户字段、统计、筛选、引用及时间在读写时均经过字段/长度/数量校验。退出、换号或撤权会清空内存并取消请求；持久化失败时当前页面继续可用并提示无法保证刷新后恢复。
