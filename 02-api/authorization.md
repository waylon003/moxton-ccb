# 权限与角色 API 说明（BACKEND-010）

## 目标

本次变更引入统一角色中间件 `requireRole`，并新增 `operator` 角色，用于开放管理端部分能力给运营角色。

## 中间件说明

### `requireRole(...allowedRoles)`

定义位置：`src/middleware/role.ts`

**行为**
- 若请求未登录（`ctx.user`/`ctx.state.user` 不存在）返回 `401`
- 若用户角色不在允许列表中返回 `403`
- 角色命中后放行到业务控制器

**返回示例**

未登录（401）：
```json
{
  "code": 401,
  "message": "No token provided",
  "data": null,
  "timestamp": "2026-02-27T16:00:00.000Z",
  "success": false
}
```

角色不足（403）：
```json
{
  "code": 403,
  "message": "Access denied. Required role: admin or operator",
  "data": null,
  "timestamp": "2026-02-27T16:00:00.000Z",
  "success": false
}
```

## 角色定义

| 角色 | 说明 |
|------|------|
| `user` | 普通用户，仅前台能力 |
| `operator` | 运营角色，拥有商品/分类/订单/上传管理能力 |
| `admin` | 管理员，拥有全部管理能力（含用户管理） |

---

## 路由权限矩阵

以下为 BACKEND-010 影响范围内的核心路由（来自 `src/routes` 现状）：

### Products（`/products`）

| 方法 | 路径 | 鉴权要求 |
|------|------|----------|
| POST | `/products` | 登录 + `admin/operator` |
| GET | `/products/admin/all` | 登录 + `admin/operator` |
| PUT | `/products/batch/stock` | 登录 + `admin/operator` |
| DELETE | `/products/batch` | 登录 + `admin/operator` |
| POST | `/products/batch/restore` | 登录 + `admin/operator` |
| GET | `/products/deleted` | 登录 + `admin/operator` |
| PUT | `/products/:id` | 登录 + `admin/operator` |
| DELETE | `/products/:id` | 登录 + `admin/operator` |
| PUT | `/products/:id/stock` | 登录 + `admin/operator` |
| POST | `/products/:id/restore` | 登录 + `admin/operator` |

### Categories（`/categories`）

| 方法 | 路径 | 鉴权要求 |
|------|------|----------|
| POST | `/categories` | 登录 + `admin/operator` |
| PUT | `/categories/:id` | 登录 + `admin/operator` |
| DELETE | `/categories/:id` | 登录 + `admin/operator` |
| DELETE | `/categories/batch` | 登录 + `admin/operator` |
| PUT | `/categories/batch/status` | 登录 + `admin/operator` |
| PUT | `/categories/:id/move` | 登录 + `admin/operator` |

### Orders 管理端（`/orders/admin/**`）

| 方法 | 路径 | 鉴权要求 |
|------|------|----------|
| GET | `/orders/admin` | 登录 + `admin/operator` |
| GET | `/orders/admin/:id` | 登录 + `admin/operator` |
| PUT | `/orders/admin/:id/ship` | 登录 + `admin/operator` |
| PUT | `/orders/admin/:id/deliver` | 登录 + `admin/operator` |
| PUT | `/orders/admin/:id/status` | 登录 + `admin/operator` |
| PUT | `/orders/admin/:id/cancel` | 登录 + `admin/operator` |
| GET | `/orders/admin/:id/history` | 登录 + `admin/operator` |
| POST | `/orders/admin/cleanup-expired` | 登录 + `admin/operator` |
| PATCH | `/orders/admin/:id/shipping-info` | 登录 + `admin/operator` |
| GET | `/orders/admin/stats/all` | 登录 + `admin/operator` |

### Upload（`/upload`）

| 方法 | 路径 | 鉴权要求 |
|------|------|----------|
| POST | `/upload/avatar` | 仅登录 |
| POST | `/upload/single` | 登录 + `admin/operator` |
| POST | `/upload/image` | 登录 + `admin/operator` |
| POST | `/upload/multiple` | 登录 + `admin/operator` |
| DELETE | `/upload/delete` | 登录 + `admin/operator` |

---

## 与 BACKEND-008 的关系

- 用户管理路由 `/auth/admin/users/**` 仍然是 **仅 admin 可访问**。
- `operator` 无法访问 `/auth/admin/users`，会返回 `403`。
