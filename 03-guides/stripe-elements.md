# Stripe Elements 前端集成指南

> **适用**: Nuxt 商城前端
> **后端版本**: v1.13.0

## 快速开始

### 1. 安装依赖

```bash
npm install @stripe/stripe-js
```

### 2. 初始化 Stripe

```javascript
// composables/useStripe.ts
import { loadStripe } from '@stripe/stripe-js'

const stripe = loadStripe('pk_test_xxxxx')
export const useStripe = () => ({ stripe })
```

### 3. 创建支付

```javascript
// 1. 获取 client secret
const { clientSecret } = await $fetch('/api/v2/payments/stripe/create-intent', {
  method: 'POST',
  body: { amount: 99.99, currency: 'USD', orderId: 'ord-123' }
})

// 2. 使用 Stripe Elements
const { error } = await stripe.confirmCardPayment(clientSecret, {
  payment_method: {
    card: cardElement,
    billing_details: { name: 'Customer Name' }
  }
})
```

## 完整示例

参见后端 API 文档: [api/payments.md](../api/payments.md)
