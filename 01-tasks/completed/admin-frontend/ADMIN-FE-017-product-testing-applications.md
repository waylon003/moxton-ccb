# Tech-Spec: 后台产品测试计划申请列表与资格邮件

**任务ID:** ADMIN-FE-017
**创建时间:** 2026-06-29
**状态:** 待开发
**角色:** CRUD前端工程师
**项目:** moxton-lotadmin
**优先级:** P1
**技术栈:** Vue 3 + TypeScript + SoybeanAdmin + Naive UI
**QA_LEVEL:** smoke

---

## 概述

### 问题陈述

官网预约页新增 AI Sheep Counting Camera 产品测试计划报名后，运营需要在后台查看报名用户、导出名单给管理层筛选，并对入选用户发送资格邮件。第一版预计只筛选 5 到 10 个名额，因此不需要批量导入筛选结果，后台手动搜索和单条操作即可。

预约优惠码后台页面只负责优惠码领取和发码状态，不适合处理测试计划筛选。需要新增独立菜单页管理产品测试申请。

### 解决方案

新增“产品测试申请”后台页面，提供：

- 列表分页。
- keyword 搜索。
- 状态和邮件状态筛选。
- 详情查看。
- 导出 CSV/Excel。
- 标记入选 / 未入选。
- 发送资格邮件 / 重发资格邮件。
- 编辑管理备注。

### 范围

**包含:**

- 新增产品测试申请 API service 和类型。
- 新增列表页。
- 新增详情弹窗或抽屉。
- 新增搜索和筛选。
- 新增导出操作。
- 新增状态标记操作。
- 新增发送资格邮件操作。
- 新增管理备注编辑。
- 在预约优惠码详情中显示“已申请测试计划”入口。
- 补齐中英文菜单和页面文案。

**不包含:**

- 后端接口开发，详见 `BACKEND-025`。
- 官网报名入口，详见 `SHOP-FE-019`。
- 批量导入管理层筛选结果。
- 设备发放和数据上传管理。

---

## 开发上下文

参考现有页面：

- `src/views/preorder-discount/index.vue`
- `src/views/preorder-discount/modules/preorder-discount-detail.vue`
- `src/service/api/preorder-discount.ts`
- `src/views/consultation-order/index.vue`

建议新增：

- `src/service/api/product-testing-application.ts`
- `src/views/product-testing-application/index.vue`
- `src/views/product-testing-application/modules/product-testing-application-detail.vue`
- `src/views/product-testing-application/modules/product-testing-application-notes.vue`

可能需要修改：

- `src/router/elegant/routes.ts` 或项目既有路由生成配置。
- `src/locales/langs/zh-cn.ts`
- `src/locales/langs/en-us.ts`
- `src/views/preorder-discount/modules/preorder-discount-detail.vue`

### 依赖项

- 前置任务：`BACKEND-025`
- API 文档：`../../../02-api/product-testing-applications.md`

---

## 页面结构

### 菜单

建议菜单位置：

- 一级：营销管理 或 预约管理。
- 二级：产品测试申请。

如果当前后台已有“预约优惠码”菜单，建议与其相邻。

### 列表字段

表格字段：

- 申请 ID，可折叠或详情内展示。
- 姓名。
- 邮箱。
- 电话。
- 牧场名称。
- 牧场地址，列表可截断。
- 羊群数量。
- 羊只品种。
- 申请状态。
- 邮件状态。
- 报名时间。
- 操作。

操作列：

- 查看详情。
- 标记入选。
- 标记未入选。
- 发送资格邮件。
- 编辑备注。

### 搜索筛选

第一版筛选：

- keyword：搜索姓名、邮箱、电话、牧场名称。
- 申请状态：`APPLIED`、`SELECTED`、`REJECTED`。
- 邮件状态：`NOT_SENT`、`SENT`、`FAILED`。
- 报名时间范围。

可选筛选：

- `programKey`，第一版只有一个测试计划时可以隐藏或默认固定。

### 详情

详情展示：

- 基础信息：姓名、邮箱、电话。
- 测试计划：`programKey`、申请状态、邮件状态。
- 牧场信息：牧场名称、牧场地址、羊群数量、羊只品种。
- 来源信息：`source`、`submissionId`。
- 时间信息：报名时间、入选时间、通知时间、更新时间。
- 邮件失败原因：`notificationError`。
- 管理备注：`adminNotes`。

详情内操作：

- 标记入选。
- 标记未入选。
- 发送资格邮件。
- 重发资格邮件。
- 编辑备注。

---

## 交互规则

### 标记入选

点击“标记入选”：

- 二次确认。
- 调用状态更新接口。
- 成功后刷新列表和详情。
- 不自动发送邮件，除非用户点击“发送资格邮件”。

### 标记未入选

点击“标记未入选”：

- 二次确认。
- 调用状态更新接口。
- 成功后刷新列表和详情。
- 如果该申请已经发送过资格邮件，应展示风险提示，但第一版不禁止操作。

### 发送资格邮件

点击“发送资格邮件”：

- 如果当前状态不是 `SELECTED`，提示“发送后将自动标记为入选”。
- 二次确认。
- 调用发送接口。
- 成功后展示发送结果。
- 邮件发送失败时，接口仍可能返回成功 envelope，但 `notificationStatus = FAILED`，前端必须按字段展示失败。

### 重发资格邮件

当 `notificationStatus = FAILED` 或 `SENT` 时：

- 展示“重发资格邮件”。
- 对 `SENT` 状态重发必须二次确认。
- 重发后刷新邮件状态、通知时间、失败原因和重试次数。

### 编辑备注

备注可以在详情抽屉内编辑：

- textarea。
- 保存按钮调用备注接口。
- 空字符串表示清空备注。

### 导出

列表页提供导出按钮：

- 使用当前筛选条件导出。
- 导出前二次确认。
- 导出文件名建议包含日期，例如 `product-testing-applications-2026-06-29.csv`。
- 导出后不改变列表状态。

导出说明：

- 表格中必须包含 `applicationId`。
- 管理层筛选后，可以用 `applicationId`、邮箱或姓名回到后台搜索。

---

## API 接入

接口来源：`../../../02-api/product-testing-applications.md`

```http
GET /product-testing-applications/admin
GET /product-testing-applications/admin/:id
PATCH /product-testing-applications/admin/:id/status
PATCH /product-testing-applications/admin/:id/notes
POST /product-testing-applications/admin/:id/send-selection-email
GET /product-testing-applications/admin/export
```

### 类型建议

```ts
type ProductTestingApplicationStatus = 'APPLIED' | 'SELECTED' | 'REJECTED'

type ProductTestingNotificationStatus = 'NOT_SENT' | 'SENT' | 'FAILED'

interface ProductTestingApplication {
  id: string
  programKey: string
  submissionId?: string | null
  firstName: string
  lastName: string
  phone: string
  email: string
  ranchName?: string | null
  ranchAddress?: string | null
  sheepCount?: number | null
  sheepBreed?: string | null
  status: ProductTestingApplicationStatus
  notificationStatus: ProductTestingNotificationStatus
  notificationError?: string | null
  notificationRetryCount: number
  selectedAt?: string | null
  notifiedAt?: string | null
  adminNotes?: string | null
  source?: string | null
  createdAt: string
  updatedAt: string
}
```

---

## 状态展示

申请状态：

| 状态 | 展示文案 | 建议颜色 |
|------|----------|----------|
| `APPLIED` | 已报名 | default / info |
| `SELECTED` | 已入选 | success |
| `REJECTED` | 未入选 | warning / error |

邮件状态：

| 状态 | 展示文案 | 建议颜色 |
|------|----------|----------|
| `NOT_SENT` | 未发送 | default |
| `SENT` | 已发送 | success |
| `FAILED` | 发送失败 | error |

---

## 预约优惠码详情联动

在预约优惠码详情页中，如果后端返回测试申请摘要：

```json
{
  "testingApplication": {
    "id": "pta_abc123",
    "status": "APPLIED",
    "notificationStatus": "NOT_SENT"
  }
}
```

则展示：

- “已申请产品测试计划”
- 申请状态
- 邮件状态
- “查看测试申请”链接或按钮

点击后跳转到产品测试申请页面并按 `id` 或 keyword 定位。若当前后台路由不支持直接打开详情，可以先跳转列表并带 keyword。

---

## 实施步骤

1. 新增 API service 和类型。
2. 新增产品测试申请列表页面。
3. 新增筛选表单和分页表格。
4. 新增详情抽屉或弹窗。
5. 实现状态更新操作。
6. 实现备注编辑操作。
7. 实现发送和重发资格邮件操作。
8. 实现导出按钮和文件下载处理。
9. 新增路由和菜单。
10. 补齐中英文文案。
11. 修改预约优惠码详情，展示测试申请入口。
12. 验证空数据、接口失败、邮件失败、导出失败等状态。

---

## 验收标准

- [ ] 菜单中可以进入“产品测试申请”页面。
- [ ] 列表能分页加载测试申请。
- [ ] keyword 可搜索姓名、邮箱、电话、牧场名称。
- [ ] 状态筛选可用。
- [ ] 邮件状态筛选可用。
- [ ] 报名时间范围筛选可用。
- [ ] 详情展示完整联系方式、牧场信息、状态、邮件状态和备注。
- [ ] 可以标记入选。
- [ ] 可以标记未入选。
- [ ] 可以编辑管理备注。
- [ ] 可以发送资格邮件。
- [ ] 发送失败时展示失败状态和错误原因。
- [ ] `FAILED` 状态可以重发。
- [ ] `SENT` 状态重发前有二次确认。
- [ ] 可以按当前筛选条件导出文件。
- [ ] 导出文件包含 `applicationId`。
- [ ] 预约优惠码详情能显示“已申请测试计划”入口。
- [ ] 空数据和接口失败状态有合理反馈。

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 邮件接口返回成功但邮件状态失败 | 前端按 `notificationStatus` 判断最终结果 |
| 操作误发资格邮件 | 发送和重发都需要二次确认 |
| 管理层筛选后难以定位申请 | 导出保留 `applicationId`，后台支持 keyword 搜索 |
| 预约优惠码页面职责膨胀 | 预约优惠码详情只展示入口，不处理筛选和发送 |
| 第一版过度复杂 | 不做批量导入，不做设备发放管理 |

---

**相关文档:**

- [后端测试申请任务](../backend/BACKEND-025-product-testing-application.md)
- [官网测试计划报名任务](../shop-frontend/SHOP-FE-019-testing-program-opt-in.md)
- [产品测试计划申请 API](../../../02-api/product-testing-applications.md)
