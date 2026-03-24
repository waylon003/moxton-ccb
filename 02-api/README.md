# API 文档中心

本目录包含 Moxton 后端 API 的完整文档。

## 📡 API 模块

| 模块 | 文档 | 状态 |
|------|------|------|
| 认证系统 | [auth.md](auth.md) | ✅ |
| 权限与角色 | [authorization.md](authorization.md) | ✅ |
| 购物车 | [cart.md](cart.md) | ✅ |
| 订单管理 | [orders.md](orders.md) | ✅ |
| 支付系统 | [payments.md](payments.md) | ✅ |
| 商品管理 | [products.md](products.md) | ✅ |
| 分类管理 | [categories.md](categories.md) | ✅ |
| 线下咨询订单 | [offline-orders.md](offline-orders.md) | ✅ |
| 地址管理 | [addresses.md](addresses.md) | ✅ |
| 系统与诊断 | [system.md](system.md) | ✅ |
| 文件上传 | [upload.md](upload.md) | ✅ |
| 通知系统 | [notifications.md](notifications.md) | ✅ |

## 🔗 基础信息

- **Base URL**: `http://localhost:3033`
- **认证方式**: Bearer Token / X-Guest-ID
- **数据格式**: JSON
- **字符编码**: UTF-8
- **运行探针**: `GET /health`、`GET /version`（已于 2026-03-24 16:19 +08:00 再次复核；两个接口当前均返回标准 envelope 并携带 `X-Request-ID`，未知根路由 `404` 错误包以 [system.md](system.md) 为准）
- **文档归属**: `BACKEND-015` 首次修复根路由统一响应契约与 `X-Request-ID`，`BACKEND-016` 最新 QA 证据中的 `contract-check.json` 已明确指向 [system.md](system.md)

## 📝 使用指南

### 认证

大部分 API 需要认证，支持两种方式：

```typescript
// 登录用户
Headers: {
  'Authorization': 'Bearer <token>'
}

// 游客
Headers: {
  'X-Guest-ID': '<guest-id>'
}
```

### 响应格式

标准响应格式：

```typescript
{
  "code": 200,
  "message": "Success",
  "data": { ... },
  "timestamp": "2026-03-19T09:50:07.845Z",
  "success": true
}
```

### 错误处理

```typescript
{
  "code": 400,
  "message": "Error message",
  "data": null,
  "timestamp": "2026-03-19T09:50:07.846Z",
  "success": false
}
```

## 🔧 维护规范

1. **后端变更时同步更新** - 修改 API 后立即更新对应文档
2. **保持向后兼容** - 重大变更需先通知前端
3. **版本标记** - 在文档顶部标注最后更新日期
4. **测试验证** - 新 API 必须通过测试后才能标记为 ✅

## 📚 相关文档

- [集成指南](../03-guides/)
- [项目状态](../04-projects/)
- [验证报告](../05-verification/)
