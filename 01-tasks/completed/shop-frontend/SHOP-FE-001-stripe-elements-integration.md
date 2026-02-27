# Tech-Spec: 独立站结账页 Stripe Elements 集成

**创建时间:** 2026-02-09
**状�?** 准备开�?
**角色:** 独立站前端工程师
**项目:** nuxt-moxton
**优先�?** P0
**技术栈:** Vue 3 + Nuxt 3 + TypeScript + Pinia + Stripe Elements

---

## 概述

### 问题陈述

当前结账页面的支付组�?(`CheckoutPayment.vue`) 只是占位实现，没有集成实际的 Stripe Elements 支付功能。用户无法完成在线支付�?

### 解决方案

集成 Stripe Elements SDK，实现完整的信用卡支付流程，包括�?
- 创建支付意图
- 渲染卡片输入表单
- 处理支付确认
- 错误处理和状态管�?

### 范围 (包含/排除)

**包含:**
- 安装 Stripe SDK (`@stripe/stripe-js`)
- 重写 `CheckoutPayment.vue` 组件
- 集成 Stripe Elements 卡片表单
- 实现支付流程（创建意�?�?确认支付 �?跳转�?
- 访客支付支持（X-Guest-ID�?
- 错误处理和用户提�?

**不包�?**
- PayPal 支付方式
- 银行转账方式
- 支付成功页面（跳转到首页�?
- 后端 Stripe 配置

---

## 开发上下文

### 现有实现

| 文件 | 状�?| 说明 |
|------|------|------|
| `components/checkout/CheckoutPayment.vue` | �?占位 | 需要完全重�?|
| `composables/api/payments.ts` | �?完整 | API 封装已存�?|
| `utils/guestId.ts` | �?完整 | 浏览器指�?+ localStorage |
| `composables/api/client.ts` | �?完整 | 自动添加 X-Guest-ID |
| `stores/checkout.ts` | �?完整 | �?orderId 字段 |
| `package.json` | �?缺少 | 需要添�?Stripe SDK |

### 依赖�?

- **后端 API**: 已完�?(BACKEND-003)
- **支付 API 端点**: `POST /payments/stripe/create-intent`
- **访客支付**: 后端已支�?X-Guest-ID 校验

### Stripe 测试环境

```
公钥 (前端): pk_test_51SXYweDt2ZDLw0kr7t6Hp4h3VClSbDxFYRzl8RSpoAWybVAbfeQxA1NCz02KK6ZpGScHm8mCev86ABK4weFRYXdB00qJwISXxA
私钥 (后端): STRIPE_SECRET_KEY_PLACEHOLDER
```

---

## 技术方�?

### 架构设计

```
CheckoutPayment.vue
    �?
    ├─�?onMounted()
    �?  └─�?获取 checkoutStore.orderId
    �?  └─�?调用 paymentsApi.createPaymentIntent({ orderId })
    �?  └─�?获取 clientSecret + publishableKey
    �?  └─�?初始�?Stripe: loadStripe(publishableKey)
    �?  └─�?创建 Elements: stripe.elements({ clientSecret })
    �?  └─�?渲染卡片组件
    �?
    └─�?handlePayment()
        └─�?stripe.confirmPayment({ elements, confirmParams, redirect: 'if_required' })
        └─�?成功 �?跳转到首�?
        └─�?失败 �?显示错误信息
```

### 数据流程

```typescript
// Step 1: 创建支付意图
const { data } = await paymentsApi.createPaymentIntent({ orderId })
// �?{ clientSecret, publishableKey, paymentIntentId, ... }

// Step 2: 初始�?Stripe
const stripe = await loadStripe(data.publishableKey)
const elements = stripe.elements({ clientSecret: data.clientSecret })

// Step 3: 渲染卡片
const cardElement = elements.create('card', { style: {...} })
cardElement.mount('#card-element')

// Step 4: 确认支付
const { error, paymentIntent } = await stripe.confirmPayment({
  elements,
  confirmParams: {
    return_url: window.location.origin + '/checkout/confirm'
  },
  redirect: 'if_required'
})
```

### API 调用

**创建支付意图**:
```typescript
// POST /payments/stripe/create-intent
// 请求头自动包�?X-Guest-ID (�?apiClient 处理)
const result = await paymentsApi.createPaymentIntent({
  orderId: checkoutStore.orderId
})
```

---

## 实施步骤

### Step 1: 安装 Stripe SDK

```bash
cd E:\nuxt-moxton
pnpm add @stripe/stripe-js
```

### Step 2: 配置环境变量

�?`nuxt.config.ts` �?`.env` 中添加：

```typescript
// runtimeConfig
public: {
  stripePublishableKey: 'pk_test_51SXYweDt2ZDLw0kr7t6Hp4h3VClSbDxFYRzl8RSpoAWybVAbfeQxA1NCz02KK6ZpGScHm8mCev86ABK4weFRYXdB00qJwISXxA'
}
```

### Step 3: 重写 CheckoutPayment.vue

**组件结构**:
```vue
<script setup lang="ts">
import { loadStripe } from '@stripe/stripe-js'
import { paymentsApi } from '~/composables/api/payments'
import { useCheckoutStore } from '~/stores/checkout'

const checkoutStore = useCheckoutStore()
const stripe = ref(null)
const elements = ref(null)
const cardElement = ref(null)
const isProcessing = ref(false)
const errorMessage = ref('')

// 1. 创建支付意图并初始化 Stripe
onMounted(async () => {
  const orderId = checkoutStore.orderId
  if (!orderId) {
    errorMessage.value = '订单 ID 不存�?
    return
  }

  // 创建支付意图
  const result = await paymentsApi.createPaymentIntent({ orderId })
  if (!result.success || !result.data) {
    errorMessage.value = result.message || '创建支付意图失败'
    return
  }

  // 初始�?Stripe
  stripe.value = await loadStripe(result.data.publishableKey)
  elements.value = stripe.value.elements({
    clientSecret: result.data.clientSecret
  })

  // 创建卡片组件
  cardElement.value = elements.value.create('card', {
    style: {
      base: {
        fontSize: '16px',
        color: '#424770',
        '::placeholder': { color: '#aab7c4' }
      },
      invalid: { color: '#9e2146' }
    }
  })

  // 挂载�?DOM
  nextTick(() => {
    cardElement.value.mount('#card-element')
  })
})

// 2. 处理支付
const handlePayment = async () => {
  isProcessing.value = true
  errorMessage.value = ''

  const { error, paymentIntent } = await stripe.value.confirmPayment({
    elements: elements.value,
    confirmParams: {
      return_url: window.location.origin + '/'
    },
    redirect: 'if_required'
  })

  if (error) {
    errorMessage.value = error.message
    isProcessing.value = false
  } else if (paymentIntent?.status === 'succeeded') {
    // 支付成功，跳转到首页
    await navigateTo('/')
  }
}
</script>

<template>
  <div class="checkout-payment">
    <!-- 错误提示 -->
    <div v-if="errorMessage" class="error-message">
      {{ errorMessage }}
    </div>

    <!-- Stripe 卡片输入 -->
    <div id="card-element" class="card-element"></div>

    <!-- 支付按钮 -->
    <button
      @click="handlePayment"
      :disabled="isProcessing"
      class="pay-button"
    >
      {{ isProcessing ? '处理�?..' : '立即支付' }}
    </button>
  </div>
</template>
```

### Step 4: 更新页面布局

�?`pages/checkout/index.vue` 中：

1. 移除 `StripePaymentPlaceholder` 组件引用
2. 确保两栏布局正确（左侧支付表单，右侧订单摘要�?

### Step 5: 添加错误处理

```typescript
// 错误处理场景
- 支付意图创建失败 �?显示错误，阻止继�?
- Stripe 初始化失�?�?显示错误，阻止继�?
- 卡片验证失败 �?显示 Stripe 返回的错�?
- 支付被拒�?�?显示错误，允许重�?
- 网络错误 �?显示错误，提供重试按�?
```

---

## 验收标准

### 功能测试

- [ ] **A1. Stripe SDK 安装成功** - package.json 包含 @stripe/stripe-js
- [ ] **A2. 创建支付意图** - POST /payments/stripe/create-intent 返回 clientSecret
- [ ] **A3. Stripe Elements 渲染** - 卡片输入框正常显�?
- [ ] **A4. 支付成功** - 使用测试�?4242 完成支付，跳转到首页
- [ ] **A5. 支付失败** - 使用测试�?4000 显示错误信息
- [ ] **A6. 访客支付** - 未登录用户可以完成支付（X-Guest-ID 自动发送）
- [ ] **A7. 订单状态更�?* - 支付后订单状态变�?PAID �?CONFIRMED

### Stripe 测试�?

| 卡号 | 结果 | 用�?|
|------|------|------|
| `4242 4242 4242 4242` | 成功 | 正常支付流程 |
| `4000 0000 0000 0002` | 失败 | 卡被拒绝 |
| `4000 0025 0000 3155` | 3DS | 需�?3D Secure 验证 |

### UI/UX 验证

- [ ] **B1. 响应式布局** - 移动端和桌面端都正常显示
- [ ] **B2. 加载状�?* - 处理中显示加载动�?
- [ ] **B3. 错误提示** - 错误信息清晰可见
- [ ] **B4. 按钮状�?* - 支付中禁用按�?

---

## 风险和注意事�?

| 风险 | 缓解措施 |
|------|----------|
| Stripe SDK 版本兼容�?| 使用最新稳定版 `@stripe/stripe-js` |
| 订单 ID �?null | �?Step 1 确保订单创建成功，验�?orderId 存在 |
| 支付意图创建失败 | 显示错误信息，阻止进入支付步�?|
| X-Guest-ID 未发�?| apiClient 自动处理，已验证可用 |
| Webhook 未配�?| 后端已配置，支付成功自动更新订单状�?|
| 3D Secure 验证 | Stripe SDK 自动处理重定�?|

### 重要提醒

1. **X-Guest-ID** - apiClient 自动添加，无需手动处理
2. **支付成功后跳�?* - 当前设计跳转到首页，可后续优化为订单详情�?
3. **测试密钥** - 已提供测试公钥，生产环境需更换
4. **错误处理** - Stripe 会返回详细的错误信息，直接显示给用户

---

## 开发注意事�?

### 现有代码依赖

```typescript
// 已存在的 API 方法
import { paymentsApi } from '~/composables/api/payments'

// 已存在的 Store
const checkoutStore = useCheckoutStore()
const orderId = checkoutStore.orderId  // Step 1 创建订单后保�?

// 自动添加的请求头（无需手动处理�?
// X-Guest-ID: �?apiClient 自动�?localStorage 读取并添�?
```

### 支付流程时序

```
用户 �?Step 1 (个人信息) �?创建订单 �?checkoutStore.orderId = "xxx"
     �?Step 2 (配�? �?选择配送方�?
     �?Step 3 (支付) �?CheckoutPayment.vue 组件
       �?创建支付意图 (POST /payments/stripe/create-intent)
       �?初始�?Stripe Elements
       �?用户输入卡号
       �?点击 "Pay Now"
       �?stripe.confirmPayment()
       �?成功 �?跳转到首�?
       �?失败 �?显示错误，允许重�?
```

---

**相关文档:**
- [Stripe Elements 文档](https://docs.stripe.com/js/elements)
- [Stripe Payment Intents API](https://docs.stripe.com/api/payment_intents)
- [后端 API 文档](../../02-api/payments.md)
- [项目状态](../../04-projects/nuxt-moxton.md)

