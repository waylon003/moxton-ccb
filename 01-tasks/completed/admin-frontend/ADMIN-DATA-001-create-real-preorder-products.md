# 操作任务: 后台录入两款真实预售产品

**任务ID:** ADMIN-DATA-001
**创建时间:** 2026-06-27
**状态:** 开发完成
**执行角色:** 业务方 / 后台管理员
**项目:** moxton-lotadmin
**优先级:** P0
**QA_LEVEL:** smoke

---

## 概述

### 问题陈述

当前后端商品列表都是测试商品。预约页后续会动态读取后台 `PREORDER` 商品作为可预约产品，因此必须先清理测试商品，再由后台录入两款真实预售产品。

### 解决方案

在 `BACKEND-021` 清理测试商品完成后，进入后台管理系统，按资料包录入两款真实产品，并把购买模式设置为 `PREORDER`。

资料包路径：

```text
E:\moxton-ccb\docs\assets\preorder-products
```

---

## 前置条件

- `BACKEND-021` 已完成，测试商品已软删除。
- 后台商品列表中不再混有测试商品。
- 后台产品新增/编辑功能可用。
- 产品图片上传能力可用。

---

## 需要录入的产品

### 产品 1：AI Sheep Counting Camera

建议配置：

- 商品名称：`AI Sheep Counting Camera`
- 购买模式：`PREORDER`
- 商品描述：`Real-time sheep counting for smarter pasture management`
- 商品标签：
  - `Fast Recognition`
  - `Portable`
  - `Real-time Monitoring`
- 商品主图：`docs/assets/preorder-products/sheep-counting-camera-main.png`
- 辅助图可选：`docs/assets/preorder-products/sheep-counting-display-panel.png`
- `metadata.preorder.description`：可填同商品描述
- `metadata.preorder.heroImage`：可不填，官网本阶段优先用商品主图
- `metadata.preorder.videoUrl`：不填

### 产品 2：AI Wool Diameter Analyzer

建议配置：

- 商品名称：`AI Wool Diameter Analyzer`
- 购买模式：`PREORDER`
- 商品描述：`Instant wool micron analysis in the field`
- 商品标签：
  - `Instant Result`
  - `Accurate Data`
  - `Handheld Device`
- 商品主图：`docs/assets/preorder-products/wool-diameter-analyzer-main.png`
- `metadata.preorder.description`：可填同商品描述
- `metadata.preorder.heroImage`：可不填，官网本阶段优先用商品主图
- `metadata.preorder.videoUrl`：不填

---

## 操作步骤

1. 确认 `BACKEND-021` 已完成。
2. 登录后台管理系统。
3. 进入商品管理。
4. 新建 `AI Sheep Counting Camera`。
5. 上传商品主图。
6. 设置购买模式为 `PREORDER`。
7. 填写商品描述和标签。
8. 保存后确认列表中购买模式显示为预售。
9. 新建 `AI Wool Diameter Analyzer`。
10. 上传商品主图。
11. 设置购买模式为 `PREORDER`。
12. 填写商品描述和标签。
13. 保存后确认列表中购买模式显示为预售。
14. 确认官网商品接口能返回这两款商品，且 `purchaseMode = PREORDER`。

---

## 验收标准

- [ ] 后台商品列表中存在 `AI Sheep Counting Camera`。
- [ ] 后台商品列表中存在 `AI Wool Diameter Analyzer`。
- [ ] 两款商品购买模式都是 `PREORDER`。
- [ ] 两款商品都有商品主图。
- [ ] 两款商品都有描述。
- [ ] 两款商品不是 `ONLINE`。
- [ ] 官网商品接口能返回两款预售商品。
- [ ] 预约页后续可以读取到这两款产品作为可预约产品。

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 忘记设置 `PREORDER` | 保存后必须在列表确认购买模式 |
| 商品主图缺失 | 预约页和邮件都会依赖商品主图，必须上传 |
| 测试商品未清理 | 必须先执行 BACKEND-021 |
| 价格字段干扰购买状态 | 以 `purchaseMode` 为准，不再用价格判断 |

---

**相关资料:**

- [预售产品资料包](../../../docs/assets/preorder-products/README.md)
- [结构化产品资料](../../../docs/assets/preorder-products/preorder-products.json)
- [开发计划](../../../docs/plans/2026-06-17-preorder-discount-code-closed-loop-plan.md)
