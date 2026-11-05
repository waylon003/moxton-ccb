# Tech-Spec: 预约预售线索保存 Google 解析后的牧场地址字段

**任务ID:** BACKEND-028
**创建时间:** 2026-07-09
**状态:** migration_hold
**执行模式:** codex-desktop
**当前 attempt:** 0
**角色:** 后端工程师
**项目:** moxton-lotapi
**优先级:** P1
**技术栈:** Node.js + Koa + TypeScript + Prisma + MySQL
**QA_LEVEL:** full

## 接管上下文（2026-11-02）

- 工作区：`E:\moxton-lotapi`；已提交基线 `c5018ea`，结构化地址主要实现已经存在。
- 当前只做接管记录，不重新开发或认定验收完成。先核对迁移后的实际 Git 状态，再补本任务的运行验收。
- 前置依赖：无；联调环境需要恢复。全量构建和迁移资产问题见现状报告，不能用局部 build 替代。
- 必读：业务仓 `AGENTS.md`、`03-guides/codex-desktop-workflow.md`、`02-api/preorder-discounts.md`。
- 允许范围：本轮无业务改动；正式续派前由主会话列明文件和基线。
- 子代理直接向父会话回报 task_id、attempt、变更/命令/证据和限制；证据按 `05-verification/BACKEND-028/attempt-<N>` 保存。
- 下次入口：对比实际保存/查询/导出字段和隔离环境，决定进入 waiting_qa 或创建明确修复范围。

## 接管核查结果（2026-11-03）

- 主会话已核对后端 `234a7f5` 的请求规范化、单/多产品保存、列表/详情、keyword、可空 schema 及地址迁移；主要实现已存在，不重复开发。
- 本轮实际检查：7 个测试文件、48 项 mock/smoke 测试通过；局部类型检查与 Prisma schema 校验退出 0；全量类型检查退出 2，仍有 156 条错误、20 个文件。准确命令与限制见 [核查报告](../../../docs/reports/2026-11-03-backend-028-takeover-review.md)。
- 隔离数据库尚未确认，约定服务和数据库端口无监听，开发配置数据库目标为非本机；三份关联迁移仍被 Git 忽略，缺完整建库基线。没有连接现有业务数据库或执行迁移。
- 跨仓字段名称可对接；文档中心测试申请 API 的六个地址字段说明落后于后端代码和仓内文档，待后续同步。
- 本次仅为接管核查，未派遣、未做独立业务 QA，状态保持 `migration_hold / attempt 0`，不进入 `waiting_qa` 或认定 PASS。三个业务仓未改动。
- 本地日志：`runtime/audits/backend-028-20261103/`。下次先明确隔离联调及迁移交付范围；全量构建另列修复范围，之后开启正式 attempt 补运行验收。

## 本地数据库准备（2026-11-03）

- 用户确认开发与线上共用同一数据库，并指定复制当前库内容到本地。主会话已做一致性快照导出，在独立 MySQL `8.4.5` 恢复到 `127.0.0.1:3307/moxton_local`。
- 19 张表、146 条记录逐表计数一致；字段、索引和外键一致；正常重启后数据仍完整。预约线索和测试申请各自六个结构化地址字段全部存在且可空。
- 初次复制时保留原 `.env`；随后已按用户指令将默认开发 `.env` 的 `DATABASE_URL` 切到 `127.0.0.1:3307/moxton_local`，其他开发变量与生产配置保持不变。真实配置加载后的 Prisma Client 和默认 Prisma CLI 只读连接验证均退出 0。
- 停用外部服务的隔离验收配置仍位于 `runtime/local-db/20261103/local-backend.env`，此类验收需显式加载。准确操作、启停与限制见 [本地副本交付记录](../../../docs/reports/2026-11-03-local-database-copy.md)。
- 本地数据库前置条件已满足；未向共享库写业务数据、执行迁移或发信，未做独立 QA。任务仍为 `migration_hold / attempt 0`；下次基于本地副本定义合成测试身份和邮件替身，再补运行验收。迁移交付和全量构建缺口另行处理。

---

## 概述

### 问题陈述

官网预约预售表单将只展示 `Country` 和 `Ranch address` 两个地址相关控件，并在 `Ranch address` 接入 Google Places Autocomplete。用户选择 Google 地址后，前端会解析隐藏结构化字段并随预约一起提交。

如果后端仍只保存 `address`，Google 解析出的 `stateRegion`、`locality`、`postcode`、`formattedAddress`、`placeId` 会丢失，后台也无法按国家、地区、城镇或邮编查看和分析预约线索。

### 解决方案

扩展 `PreorderDiscountLead` 数据模型和 `/preorder-discounts/claim` 提交流程：

1. 在预约优惠码线索中新增 `country`、`stateRegion`、`locality`、`postcode`、`formattedAddress`、`placeId` 可空字段。
2. `POST /preorder-discounts/claim` 接收上述根级字段。
3. 创建预约 lead 时保存可见地址和隐藏结构化字段。
4. 一次提交多个产品时，每条 lead 都保存同一组地址字段。
5. 后台列表和详情接口返回新增字段。
6. keyword 搜索补充覆盖国家、地区、城镇、邮编、详细地址、标准化地址。
7. 同步更新 `02-api/preorder-discounts.md`。

---

## 范围

**包含:**

- Prisma 模型新增 `country`、`stateRegion`、`locality`、`postcode`、`formattedAddress`、`placeId` 可空字段。
- 生成数据库迁移。
- 预约提交接口接收并规范化新增字段。
- `claim` / `claimMany` 保存新增字段。
- 后台列表接口返回新增字段。
- 后台详情接口返回新增字段。
- keyword 搜索覆盖新增地址字段。
- API 文档更新。
- 增加接口测试或脚本验证。

**不包含:**

- 官网 Google 地址搜索 UI，见 `SHOP-FE-022`。
- 后台管理页面展示，见 `ADMIN-FE-020`。
- 服务端调用 Google API 校验地址。
- 地址强校验。
- 经纬度保存。

---

## 开发上下文

相关文件：

- `prisma/schema.prisma`
- `src/controllers/PreorderDiscount.ts`
- `src/models/PreorderDiscountLead.ts`
- `src/routes/preorder-discounts.ts`
- `02-api/preorder-discounts.md`

相关任务：

- `SHOP-FE-022`：预约预售表单接入 Google 牧场地址搜索。
- `ADMIN-FE-020`：后台预约线索展示牧场地址结构化字段。
- `BACKEND-026`：预约优惠码线索补充牧场扩展字段。

---

## 数据模型

在 `PreorderDiscountLead` 增加：

```prisma
model PreorderDiscountLead {
  // existing fields...
  country          String?
  stateRegion      String?
  locality         String?
  postcode         String?
  address          String? @db.Text
  formattedAddress String? @db.Text
  placeId          String?
  // existing fields...
}
```

字段说明：

| 字段 | 类型 | 说明 |
|------|------|------|
| `country` | `String?` | 用户可见国家选择 |
| `stateRegion` | `String?` | Google 解析出的州 / 领地 / 地区 |
| `locality` | `String?` | Google 解析出的城市 / 区镇 / locality |
| `postcode` | `String?` | Google 解析出的邮编，允许为空 |
| `address` | `String? @db.Text` | 用户最终提交的牧场地址文本；可为手填 |
| `formattedAddress` | `String? @db.Text` | Google 返回的标准化完整地址 |
| `placeId` | `String?` | Google Place ID |

迁移要求：

- 新字段必须可空，兼容历史预约记录。
- 历史记录返回 `null`。
- 不解析历史 `address` 内容。

---

## API 调整

### 提交预约

```http
POST /preorder-discounts/claim
```

用户选择 Google 地址后的请求体示例：

```json
{
  "firstName": "Morgan",
  "lastName": "Carter",
  "phone": "+61 400 000 000",
  "email": "morgan@example.com",
  "ranchName": "Carter Ranch",
  "country": "Australia",
  "address": "433 Binginbar Road, Gollan NSW 2820, Australia",
  "formattedAddress": "433 Binginbar Road, Gollan NSW 2820, Australia",
  "stateRegion": "New South Wales",
  "locality": "Gollan",
  "postcode": "2820",
  "placeId": "google_place_id",
  "sheepCount": 1200,
  "sheepBreed": "Merino",
  "productIds": ["product_a_id"],
  "source": "home_preorder"
}
```

用户只手填地址时允许：

```json
{
  "country": "Australia",
  "address": "397 Bryant's Gap Road",
  "formattedAddress": null,
  "stateRegion": null,
  "locality": null,
  "postcode": null,
  "placeId": null
}
```

字段规则：

- `country` 非必填，trim，空字符串转 `null`，最大长度建议 100。
- `stateRegion` 非必填，trim，空字符串转 `null`，最大长度建议 100。
- `locality` 非必填，trim，空字符串转 `null`，最大长度建议 100。
- `postcode` 非必填，trim，空字符串转 `null`，最大长度建议 20。
- `address` 非必填，trim，空字符串转 `null`，最大长度建议 500。
- `formattedAddress` 非必填，trim，空字符串转 `null`，最大长度建议 500。
- `placeId` 非必填，trim，空字符串转 `null`，最大长度建议 255。
- 后端不因 `postcode`、`stateRegion`、`locality` 为空拒绝提交。

### 后台列表和详情

`GET /preorder-discounts/admin/leads` 和 `GET /preorder-discounts/admin/leads/:id` 返回新增字段：

```json
{
  "country": "Australia",
  "stateRegion": "New South Wales",
  "locality": "Gollan",
  "postcode": "2820",
  "address": "433 Binginbar Road, Gollan NSW 2820, Australia",
  "formattedAddress": "433 Binginbar Road, Gollan NSW 2820, Australia",
  "placeId": "google_place_id"
}
```

### keyword 搜索

keyword 建议覆盖：

- `country`
- `stateRegion`
- `locality`
- `postcode`
- `address`
- `formattedAddress`
- 现有姓名、邮箱、电话、牧场名称、羊只品种、产品名称、优惠码等字段

---

## 实施步骤

1. 检查 `PreorderDiscountLead` 当前字段和迁移历史。
2. 在 Prisma 模型新增 Google 地址结构化字段。
3. 生成迁移并确认字段可空。
4. 修改预约提交请求体类型。
5. 新增或复用字符串规范化 helper。
6. 修改 controller，将规范化后的地址字段传入 model。
7. 修改 `claim` / `claimMany` 保存逻辑。
8. 确认后台列表和详情接口返回新增字段。
9. 修改 keyword 搜索条件。
10. 更新 `02-api/preorder-discounts.md`。
11. 补充接口测试或验证脚本。

---

## 验收标准

- [ ] `PreorderDiscountLead` 表包含 `country`、`stateRegion`、`locality`、`postcode`、`formattedAddress`、`placeId` 可空字段。
- [ ] `POST /preorder-discounts/claim` 接收 Google 地址结构化字段。
- [ ] 用户只手填 `country + address` 时接口可正常提交。
- [ ] Google 解析字段为空时接口可正常提交。
- [ ] 新增字段空字符串保存为 `null`。
- [ ] 新增字段填写后会保存到每条预约 lead。
- [ ] 一次提交多个产品时，每条 lead 都保存同一组地址字段。
- [ ] 后台列表接口返回新增字段。
- [ ] 后台详情接口返回新增字段。
- [ ] 历史记录新增字段返回 `null`，接口不报错。
- [ ] keyword 可按国家、地区、城市/区镇、邮编、标准化地址搜索。
- [ ] API 文档已同步。

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| Google 解析字段缺失 | 后端字段全部可空，不做强校验 |
| 前端手填地址没有 `placeId` | 允许 `placeId = null` |
| 历史地址无法结构化 | 不自动解析历史 `address`，保持新字段为空 |
| 邮编格式跨国家差异大 | 后端只做长度和 trim，不做严格格式校验 |
| 多产品提交字段不一致 | 同一次提交所有 lead 复用同一组地址字段 |

---

**相关文档:**

- [预约预售表单接入 Google 牧场地址搜索](../shop-frontend/SHOP-FE-022-preorder-ranch-address-country-region-locality-postcode.md)
- [后台预约线索展示牧场地址结构化字段](../admin-frontend/ADMIN-FE-020-preorder-ranch-address-region-fields-display.md)
- [预售预约优惠码 API](../../../02-api/preorder-discounts.md)
