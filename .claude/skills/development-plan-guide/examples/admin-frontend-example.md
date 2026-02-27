# ADMIN-FE-001: 商品管理页面

> **示例任务：CRUD前端单角色任务**

**创建时间:** 2026-02-08
**状态:** 准备开发
**角色:** CRUD前端工程师 (ADMIN-FE)
**项目:** moxton-lotadmin
**优先级:** P0
**技术栈:** Vue 3 + TypeScript + SoybeanAdmin + Naive UI

---

## 概述

### 问题陈述

后台管理系统需要商品管理功能，管理员可以查看、创建、编辑和删除商品信息。

### 解决方案

使用 Naive UI 的 Table 和 Form 组件实现商品列表和编辑表单，通过后端 API 进行 CRUD 操作。

### 范围 (包含/排除)

**包含:**
- 商品列表展示（分页、搜索、筛选）
- 商品创建和编辑表单
- 商品删除功能
- 商品状态管理（上架/下架）

**不包含:**
- 商品分类管理（单独任务）
- 商品库存管理（单独任务）
- 批量导入导出

---

## 开发上下文

### 现有实现

- 路由：`/products`
- 布局：使用 SoybeanAdmin 的标准布局
- API 基础地址：`http://localhost:3006/api`

### 依赖项

- 后端 API：`/products/*`
- Naive UI 组件库
- Vue Router

---

## 技术方案

### 架构设计

```
┌─────────────────────────────┐
│      Product Management     │
│                             │
│  ┌─────────┐  ┌──────────┐  │
│  │  List   │  │   Form   │  │
│  │  View   │  │  Editor  │  │
│  └─────────┘  └──────────┘  │
└─────────────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│         Backend API          │
│      /api/products/*         │
└─────────────────────────────┘
```

### 数据模型

```typescript
interface Product {
  id: string
  name: string
  description: string
  price: number
  categoryId: string
  images: string[]
  stock: number
  status: 'active' | 'inactive'
  createdAt: string
  updatedAt: string
}
```

### API 调用

1. **获取商品列表**
   - 端点：`GET /api/products`
   - 参数：`page`, `limit`, `search`, `status`

2. **创建商品**
   - 端点：`POST /api/products`

3. **更新商品**
   - 端点：`PATCH /api/products/:id`

4. **删除商品**
   - 端点：`DELETE /api/products/:id`

---

## 实施步骤

1. **创建商品列表页面**
   - 文件：`views/products/product-list.vue`
   - 使用 `n-data-table` 展示数据
   - 添加搜索和筛选功能

2. **创建商品表单组件**
   - 文件：`views/products/product-form.vue`
   - 使用 `n-form` 和表单项组件
   - 添加图片上传功能

3. **实现 CRUD 操作**
   - 连接后端 API
   - 处理成功/错误响应
   - 刷新列表数据

4. **添加确认对话框**
   - 删除前确认
   - 保存前验证

5. **状态管理**
   - 上架/下架切换
   - 批量操作

---

## 验收标准

- [ ] 可以查看商品列表，支持分页
- [ ] 可以通过名称搜索商品
- [ ] 可以按状态筛选商品
- [ ] 可以创建新商品
- [ ] 可以编辑现有商品
- [ ] 可以删除商品（有确认提示）
- [ ] 可以切换商品上架状态
- [ ] 表单验证正常工作
- [ ] 加载状态和错误提示正常显示

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 图片上传失败 | 使用组件库的 upload 组件处理错误 |
| 表单验证复杂 | 使用 Naive UI 的内置验证规则 |
| 列表性能问题 | 实现虚拟滚动或分页加载 |

---

**相关文档:**
- [商品 API](../../../02-api/products.md)
- [项目状态](../../../04-projects/moxton-lotadmin.md)
