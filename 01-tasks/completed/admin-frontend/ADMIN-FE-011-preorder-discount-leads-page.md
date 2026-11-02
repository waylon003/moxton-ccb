# Tech-Spec: 后台预约优惠码名单与详情页

**任务ID:** ADMIN-FE-011
**创建时间:** 2026-06-17
**状态:** 开发完成
**角色:** CRUD前端工程师
**项目:** moxton-lotadmin
**优先级:** P1
**技术栈:** Vue 3 + TypeScript + SoybeanAdmin + Naive UI
**QA_LEVEL:** smoke

---


## 概述

### 问题陈述

预售预约发码上线后，运营需要在后台查看预约用户、预约产品、优惠码和邮件发送状态。

### 解决方案

新增“预约优惠码”菜单页，接入后端预约名单和详情接口，提供搜索、筛选、详情查看。

### 范围

**包含:**
- 新增预约优惠码 API 封装。
- 新增预约优惠码列表页。
- 新增详情弹窗或详情抽屉。
- 支持 keyword、productId、emailStatus、source 筛选。
- 展示优惠码、过期时间、邮件状态。

**不包含:**
- 重发邮件操作，单独由 ADMIN-FE-012 处理。
- 后端接口开发。

---

## 开发上下文

参考现有页面：

- `src/views/consultation-order/index.vue`
- `src/views/consultation-order/modules/consultation-order-detail.vue`
- `src/service/api/consultation-order.ts`

建议新增：

- `src/service/api/preorder-discount.ts`
- `src/views/preorder-discount/index.vue`
- `src/views/preorder-discount/modules/preorder-discount-detail.vue`

需要更新：

- `src/router/elegant/routes.ts` 或使用项目既有路由生成流程。
- `src/locales/langs/zh-cn.ts`
- `src/locales/langs/en-us.ts`

### 依赖项

- 前置任务：`BACKEND-019`
- 前置任务：`BACKEND-023`

### API 文档来源

- 预约优惠码列表和详情接口以 `../../../02-api/preorder-discounts.md` 为准。
- 列表、详情、筛选参数、字段命名、状态枚举和错误结构都按 `BACKEND-023` 更新后的 API 文档实现。
- 本任务文档中的字段列表只用于说明页面展示目标；如果与 `02-api` 文档不一致，以 `02-api` 文档为最终字段契约。

---

## 技术方案

### 页面结构

列表字段：

- 姓名
- 邮箱
- 电话
- 牧场名
- 预约产品
- 来源
- 邮件状态
- 提交时间
- 操作

详情字段：

- 完整表单信息
- 产品信息
- 优惠码
- 折扣比例
- 过期时间
- 邮件状态
- 发送时间
- 失败原因

### API 调用

接口来源：`../../../02-api/preorder-discounts.md`

```http
GET /preorder-discounts/admin/leads
GET /preorder-discounts/admin/leads/:id
```

---

## 实施步骤

1. 新增 API service 和类型。
2. 新增列表页面。
3. 新增筛选区。
4. 新增详情弹窗或抽屉。
5. 新增路由和菜单。
6. 补齐中英文路由文案。
7. 参考现有列表页做分页和加载状态。

---

## 验收标准

- [ ] 菜单中可以进入“预约优惠码”页面。
- [ ] 列表能分页加载预约记录。
- [ ] keyword 筛选可用。
- [ ] 产品、邮件状态、来源筛选可用。
- [ ] 详情页展示表单信息、产品、优惠码和邮件状态。
- [ ] 空数据和接口失败状态有合理反馈。

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 路由生成机制不熟 | 参考已有 `consultation-order` 页面和路由配置 |
| 后端接口字段不一致 | 按 `../../../02-api/preorder-discounts.md` 中 `BACKEND-023` 更新后的接口文档调整类型 |

---

**相关文档:**
- [开发计划](../../docs/plans/2026-06-17-preorder-discount-code-closed-loop-plan.md)
- [项目状态](../../04-projects/moxton-lotadmin.md)
