# Tech-Spec: 地址自动补全 API 集成

**任务ID:** SHOP-FE-005
**创建时间:** 2026-03-02
**状态:** 准备开发
**角色:** 独立站前端工程师
**项目:** nuxt-moxton (E:\nuxt-moxton)
**优先级:** P1
**技术栈:** Vue 3 + Nuxt 3 + TypeScript + Pinia + Reka UI + UnoCSS

---

## 概述

### 问题陈述

需要在两个地方集成地址自动补全功能：
1. **地址管理页面** (`pages/account/addresses.vue`) - 新增/编辑地址表单
2. **结账流程地址表单** - 如果存在单独的结账地址输入

后端地址补全服务 `GET /address/autocomplete` 已部署可用，支持智能地址建议，返回结构化地址数据。

### 解决方案

创建一个可复用的 `AddressAutocomplete` composable 和/或组件，在地址表单中提供实时地址建议下拉，用户选择后自动填充表单字段。

### 范围

**包含:**
- 创建 `useAddressAutocomplete` composable
- 在地址管理页面集成地址补全
- 在结账流程地址表单集成地址补全（如适用）
- 使用防抖减少 API 调用频率

**不包含:**
- 修改后端 API
- 其他页面的修改
- 地图可视化组件

---

## 开发上下文

### 后端 API 端点

**GET** `/address/autocomplete`（已部署可用）

**查询参数**:
- `input` (必需): 用户输入的地址文本，最少 2 个字符
- `country` (可选): 国家代码，默认 'au' (澳大利亚)
- `language` (可选): 语言代码，默认 'en'

**响应格式**:
```json
{
  "code": 200,
  "message": "Success",
  "data": {
    "suggestions": [
      {
        "placeId": "ChIJ3c5SiJN2EmsRBfyfZgdnSyI",
        "description": "Sydney Opera House, Bennelong Point, Sydney NSW, Australia",
        "structuredAddress": {
          "addressLine1": "Bennelong Point",
          "addressLine2": "Sydney Opera House",
          "city": "Sydney",
          "state": "NSW",
          "postalCode": "2000",
          "country": "Australia",
          "countryCode": "AU",
          "fullAddress": "Bennelong Point, Sydney Opera House, Sydney NSW 2000, Australia",
          "district": ""
        }
      }
    ]
  },
  "success": true
}
```

### 需要集成的页面

| 页面 | 路径 | 说明 |
|------|------|------|
| 地址管理 | `pages/account/addresses.vue` | 新增/编辑地址表单 |
| 结账流程 | `pages/checkout/address.vue` 或类似 | 下单时填写地址（如存在） |

### 可用的 UI 组件

| 组件 | 路径 | 用途 |
|------|------|------|
| `MaterialInput` | `components/ui/MaterialInput.vue` | 地址输入框（带补全下拉） |
| `GradientButton` | `components/ui/GradientButton.vue` | 按钮 |

### UnoCSS 主题色

```
primary: #FF6B35  success: #2C8A4B  error: #D93A2F  warning: #C97A00  info: #3667D6
```

---

## 技术方案

### Step 1: 创建 useAddressAutocomplete Composable

**目标**: 封装地址补全逻辑，供多个页面复用

**文件**: `composables/useAddressAutocomplete.ts`

**功能需求**:
1. 接收用户输入，防抖 300ms 后调用 API
2. 管理建议列表状态
3. 处理加载状态和错误
4. 提供选择建议后的回调

**接口设计**:
```typescript
interface UseAddressAutocompleteOptions {
  country?: string        // 默认 'au'
  language?: string       // 默认 'en'
  minLength?: number      // 最小触发长度，默认 2
  debounceMs?: number     // 防抖毫秒，默认 300
}

interface StructuredAddress {
  addressLine1: string
  addressLine2: string
  city: string
  state: string
  postalCode: string
  country: string
  countryCode: string
  fullAddress: string
  district: string
}

interface AddressSuggestion {
  placeId: string
  description: string
  structuredAddress: StructuredAddress
}

export function useAddressAutocomplete(options?: UseAddressAutocompleteOptions) {
  const suggestions = ref<AddressSuggestion[]>([])
  const loading = ref(false)
  const error = ref<string | null>(null)

  const search = async (input: string) => {
    // 防抖处理
    // 调用 GET /address/autocomplete
    // 更新 suggestions
  }

  const clearSuggestions = () => {
    suggestions.value = []
  }

  return {
    suggestions,
    loading,
    error,
    search,
    clearSuggestions
  }
}
```

**验收**:
- composable 可被正常导入使用
- 输入超过 2 个字符后触发搜索
- 防抖正常工作（300ms）
- 返回的建议数据格式正确

---

### Step 2: 创建 AddressAutocompleteInput 组件（可选）

**目标**: 如果需要更复杂的 UI，可以封装成专用组件

**文件**: `components/AddressAutocompleteInput.vue`

**Props**:
```typescript
interface Props {
  modelValue: string           // 当前输入值
  label?: string               // 标签文本
  placeholder?: string         // 占位符
  country?: string             // 国家代码
  error?: string               // 错误信息
}
```

**Emits**:
- `update:modelValue` - 输入变化
- `select` - 用户选择建议，`payload: StructuredAddress`

**UI 结构**:
```vue
<template>
  <div class="relative">
    <MaterialInput
      v-model="inputValue"
      :label="label"
      :placeholder="placeholder"
      :error="error"
    />
    <!-- 建议下拉列表 -->
    <div v-if="suggestions.length > 0" class="absolute z-50 w-full bg-white border rounded shadow-lg">
      <div
        v-for="suggestion in suggestions"
        :key="suggestion.placeId"
        class="px-4 py-2 hover:bg-gray-100 cursor-pointer"
        @click="selectSuggestion(suggestion)"
      >
        {{ suggestion.description }}
      </div>
    </div>
  </div>
</template>
```

**验收**:
- 输入时显示下拉建议
- 点击建议后触发 select 事件并传递结构化地址
- 选择后清空建议列表

---

### Step 3: 在地址管理页面集成

**目标**: 在 `pages/account/addresses.vue` 的地址表单中集成地址补全

**修改内容**:
1. 导入 `useAddressAutocomplete` composable
2. 在地址输入框（通常是 addressLine1 或一个专门的"搜索地址"字段）集成补全功能
3. 用户选择建议后，自动填充以下字段：
   - `addressLine1` ← `structuredAddress.addressLine1`
   - `addressLine2` ← `structuredAddress.addressLine2`
   - `city` ← `structuredAddress.city`
   - `state` ← `structuredAddress.state`
   - `postalCode` ← `structuredAddress.postalCode`
   - `country` ← `structuredAddress.countryCode`

**代码示例**:
```vue
<script setup lang="ts">
const { suggestions, loading, search, clearSuggestions } = useAddressAutocomplete({
  country: 'au',
  language: 'en'
})

const form = reactive({
  name: '',
  phone: '',
  addressLine1: '',
  addressLine2: '',
  city: '',
  state: '',
  postalCode: '',
  country: 'AU',
  isDefault: false
})

// 监听地址行1输入，触发搜索
watch(() => form.addressLine1, (val) => {
  if (val.length >= 2) {
    search(val)
  } else {
    clearSuggestions()
  }
})

// 选择建议后填充表单
const onSelectSuggestion = (suggestion: AddressSuggestion) => {
  const addr = suggestion.structuredAddress
  form.addressLine1 = addr.addressLine1
  form.addressLine2 = addr.addressLine2 || ''
  form.city = addr.city
  form.state = addr.state
  form.postalCode = addr.postalCode
  form.country = addr.countryCode
  clearSuggestions()
}
</script>
```

**验收**:
- 在地址管理页面输入地址时显示建议下拉
- 选择建议后自动填充所有地址字段
- 用户可以手动修改自动填充的内容

---

### Step 4: 在结账流程集成（如适用）

**目标**: 如果结账流程有独立的地址表单，同样集成地址补全

**文件**: 查找结账相关的地址表单页面

**操作**: 与 Step 3 相同，在结账地址表单中集成 `useAddressAutocomplete`

**验收**:
- 结账时填写地址也能使用自动补全

---

### Step 5: 全量回归验证

**目标**: 确认地址补全功能在所有集成点正常工作

**验证清单**:
1. **地址管理页面**:
   - [ ] 输入地址时显示建议下拉
   - [ ] 选择建议后自动填充各字段
   - [ ] 可以手动修改填充的内容
   - [ ] 保存地址后数据正确

2. **API 调用验证**:
   - [ ] 输入时触发 `GET /address/autocomplete?input=...`
   - [ ] 防抖正常工作（不会每输入一个字符就请求）
   - [ ] 网络面板无 4xx/5xx 错误

3. **边界场景**:
   - [ ] 输入少于 2 个字符不触发请求
   - [ ] 无匹配结果时显示空状态或无下拉
   - [ ] 快速输入时无竞态问题

---

## 验收标准

| # | 标准 | 验证方式 |
|---|------|---------|
| 1 | 地址管理页面集成地址补全 | 手工测试 |
| 2 | 选择建议后自动填充表单字段 | 手工测试 |
| 3 | API 调用有防抖（300ms） | DevTools Network 观察 |
| 4 | 无 console 错误或警告 | 浏览器 Console |
| 5 | 移动端触摸交互正常 | 手机/模拟器测试 |

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 用户选择建议后仍需修改 | 自动填充后允许用户编辑 |
| API 延迟高影响体验 | 添加 loading 状态提示 |
| 下拉被其他元素遮挡 | 使用 `z-index` 确保层级正确 |
| 移动端下拉显示问题 | 测试多种屏幕尺寸 |

---

## 相关文档

- [Addresses API](../../02-api/addresses.md) - 包含完整的前端集成示例
- [项目状态](../../04-projects/nuxt-moxton.md)
- 历史任务: SHOP-FE-003 (个人中心 API 联调修复)
