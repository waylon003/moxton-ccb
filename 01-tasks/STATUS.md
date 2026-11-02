# 任务状态总览

> 2026-11-02 复核：[三项目开发现状报告](../docs/reports/2026-11-02-project-status-review.md)。下表保留 7 月的任务文件归类；4 个 active 任务已有不同程度实现，completed 也不等于全部已提交、验收或部署。恢复开发前请先核对报告。

**更新时间**: 2026-07-13
**活跃任务**: 4 个

## 项目映射

| 角色 | 标识 | 项目 | 仓库路径 |
|------|------|------|----------|
| 独立站前端 | `SHOP-FE` | nuxt-moxton | `E:\nuxt-moxton` |
| 管理后台前端 | `ADMIN-FE` | moxton-lotadmin | `E:\moxton-lotadmin` |
| 后端 | `BACKEND` | moxton-lotapi | `E:\moxton-lotapi` |

## 任务统计

| 角色 | backlog | active | completed | 总计 |
|------|---------|--------|-----------|------|
| SHOP-FE | 0 | 1 | 21 | 22 |
| ADMIN-FE | 0 | 2 | 21 | 23 |
| BACKEND | 0 | 1 | 32 | 33 |
| **TOTAL** | **0** | **4** | **74** | **78** |

## 目录结构

```text
01-tasks/
|-- active/
|   |-- shop-frontend/
|   |-- admin-frontend/
|   `-- backend/
|-- backlog/
|   |-- shop-frontend/
|   |-- admin-frontend/
|   `-- backend/
|-- completed/
|   |-- shop-frontend/
|   |-- admin-frontend/
|   `-- backend/
`-- templates/
```

## 当前活跃任务

### 独立站前端 (SHOP-FE)

| 任务ID | 标题 |
|--------|------|
| [SHOP-FE-022](./active/shop-frontend/SHOP-FE-022-preorder-ranch-address-country-region-locality-postcode.md) | 预约预售表单接入 Google 牧场地址搜索 |

### 管理后台前端 (ADMIN-FE)

| 任务ID | 标题 |
|--------|------|
| [ADMIN-FE-020](./active/admin-frontend/ADMIN-FE-020-preorder-ranch-address-region-fields-display.md) | 后台预约线索展示牧场地址结构化字段 |
| [ADMIN-FE-021](./active/admin-frontend/ADMIN-FE-021-product-testing-application-address-fields-display.md) | 后台产品测试申请展示结构化地址字段 |

### 后端 (BACKEND)

| 任务ID | 标题 |
|--------|------|
| [BACKEND-028](./active/backend/BACKEND-028-preorder-ranch-address-country-region-locality-postcode.md) | 预约预售线索保存 Google 解析后的牧场地址字段 |

## backlog 任务

当前没有 `backlog` 任务。

## 已完成任务

### 独立站前端 (SHOP-FE)

| 任务ID | 标题 |
|--------|------|
| [SHOP-FE-001](./completed/shop-frontend/SHOP-FE-001-stripe-elements-integration.md) | 独立站结账页 Stripe Elements 集成 |
| [SHOP-FE-002](./completed/shop-frontend/SHOP-FE-002-login-register-auth.md) | 登录注册认证 - UI 规范化 + API 修复 |
| [SHOP-FE-003](./completed/shop-frontend/SHOP-FE-003-account-center.md) | 个人中心 - API 联调修复 + UI 规范化 |
| [SHOP-FE-004](./completed/shop-frontend/SHOP-FE-004-account-center-sidebar-fix.md) | 个人中心侧边栏切换报错修复 + 状态下拉优化 |
| [SHOP-FE-005](./completed/shop-frontend/SHOP-FE-005-backend-fix-1-fix-order-get-orders-user-500-2.md) | 地址自动补全 API 集成 |
| [SHOP-FE-006](./completed/shop-frontend/SHOP-FE-006-layout.md) | 修复地址自动补全组件布局 |
| [SHOP-FE-007](./completed/shop-frontend/SHOP-FE-007.md) | 商城前端 UI 修复合集 |
| [SHOP-FE-008](./completed/shop-frontend/SHOP-FE-008.md) | 订单详情页图片显示与箭头符号修复 |
| [SHOP-FE-009](./completed/shop-frontend/SHOP-FE-009.md) | 订单记录和咨询记录页面布局修复 |
| [SHOP-FE-010](./completed/shop-frontend/SHOP-FE-010-mobile-nav-refactor.md) | 移动端导航栏重构 |
| [SHOP-FE-011](./completed/shop-frontend/SHOP-FE-011-mobile-address-fix.md) | 移动端地址管理优化 |
| [SHOP-FE-012](./completed/shop-frontend/SHOP-FE-012-order-detail-fixes.md) | 订单详情页缺陷修复 |
| [SHOP-FE-013](./completed/shop-frontend/SHOP-FE-013-payment-intent-smart-reuse.md) | 支付意图智能复用 |
| [SHOP-FE-014](./completed/shop-frontend/SHOP-FE-014-frontend-dev-env-recovery.md) | 前端开发环境恢复 |
| [SHOP-FE-015](./completed/shop-frontend/SHOP-FE-015-order-payment-display-and-checkout-redirect.md) | 订单详情支付信息展示 + 结账第4步确认直达 /shop |
| [SHOP-FE-016](./completed/shop-frontend/SHOP-FE-016-purchase-mode-and-preorder-entry.md) | 官网购买模式展示与预售预约入口 |
| [SHOP-FE-017](./completed/shop-frontend/SHOP-FE-017-preorder-discount-form.md) | 固定预售预约表单页与优惠码提交接入 |
| [SHOP-FE-018](./completed/shop-frontend/SHOP-FE-018-shop-preorder-coming-soon-display.md) | 官网商店预售产品“即将上线”展示修正 |
| [SHOP-FE-019](./completed/shop-frontend/SHOP-FE-019-testing-program-opt-in.md) | 官网预约页产品测试计划报名入口 |
| [SHOP-FE-020](./completed/shop-frontend/SHOP-FE-020-preorder-ranch-fields-position-adjustment.md) | 预约页牧场信息字段位置与测试计划勾选调整 |
| [SHOP-FE-021](./completed/shop-frontend/SHOP-FE-021-preorder-product-feedback-survey-ui.md) | 官网预售预约页产品反馈 Survey UI 原型 |

### 管理后台前端 (ADMIN-FE)

| 任务ID | 标题 |
|--------|------|
| [ADMIN-DATA-001](./completed/admin-frontend/ADMIN-DATA-001-create-real-preorder-products.md) | 操作任务: 后台录入两款真实预售产品 |
| [ADMIN-FE-001](./completed/admin-frontend/ADMIN-FE-001-online-order-management.md) | 在线订单管理页面实施计划 |
| [ADMIN-FE-001](./completed/admin-frontend/ADMIN-FE-001-status-display-fix.md) | 订单状态显示优化 |
| [ADMIN-FE-002](./completed/admin-frontend/ADMIN-FE-002-operation-confirmation.md) | 订单操作二次确认 |
| [ADMIN-FE-003](./completed/admin-frontend/ADMIN-FE-003-order-history-ui.md) | 操作历史 UI 对接 |
| [ADMIN-FE-004](./completed/admin-frontend/ADMIN-FE-004-remove-invalid-buttons.md) | 移除无效按钮 |
| [ADMIN-FE-005](./completed/admin-frontend/ADMIN-FE-005-supplement-shipping-info.md) | 补充物流信息 UI |
| [ADMIN-FE-006](./completed/admin-frontend/ADMIN-FE-006-order-detail-shipping-info-visibility-fix.md) | 在线订单详情物流信息展示修复 |
| [ADMIN-FE-007](./completed/admin-frontend/ADMIN-FE-007-online-order-history-event-rendering-normalization.md) | 在线订单操作历史展示规范化 |
| [ADMIN-FE-008](./completed/admin-frontend/ADMIN-FE-008-user-management-page.md) | 用户管理页面 |
| [ADMIN-FE-009](./completed/admin-frontend/ADMIN-FE-009-role-based-access-control.md) | 角色门禁 + 菜单权限过滤 |
| [ADMIN-FE-010](./completed/admin-frontend/ADMIN-FE-010-product-purchase-mode-config.md) | 后台产品购买模式配置 |
| [ADMIN-FE-011](./completed/admin-frontend/ADMIN-FE-011-preorder-discount-leads-page.md) | 后台预约优惠码名单与详情页 |
| [ADMIN-FE-012](./completed/admin-frontend/ADMIN-FE-012-preorder-email-resend.md) | 预约优惠码邮件重发操作 |
| [ADMIN-FE-013](./completed/admin-frontend/ADMIN-FE-013-product-preorder-page-content-config.md) | 后台产品预售预约页内容配置 |
| [ADMIN-FE-014](./completed/admin-frontend/ADMIN-FE-014-product-list-preorder-management.md) | 后台商品列表预售管理字段优化 |
| [ADMIN-FE-015](./completed/admin-frontend/ADMIN-FE-015-product-form-preorder-simplification.md) | 产品表单预售模式简化与库存校验修正 |
| [ADMIN-FE-016](./completed/admin-frontend/ADMIN-FE-016-preorder-source-label-mapping.md) | 预约优惠码来源字段展示映射 |
| [ADMIN-FE-017](./completed/admin-frontend/ADMIN-FE-017-product-testing-applications.md) | 后台产品测试计划申请列表与资格邮件 |
| [ADMIN-FE-018](./completed/admin-frontend/ADMIN-FE-018-preorder-lead-ranch-fields-display.md) | 预约优惠码后台展示牧场扩展字段 |
| [ADMIN-FE-019](./completed/admin-frontend/ADMIN-FE-019-preorder-product-feedback-survey-display.md) | 后台展示预售预约产品反馈 Survey |

### 后端 (BACKEND)

| 任务ID | 标题 |
|--------|------|
| [BACKEND-001](./completed/backend/BACKEND-001-ship-api-optional-tracking.md) | 发货接口参数调整 |
| [BACKEND-002](./completed/backend/BACKEND-002-admin-order-detail-api.md) | 管理员获取订单详情 API |
| [BACKEND-002](./completed/backend/BACKEND-002-order-history-feature.md) | 订单操作历史功能 |
| [BACKEND-003](./completed/backend/BACKEND-003-cleanup-expired-orders.md) | 清理过期未支付订单 |
| [BACKEND-003](./completed/backend/BACKEND-003-order-payment-stripe-fix.md) | 在线订单 + Stripe 支付模块修复 |
| [BACKEND-004](./completed/backend/BACKEND-004-update-shipping-info.md) | 补充/修改物流信息接口 |
| [BACKEND-005](./completed/backend/BACKEND-005-keyword-search-fix.md) | 订单查询 keyword 参数不生效 |
| [BACKEND-006](./completed/backend/BACKEND-006-admin-order-detail-include-metadata.md) | 管理员订单详情接口补全物流 metadata |
| [BACKEND-007](./completed/backend/BACKEND-007-online-order-history-event-contract-normalization.md) | 在线订单操作历史事件契约规范化 |
| [BACKEND-008](./completed/backend/BACKEND-008-admin-user-management-api.md) | Admin 用户管理 API 重构与补全 |
| [BACKEND-009](./completed/backend/BACKEND-009-auth-api-normalization.md) | Auth 接口规范化 |
| [BACKEND-010](./completed/backend/BACKEND-010-role-system-operator.md) | 角色系统扩展 - 新增 operator 角色 |
| [BACKEND-011](./completed/backend/BACKEND-011-backend-fix-1-fix-order-get-orders-user-500-2.md) | 修复个人中心接口 500 错误 |
| [BACKEND-012](./completed/backend/BACKEND-012-pagination.md) | 修复分页参数不合规返回 400 |
| [BACKEND-013](./completed/backend/BACKEND-013-order-images-format.md) | 修复订单接口商品图片返回格式 |
| [BACKEND-014](./completed/backend/BACKEND-014-order-payment-query-api.md) | 新增订单支付查询 API |
| [BACKEND-015](./completed/backend/BACKEND-015-fix-uuid-esm-require.md) | 修复后端启动 uuid ESM require 报错 |
| [BACKEND-016](./completed/backend/BACKEND-016-start-backend-dev-server.md) | 启动本机 3033 后端服务 |
| [BACKEND-017](./completed/backend/BACKEND-017-product-purchase-mode.md) | 商品购买模式字段与服务端拦截 |
| [BACKEND-018](./completed/backend/BACKEND-018-preorder-discount-claim-api.md) | 预售预约优惠码数据模型与多产品提交接口 |
| [BACKEND-019](./completed/backend/BACKEND-019-preorder-email-and-admin-api.md) | 预约优惠码邮件发送与后台管理接口 |
| [BACKEND-020](./completed/backend/BACKEND-020-product-preorder-page-content.md) | 产品预售预约页内容字段支持 |
| [BACKEND-021](./completed/backend/BACKEND-021-clean-test-products.md) | 清理后端测试商品数据 |
| [BACKEND-022](./completed/backend/BACKEND-022-admin-product-purchase-mode-filter.md) | 后台商品列表购买模式筛选支持 |
| [BACKEND-023](./completed/backend/BACKEND-023-preorder-api-documentation-update.md) | 预售预约接口文档更新 |
| [BACKEND-024](./completed/backend/BACKEND-024-preorder-email-template-and-code-format.md) | 预售优惠码邮件移除产品主图与短码规则调整 |
| [BACKEND-025](./completed/backend/BACKEND-025-product-testing-application.md) | 产品测试计划申请数据模型与后台接口 |
| [BACKEND-026](./completed/backend/BACKEND-026-preorder-lead-ranch-fields.md) | 预约优惠码线索补充牧场扩展字段 |
| [BACKEND-027](./completed/backend/BACKEND-027-preorder-product-feedback-survey-fields.md) | 后端保存预售预约产品反馈 Survey 字段 |
| [BUG-001](./completed/backend/BUG-001-order-api-500-error.md) | 订单列表 API 返回 500 错误 |
| [BUG-002](./completed/backend/BUG-002-order-items-field-name.md) | findByIdWithDetails 使用错误的字段名 |
| [BUG-004](./completed/backend/BUG-004-stripe-payment-intent-params.md) | Stripe Payment Intent 参数冲突 |

