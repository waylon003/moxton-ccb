# Tech-Spec: Auth 接口规范化

**创建时间:** 2026-02-26
**状态:** 准备开发
**角色:** 后端工程师
**项目:** moxton-lotapi
**优先级:** P1
**技术栈:** Node.js + Koa + TypeScript + Prisma + MongoDB

---

## 概述

### 问题陈述

当前 auth 接口存在以下问题：
1. 注册时用户名/邮箱重复返回 500 而非 409 Conflict
2. `GET /auth/getUserInfo` 和 `GET /auth/profile` 功能重叠，前端需要明确使用哪个
3. 商城前端即将对接登录/注册，需要确保接口行为规范

### 解决方案

规范化错误码，确认接口契约满足商城前端需求。

### 范围 (包含/排除)

**包含:**
- 注册接口重复用户名/邮箱返回 409
- 确认 login 返回的 token 格式和 user 对象字段
- 确认 getUserInfo 返回格式满足前端路由守卫需求
- 确认 change-password 接口路径一致性（文档有 `/auth/password` 和 `/auth/change-password` 两种写法）

**不包含:**
- 新增接口
- 数据模型变更

---

## 开发上下文

### 现有实现

| 文件 | 说明 |
|------|------|
| `src/routes/auth.ts` | 认证路由 |
| `src/controllers/User.ts` | register/login 方法 |
| `src/models/User.ts` | findByUsername/findByEmail |

### 依赖项

- 无外部依赖

---

## 技术方案

### 错误码规范化

| 场景 | 当前行为 | 目标行为 |
|------|---------|---------|
| 注册 - 用户名已存在 | 500 | 409 `{ code: 409, message: "用户名已存在" }` |
| 注册 - 邮箱已存在 | 500 | 409 `{ code: 409, message: "邮箱已存在" }` |
| 登录 - 用户不存在 | 401 | 401（保持不变） |
| 登录 - 密码错误 | 401 | 401（保持不变） |

### 接口路径确认

确认 change-password 的实际路径，统一文档和代码。

---

## 实施步骤

1. 修改 register controller，在创建用户前检查重复并返回 409
2. 确认 change-password 实际路径，统一为一种
3. 手动测试注册重复场景

---

## 验收标准

- [ ] 注册重复用户名返回 409
- [ ] 注册重复邮箱返回 409
- [ ] change-password 路径在代码和文档中一致
- [ ] 现有登录/注册流程不受影响

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 改动影响现有注册流程 | 仅修改错误处理分支，正常流程不变 |

---

**相关文档:**
- [Auth API 文档](../../02-api/auth.md)
- [项目状态](../../04-projects/moxton-lotapi.md)
