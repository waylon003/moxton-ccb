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
