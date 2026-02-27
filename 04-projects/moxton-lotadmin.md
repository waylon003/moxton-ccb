---
last_verified: 2026-02-26
verified_against: [ADMIN-FE-007, ADMIN-FE-006, ADMIN-FE-005]
---

# moxton-lotadmin 项目状态

> **项目**: Moxton 管理后台
> **路径**: `E:\moxton-lotadmin`
> **类型**: Vue 3 应用
> **框架**: Soybean Admin
> **端口**: 3002
> **状态**: 🟢 活跃

## 项目概述

Moxton 管理后台，用于管理产品、分类、在线订单、咨询订单等后台操作。基于 Vue 3 和 Soybean Admin 框架构建。

## 技术栈

- **框架**: Vue 3
- **管理模板**: Soybean Admin
- **语言**: TypeScript
- **UI 组件库**: Naive UI (NPopconfirm 等)

## 已实现功能模块

| 模块 | 说明 | 状态 |
|------|------|------|
| 产品管理 | 商品 CRUD、批量操作、状态管理 | ✅ 完成 |
| 分类管理 | 分类树管理、排序、状态切换 | ✅ 完成 |
| 在线订单管理 | 订单列表/详情/搜索/状态操作/发货/物流 | ✅ 完成 |
| 咨询订单管理 | 咨询订单列表、状态管理、批量删除 | ✅ 完成 |
| 订单操作历史 | 时间线展示操作人/时间/类型/备注 | ✅ 完成 |

### 在线订单管理（详细）

通过 8 个已完成任务迭代构建：

- 完整的订单列表、搜索筛选（keyword 多字段）、分页
- 订单详情查看（客户信息/收货地址/商品明细/支付信息/物流信息）
- 订单操作：发货、确认收货、取消订单（均有二次确认弹窗）
- 物流信息：SHIPPED 状态可补充物流单号/公司/备注；DELIVERED 状态也可查看物流卡片
- 操作历史：时间线 UI，action 映射中文文案，兼容旧数据，支付 webhook 本地化
- 状态显示优化：CONFIRMED 显示为"待发货"
- 已移除无效按钮（新增订单、批量删除）

### 缺失功能模块

| 模块 | 说明 | 状态 |
|------|------|------|
| 用户管理 | 用户列表、角色分配、状态管理 | ❌ 未实现 |
| 数据统计/仪表盘 | 销售统计、订单趋势 | ❌ 未实现 |
| 系统设置 | 站点配置、通知设置 | ❌ 未实现 |

## 依赖的 API

### 后端 API (moxton-lotapi:3006)

| API 端点 | 方法 | 用途 |
|---------|------|------|
| `/products` | GET/POST/PUT/DELETE | 产品管理 |
| `/products/batch/*` | POST/PUT | 批量操作 |
| `/categories/*` | GET/POST/PUT/DELETE | 分类管理 |
| `/orders/admin` | GET | 订单列表（支持 keyword 搜索） |
| `/orders/admin/:id` | GET | 订单详情（含 metadata） |
| `/orders/admin/:id/status` | PUT | 更新订单状态 |
| `/orders/admin/:id/ship` | POST | 发货 |
| `/orders/admin/:id/shipping-info` | PATCH | 补充物流信息 |
| `/orders/admin/:id/history` | GET | 操作历史 |
| `/offline-orders/admin` | GET | 咨询订单列表 |
| `/offline-orders/admin/:id/status` | PUT | 更新咨询订单状态 |
| `/offline-orders/admin/batch/delete` | POST | 批量删除咨询订单 |
| `/upload/image` | POST | 图片上传 |

## 已知质量问题

- pnpm lint: 102 errors / 76 warnings（2026-02-25 QA 报告）
- pnpm build: spawn EPERM（环境权限问题）
- 功能层面验证通过，基线质量待修复

## 相关文档

- [API 文档](../02-api/)
- [集成指南](../03-guides/)
- [项目协调](./COORDINATION.md)
- [依赖关系](./DEPENDENCIES.md)
