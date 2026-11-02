# Tech-Spec: 预约优惠码来源字段展示映射

**任务ID:** ADMIN-FE-016  
**创建时间:** 2026-06-28  
**状态:** 准备开发  
**角色:** 管理后台前端工程师  
**项目:** moxton-lotadmin  
**优先级:** P1  
**技术栈:** Vue 3 + TypeScript + SoybeanAdmin + Naive UI  
**QA_LEVEL:** smoke

---

## 概述

### 问题陈述

预约优惠码列表和详情页当前直接展示接口返回的 `source` 原始值，例如：

```text
home_preorder
```

该值对开发排查有用，但对运营人员不够直观。后台管理系统中“来源”字段应该做展示映射，列表、筛选和详情页都显示可读文案。

### 解决方案

在后台前端新增统一的来源映射 helper：

- 列表表格“来源”列显示中文标签。
- 详情抽屉中的“来源”字段显示中文标签。
- 来源筛选下拉选项显示中文标签，提交查询时仍传原始 `source` 值。
- 未知来源保留原始值，避免后续新渠道没有映射时显示为空。

---

## 范围

**包含:**

- 新增或复用 `source` 映射方法。
- 修改预约优惠码列表来源列展示。
- 修改预约优惠码详情来源展示。
- 修改来源筛选控件选项展示。
- 保留筛选请求参数仍使用原始值。

**不包含:**

- 后端接口调整。
- 数据库字段调整。
- 官网来源参数生成逻辑调整。
- 二维码短链统计。

---

## 当前页面

相关页面：

- `src/views/preorder-discount/index.vue`
- `src/views/preorder-discount/modules/preorder-discount-detail.vue`
- `src/service/api/preorder-discount.ts`

API 文档来源：

- `../../../02-api/preorder-discounts.md`

当前接口字段：

```ts
source?: string | null
```

---

## 来源映射规则

本次先支持已知来源：

| 原始值 | 后台展示文案 | 说明 |
|------|------|------|
| `home_preorder` | 官网首页预约 | 官网首页“立即预约”入口 |
| `expo_2026` | 展会二维码 | 展会现场统一二维码 |
| `expo_sydney_2026` | 悉尼展会二维码 | 如果后续按展会城市区分 |
| `expo_booth_qr_2026` | 展位二维码 | 展位现场二维码 |
| `expo_brochure_2026` | 展会手册二维码 | 宣传册 / 手册二维码 |

兜底规则：

- `source` 为空、`null`、`undefined`：显示 `-`。
- 未知来源：显示原始值。
- 不要因为未知来源导致列表或详情报错。

建议实现：

```ts
const PREORDER_SOURCE_LABEL_MAP: Record<string, string> = {
  home_preorder: '官网首页预约',
  expo_2026: '展会二维码',
  expo_sydney_2026: '悉尼展会二维码',
  expo_booth_qr_2026: '展位二维码',
  expo_brochure_2026: '展会手册二维码'
}

export function getPreorderSourceLabel(source?: string | null) {
  if (!source) return '-'
  return PREORDER_SOURCE_LABEL_MAP[source] || source
}
```

---

## UI 要求

### 列表页

当前截图中列表“来源”列直接显示：

```text
home_preorder
```

应改为：

```text
官网首页预约
```

如果后续扫码来源为：

```text
expo_2026
```

应显示：

```text
展会二维码
```

### 详情页

当前详情抽屉中“来源”字段直接显示：

```text
home_preorder
```

应改为：

```text
官网首页预约
```

如果需要保留原始值用于排查，可以在 tooltip 或括号中展示，但默认不强制：

```text
官网首页预约
```

### 筛选区

来源筛选控件应展示中文选项：

- 全部来源
- 官网首页预约
- 展会二维码
- 悉尼展会二维码
- 展位二维码
- 展会手册二维码

实际请求仍传原始值：

```http
GET /preorder-discounts/admin/leads?source=home_preorder
```

---

## 实施步骤

1. 在预约优惠码页面模块中新增 `source` 映射常量和 helper。
2. 列表“来源”列使用 `getPreorderSourceLabel(row.source)`。
3. 详情抽屉“来源”字段使用同一个 helper。
4. 来源筛选下拉选项改为中文 label、原始 value。
5. 未知来源测试显示原始值。
6. 空来源测试显示 `-`。

---

## 验收标准

- [ ] 列表页 `home_preorder` 显示为 `官网首页预约`。
- [ ] 详情页 `home_preorder` 显示为 `官网首页预约`。
- [ ] 来源筛选选项显示中文文案。
- [ ] 来源筛选请求仍传原始 `source` 值。
- [ ] `expo_2026` 可显示为 `展会二维码`。
- [ ] 空来源显示 `-`。
- [ ] 未知来源显示原始值，不报错。

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 前端只改列表没改详情 | 列表和详情必须共用同一个 helper |
| 筛选传了中文文案 | 下拉 label 用中文，value 必须保持原始值 |
| 后续新增来源无映射 | 未知来源兜底显示原始值 |

---

**相关文档:**

- [预售预约优惠码 API](../../../02-api/preorder-discounts.md)
- [ADMIN-FE-011 后台预约优惠码名单与详情页](./ADMIN-FE-011-preorder-discount-leads-page.md)
