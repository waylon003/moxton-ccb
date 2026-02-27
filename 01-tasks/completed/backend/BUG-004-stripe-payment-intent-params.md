# Bug Report: Stripe Payment Intent 参数冲突

**创建时间**: 2026-02-09
**状态**: 待修复
**角色**: 后端工程师
**项目**: moxton-lotapi
**优先级**: P1
**来源**: BACKEND-003 QA 测试发现

---

## 问题描述

### 错误信息
```
You cannot enable `automatic_payment_methods` and specify `payment_method_types`.
```

### 问题位置
**文件**: `E:\moxton-lotapi\src\services\StripePaymentService.ts`
**行号**: 72-78

### 根本原因
Stripe API 不允许同时启用以下两个参数：
1. `automatic_payment_methods.enabled = true`
2. `payment_method_types: ['card']`

这两个参数是互斥的，只能使用其中一个。

---

## 修复方案

### 方案 1：移除 payment_method_types（推荐）

保持 `automatic_payment_methods.enabled = true`，移除 `payment_method_types` 配置。

**修改前**:
```typescript
const paymentIntent = await stripe.paymentIntents.create({
  amount: orderAmountInCents,
  currency: order.currency.toLowerCase(),
  automatic_payment_methods: {
    enabled: true,
  },
  payment_method_types: ['card'],  // ❌ 删除这行
  // ... 其他配置
});
```

**修改后**:
```typescript
const paymentIntent = await stripe.paymentIntents.create({
  amount: orderAmountInCents,
  currency: order.currency.toLowerCase(),
  automatic_payment_methods: {
    enabled: true,
  },
  // payment_method_types 已移除
  // ... 其他配置
});
```

### 方案 2：使用 payment_method_types（不推荐）

如果需要显式指定支付方式，可以禁用 automatic_payment_methods：

```typescript
const paymentIntent = await stripe.paymentIntents.create({
  amount: orderAmountInCents,
  currency: order.currency.toLowerCase(),
  payment_method_types: ['card'],
  // ... 其他配置
});
```

**注意**: 方案 2 会失去 Stripe 自动选择最佳支付方式的能力。

---

## 验证步骤

1. 修改代码后重启服务
2. 使用测试订单创建支付意图
3. 确认返回 200 状态码和 `clientSecret`
4. 使用测试卡 `4242 4242 4242 4242` 完成支付流程

---

## 影响范围

- **影响接口**: `POST /payments/stripe/create-intent`
- **影响功能**: Stripe 支付创建
- **阻塞状态**: 当前无法完成 Stripe 支付流程

---

## 相关文档

- [Stripe Payment Intents API](https://docs.stripe.com/api/payment_intents/create)
- [Automatic Payment Methods](https://docs.stripe.com/payments/payment-methods/overview)

---

## 相关任务

- **QA 报告**: BACKEND-003 测试发现
- **原始任务**: BACKEND-003 订单支付修复
