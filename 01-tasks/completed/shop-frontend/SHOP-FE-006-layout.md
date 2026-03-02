# Tech-Spec: 修复地址自动补全组件布局

**任务ID:** SHOP-FE-006
**父任务:** SHOP-FE-005
**创建时间:** 2026-03-02
**状态:** 准备开发
**角色:** 独立站前端工程师
**项目:** nuxt-moxton (E:\nuxt-moxton)
**优先级:** P1
**技术栈:** Vue 3 + Nuxt 3 + TypeScript + Reka UI + UnoCSS

---

## 执行上下文（强约束）

- **Task File = 唯一执行输入源**：派遣消息可能是短文本，必须以本任务文件为准，不得依赖派遣消息补充细节。
- **角色定义**：`E:\moxton-ccb\.claude\agents\shop-frontend.md`
- **协议文件**：`E:\moxton-ccb\.claude\agents\protocol.md`
- **工作目录**：`E:\nuxt-moxton`
- **开始后 60 秒内**：必须 `report_route(status="in_progress")`
- **执行中每 90~120 秒**：发送一次 `in_progress` 心跳
- **遇阻塞 2 分钟内**：`report_route(status="blocked", body="blocker_type=...;question=...;attempted=...;next_action_needed=...")`
- **完成后必须**：`report_route(status="success|fail|blocked", body=变更文件+命令+测试结果)`

---

## 概述

### 问题陈述

当前 `AddressAutocompleteInput` 组件被直接绑定到 `addressLine1` 字段，导致自动搜索地址和详细地址输入框混在一起。根据用户提供的图片，正确的布局应该是：

1. **上面**: 独立的"搜索地址"输入框（仅用于触发自动补全API）
2. **下面**: "详细地址"输入框（addressLine1，选择自动填充后仍可手动修改）

此外，X 按钮的垂直居中位置需要修复。

### 解决方案

修改 `components/AddressAutocompleteInput.vue` 组件，添加独立的搜索输入框，与详细地址(addressLine1)字段分离。用户选择地址建议后，自动填充下方各表单字段（包括 addressLine1）。

### 范围

**包含:**
- 修改 `AddressAutocompleteInput.vue` 组件
- 添加独立的搜索地址输入框
- 修复 X 按钮垂直居中
- 更新 `pages/account/addresses.vue` 中的使用方式

**不包含:**
- 后端 API 修改
- 其他页面的修改

---

## 当前问题分析

### 当前实现（问题）

在 `pages/account/addresses.vue` 第353-361行：
```vue
<AddressAutocompleteInput
  v-model="form.addressLine1"
  :label="t('account.addresses.fields.addressLine1')"
  :error="errors.addressLine1"
  required
  @select="onSelectSuggestion"
/>
```

问题：`AddressAutocompleteInput` 直接绑定到 `addressLine1`，导致搜索和输入混在一起。

### 目标实现

根据用户提供的图片，正确布局：

```
┌─────────────────────────────────────────────┐
│  Address                                    │
│  ┌───────────────────────────────────────┐  │
│  │ Lalaguli Drive, Toormina NSW, Australia│  │
│  └───────────────────────────────────────┘  │
│  搜索您的地址，系统将自动填充详细信息        │
│                                             │
│  详细地址 *                                 │
│  ┌───────────────────────────────────────┐  │
│  │ Lalaguli Drive                        │  │
│  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

---

## 技术方案

### Step 1: 修改 AddressAutocompleteInput 组件

**文件**: `components/AddressAutocompleteInput.vue`

**修改内容**:

1. **添加独立的搜索输入框**:
   - 添加 `searchQuery` 响应式变量用于存储搜索输入
   - 搜索输入框显示在顶部，用于触发自动补全
   - 选择地址后，搜索框显示选中的完整地址描述

2. **X 按钮垂直居中修复**:
   - 检查 `MaterialInput` 组件的高度计算
   - 调整 X 按钮的定位方式

3. **Props 调整**:
```typescript
interface Props {
  // 搜索框的值（完整地址描述）
  searchValue?: string
  // 详细地址值（addressLine1）
  modelValue: string
  label?: string
  searchLabel?: string  // 搜索框标签，默认 "Address"
  placeholder?: string
  searchPlaceholder?: string  // 搜索框占位符
  disabled?: boolean
  country?: string
  error?: string | boolean
  required?: boolean
  id?: string
}
```

4. **UI 结构修改**:
```vue
<template>
  <div class="address-autocomplete-wrapper">
    <!-- 搜索地址输入框 -->
    <div class="relative w-full mb-2">
      <MaterialInput
        v-model="searchQuery"
        :label="searchLabel || 'Address'"
        :placeholder="searchPlaceholder || 'Enter address...'"
        :disabled="disabled"
        :icon="loading ? 'heroicons:arrow-path' : 'heroicons:map-pin'"
        :icon-class="loading ? 'animate-spin' : ''"
        @keydown="handleKeyDown"
        @blur="handleBlur"
        @focus="handleFocus"
      >
        <template #append>
          <button
            v-if="searchQuery && !disabled"
            type="button"
            class="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600 transition-colors p-1 flex items-center justify-center"
            @click="clearInput"
          >
            <Icon name="heroicons:x-mark" class="w-4 h-4" />
          </button>
        </template>
      </MaterialInput>

      <!-- 建议下拉列表 -->
      <div
        v-if="isOpen && suggestions.length > 0"
        class="absolute z-50 w-full mt-1 bg-white border border-gray-200 rounded-lg shadow-xl max-h-60 overflow-y-auto"
      >
        <!-- suggestion items -->
      </div>
    </div>

    <!-- 提示文字 -->
    <p class="text-xs text-gray-500 mb-4">搜索您的地址，系统将自动填充详细信息</p>

    <!-- 详细地址输入框（可由父组件通过 v-model 管理） -->
    <!-- 这个组件只负责地址选择和填充事件，详细地址输入框在父组件中 -->
  </div>
</template>
```

**验收**:
- 搜索输入框和详细地址输入框分离
- X 按钮在输入框中垂直居中

---

### Step 2: 更新 addresses.vue 页面

**文件**: `pages/account/addresses.vue`

**修改内容**:

修改表单布局，将 `AddressAutocompleteInput` 作为独立的搜索组件：

```vue
<!-- 搜索地址（独立组件） -->
<div class="w-full">
  <AddressAutocompleteInput
    :search-value="searchAddress"
    :label="t('account.addresses.fields.searchAddress')"
    search-placeholder="Search your address..."
    @select="onSelectSuggestion"
    @clear="onClearAddress"
  />
</div>

<!-- 详细地址（普通输入框） -->
<div class="grid grid-cols-1 md:grid-cols-2 gap-6">
  <MaterialInput v-model="form.addressLine1" :label="t('account.addresses.fields.addressLine1')" :error="errors.addressLine1" required />
  <MaterialInput v-model="form.addressLine2" :label="t('account.addresses.fields.addressLine2')" :error="errors.addressLine2" />
</div>
```

添加 `searchAddress` 响应式变量：
```typescript
const searchAddress = ref('')

const onSelectSuggestion = (suggestion: AddressSuggestion) => {
  const addr = suggestion.structuredAddress
  if (addr) {
    searchAddress.value = suggestion.description  // 搜索框显示完整地址
    form.addressLine1 = addr.addressLine1 || ''
    form.addressLine2 = addr.addressLine2 || ''
    form.city = addr.city || ''
    form.state = addr.state || ''
    form.zipCode = addr.postalCode || ''
    form.country = addr.countryCode || ''
  }
}

const onClearAddress = () => {
  searchAddress.value = ''
}
```

**验收**:
- 搜索地址输入框位于详细地址上方
- 选择地址后自动填充下方各字段
- 用户可以手动修改自动填充的内容

---

### Step 3: 修复 X 按钮垂直居中

**文件**: `components/AddressAutocompleteInput.vue`

X 按钮当前使用 `top-1/2 -translate-y-1/2`，但需要确保在 `MaterialInput` 的上下文中正确居中。

检查并修复：
```vue
<template #append>
  <button
    v-if="searchQuery && !disabled"
    type="button"
    class="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600 transition-colors p-1 flex items-center justify-center h-6 w-6"
    @click="clearInput"
  >
    <Icon name="heroicons:x-mark" class="w-4 h-4" />
  </button>
</template>
```

如果仍不居中，考虑使用 flex 布局或调整计算方式。

**验收**:
- X 按钮在输入框中垂直居中显示

---

## 验收标准

| # | 标准 | 验证方式 |
|---|------|---------|
| 1 | 搜索地址输入框和详细地址输入框分离 | 页面视觉检查 |
| 2 | 选择地址建议后自动填充各字段 | 手工测试 |
| 3 | X 按钮垂直居中 | 页面视觉检查 |
| 4 | 无 console 错误或警告 | 浏览器 Console |
| 5 | 移动端显示正常 | 响应式测试 |

---

## 相关文件

- `components/AddressAutocompleteInput.vue`
- `pages/account/addresses.vue`
- `components/ui/MaterialInput.vue`
