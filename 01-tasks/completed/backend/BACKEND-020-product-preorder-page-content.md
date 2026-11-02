# Tech-Spec: 产品预售预约页内容字段支持

**任务ID:** BACKEND-020
**创建时间:** 2026-06-23
**最后更新:** 2026-06-27
**状态:** 已完成
**角色:** 后端工程师
**项目:** moxton-lotapi
**优先级:** P1
**技术栈:** Node.js + Koa + TypeScript + Prisma + MySQL
**QA_LEVEL:** smoke

---

## 概述

> 2026-06-27 备注：本任务已完成并保留 `metadata.preorder.videoUrl` 兼容字段。但当前预约页方案已调整为固定页面，不展示视频；官网本阶段只需要商品主图、商品名称和说明等基础信息。已有 `videoUrl` 字段不需要删除，但不得作为 `SHOP-FE-017` 的前置依赖。

### 问题陈述

早期方案中，官网预售产品会进入按 `productId` 渲染内容的预约页，因此需要支持产品级预售内容配置。当前最新方案已经调整为固定 `/preorder-discount` 页面：表单字段固定，页面整体固定，产品展示区从预售商品列表读取商品主图、名称和说明。当前产品已有 `metadata` 字段，仍可承载轻量的预售展示内容，但官网本阶段不依赖视频。

### 解决方案

复用 `Product.metadata` 存储 `preorder` 配置，不新增独立数据表。后端产品创建、更新、详情和后台列表接口需要接收并返回该字段，保证后台可配置、官网可读取。

推荐结构：

```json
{
  "preorder": {
    "heroImage": "https://example.com/a.jpg",
    "description": "Short marketing copy for the preorder page.",
    "videoUrl": "https://example.com/a.mp4"
  }
}
```

说明：`videoUrl` 是历史兼容字段，本阶段官网预约页不读取、不展示。

### 范围

**包含:**
- 确认产品接口返回 `metadata`。
- 创建/更新产品时允许保存 `metadata.preorder`。
- 对 `metadata` 做 JSON 合法性处理，避免非法字符串写入。
- 保留历史 `metadata` 里的其他内容，不覆盖无关字段。

**不包含:**
- 后台表单 UI。
- 官网预约页 UI。
- 预约提交和发码接口。

---

## 开发上下文

重点文件：

- `prisma/schema.prisma`
- `src/controllers/Product.ts`
- `src/models/Product.ts`

当前情况：

- `Product` 已有 `metadata String? @db.Text`。
- 产品创建/更新接口当前主要处理 `name`、`description`、`content`、`price`、`images`、`specifications`、`tags`、`purchaseMode`。
- 需要检查 `metadata` 是否已经被产品接口完整返回；如果没有，需要补齐。

### 依赖项

- 前置任务：`BACKEND-017`

---

## 技术方案

### 字段约定

后端不需要理解所有营销文案含义，但需要保证结构可存取：

```ts
type ProductPreorderMetadata = {
  preorder?: {
    heroImage?: string
    description?: string
    videoUrl?: string // 历史兼容字段，本阶段官网不使用
  }
}
```

### 创建/更新策略

- 请求体允许传 `metadata`。
- 如果 `metadata` 是对象，保存前 `JSON.stringify`。
- 如果 `metadata` 是字符串，必须能 `JSON.parse`，否则返回参数错误。
- 更新时如果只传 `metadata.preorder`，不要清空其他 metadata 内容。
- 若项目现有风格不方便做深合并，可以要求前端提交完整 `metadata` 对象，但必须在任务说明或接口注释中明确。

### 返回策略

- 商品详情和后台商品列表应返回 `metadata`。
- 如果当前项目已有统一 JSON 解析逻辑，返回对象。
- 如果历史接口返回字符串，官网和后台需要兼容字符串解析；但新实现优先返回对象。

---

## 实施步骤

1. 检查产品接口当前是否返回 `metadata`。
2. 产品创建接口接收并保存 `metadata`。
3. 产品更新接口接收并保存 `metadata`。
4. 增加 `metadata` JSON 校验和对象序列化。
5. 确保产品详情接口返回可被官网使用的 `metadata.preorder`。
6. 补充最小接口测试或脚本验证。

---

## 验收标准

- [ ] 创建预售产品时可以保存 `metadata.preorder`。
- [ ] 编辑预售产品时可以更新 `metadata.preorder`。
- [ ] 产品详情接口返回 `metadata.preorder`。
- [ ] 后台商品接口返回 `metadata.preorder`。
- [ ] 非预售产品保留原有 `metadata` 行为。
- [ ] 非法 JSON 不会静默写入数据库。

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 覆盖历史 metadata | 更新时尽量合并，至少要求前端提交完整 metadata |
| metadata 返回格式不一致 | 官网和后台类型要兼容对象和字符串 |
| 文案字段扩展 | 放在 `metadata.preorder` 内，避免后续再改表 |

---

**相关文档:**
- [开发计划](../../docs/plans/2026-06-17-preorder-discount-code-closed-loop-plan.md)
- [项目状态](../../04-projects/moxton-lotapi.md)

