# Tech-Spec: 移动端导航栏重构

**任务ID:** SHOP-FE-010
**创建时间:** 2026-03-03
**状态:** 准备开发
**角色:** 独立站前端工程师
**项目:** nuxt-moxton
**优先级:** P1
**技术栈:** Vue 3 + Nuxt 3 + TypeScript + Pinia

---

## 执行上下文（强约束）

- **Task File = 唯一执行输入源**：派遣消息可能是短文本，必须以本任务文件为准，不得依赖派遣消息补充细节。
- **工作目录**：`E:\nuxt-moxton`
- **必读文档**：
  - `E:\nuxt-moxton\CLAUDE.md`
  - `E:\nuxt-moxton\AGENTS.md`
- **开始后 60 秒内**：必须 `report_route(status="in_progress")`
- **执行中每 90~120 秒**：发送一次 `in_progress` 心跳
- **遇阻塞 2 分钟内**：`report_route(status="blocked", body="blocker_type=...;question=...;attempted=...;next_action_needed=...")`
- **完成后必须**：`report_route(status="success|fail|blocked", body=变更文件+命令+测试结果)`

---

## 概述

### 问题陈述

当前移动端导航栏存在以下问题：
1. 移动端顶部没有显示用户头像，与桌面端不一致
2. "账户中心"和"退出登录"直接暴露在汉堡菜单中，不够简洁
3. 搜索图标占用头部空间

### 解决方案

1. 在移动端导航栏右侧添加头像显示，点击展开下拉菜单（账户中心、退出登录）
2. 移除汉堡菜单中的"账户中心"和"退出登录"选项
3. 将搜索功能改为悬浮按钮形式，默认位置左下角，支持拖拽移动
4. 下拉菜单样式与桌面端完全一致（圆角、阴影、动画效果）

### 范围 (包含/排除)

**包含:**
- Navigation.vue 移动端布局修改
- 新建 FloatingSearchButton.vue 组件（参考 BackToTop.vue 实现）
- 头像下拉菜单的交互和样式
- 搜索悬浮按钮的拖拽功能

**不包含:**
- 桌面端导航栏的修改
- 搜索功能的业务逻辑修改
- 用户认证相关功能

---

## 开发上下文

### 现有实现

**Navigation.vue (`components/layout/Navigation.vue`)**
- 第186-217行：桌面端已实现头像和下拉菜单逻辑
- 第252-257行：移动端搜索图标
- 第296-320行：移动端汉堡菜单中的账户中心/退出登录链接

**BackToTop.vue (`components/common/BackToTop.vue`)**
- 已实现可拖拽定位的悬浮按钮模式
- 使用 `position: fixed`、`z-index: 1000`
- 有完整的移动端适配样式，可作为参考

**SearchModal.vue (`components/common/SearchModal.vue`)**
- 通过 `isSearchOpen` 控制显示
- 已实现完整的搜索模态框

### 依赖项

- UnoCSS 原子化样式
- VueUse Motion 动画库
- 现有的 auth store（获取用户信息）

---

## 技术方案

### 架构设计

```
Navigation.vue (修改)
├── 桌面端：保持现有逻辑不变
└── 移动端：<md breakpoint
    ├── 左侧：Logo
    ├── 中间：（空出或保持原样）
    └── 右侧：购物车 + 语言切换 + 头像（新）+ 汉堡菜单
        └── 头像点击 → Dropdown（账户中心/退出登录）

FloatingSearchButton.vue (新建)
├── 固定在左下角（默认）
├── 支持拖拽改变位置
├── 点击打开 SearchModal
└── 样式参考 BackToTop.vue
```

### 实施步骤

1. **读取现有代码**
   - 仔细阅读 Navigation.vue 的桌面端头像实现（186-217行）
   - 阅读 BackToTop.vue 了解悬浮按钮实现模式
   - 确认 SearchModal 的调用方式

2. **修改 Navigation.vue**
   - 在移动端右侧区域添加头像显示（复用桌面端的头像逻辑）
   - 复制桌面端的 Dropdown 实现到移动端（或使用同一套逻辑）
   - 从汉堡菜单中移除"账户中心"和"退出登录"链接
   - 确保下拉菜单样式与桌面端完全一致（圆角、阴影、动画）

3. **新建 FloatingSearchButton.vue**
   - 参考 BackToTop.vue 的实现模式
   - 固定在左下角（bottom: 20px, left: 20px）
   - 实现拖拽功能（touchstart/touchmove/touchend 或 mousedown/mousemove/mouseup）
   - 点击时触发搜索模态框打开
   - 添加搜索图标（heroicons:magnifying-glass）
   - 确保 z-index 足够高（如 1000）

4. **集成测试**
   - 验证移动端头像显示正常
   - 验证点击头像展开下拉菜单
   - 验证汉堡菜单中不再显示账户中心/退出登录
   - 验证搜索悬浮按钮可以拖拽
   - 验证点击搜索按钮打开搜索模态框

---

## 验收标准

- [ ] 移动端导航栏右侧显示用户头像（已登录状态下）
- [ ] 点击头像展开下拉菜单，包含"账户中心"和"退出登录"
- [ ] 下拉菜单样式与桌面端完全一致（圆角、阴影、动画效果）
- [ ] 汉堡菜单中不再显示"账户中心"和"退出登录"
- [ ] 新建 FloatingSearchButton 组件，默认固定在左下角
- [ ] 搜索悬浮按钮支持拖拽移动位置
- [ ] 点击搜索悬浮按钮能正常打开搜索模态框
- [ ] 未登录状态下不显示头像，保持原有逻辑

## QA 反馈 - 需修复问题

**QA 状态**: FAIL (2026-03-03)

### 必须修复的问题

1. **悬浮搜索按钮位置错误**
   - 当前：CSS `right:1.5rem; bottom:6rem`（右下角偏上）
   - 要求：`left: 20px; bottom: 20px`（左下角）
   - 修复文件：`components/common/FloatingSearchButton.vue`

2. **下拉菜单样式与桌面端不一致**
   - 移动端使用：`rounded-xl shadow-xl border`
   - 桌面端使用：`rounded-lg shadow-lg`
   - 要求：移动端与桌面端样式完全一致
   - 修复文件：`components/layout/Navigation.vue`

3. **故障路径错误信息本地化**
   - 问题：登录失败时暴露后端英文错误 "Invalid credentials"
   - 要求：显示中文错误信息或通用提示

### 证据路径
- QA 报告：`05-verification/SHOP-FE-010/`
- 截图对比：UI 样式差异已截图留存

---

## QA 反馈与修复要求（2026-03-03）

### 发现的问题

1. **悬浮搜索按钮位置错误** ❌
   - 当前：CSS 为 `right:1.5rem; bottom:6rem`（右下角）
   - 要求：固定在左下角，CSS 应为 `left: 20px; bottom: 20px`
   - 修复文件：`components/common/FloatingSearchButton.vue`

2. **下拉菜单样式与桌面端不一致** ❌
   - 移动端使用：`rounded-xl shadow-xl border`
   - 桌面端使用：`rounded-lg shadow-lg`
   - 要求：两者样式必须完全一致
   - 修复文件：`components/layout/Navigation.vue`

3. **故障路径暴露后端英文错误** ❌
   - 登录 401 错误直接显示 "Invalid credentials"
   - 应显示中文用户友好提示

### 必须修复项

- [ ] FloatingSearchButton 默认位置改为左下角（left: 20px; bottom: 20px）
- [ ] 移动端下拉菜单样式与桌面端统一（使用相同的 rounded-lg shadow-lg）
- [ ] 登录/登出 401 错误处理，显示中文提示而非暴露后端英文

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 拖拽功能可能与页面滚动冲突 | 使用 touch-action: none 禁用元素上的默认触摸行为 |
| 悬浮按钮可能遮挡内容 | 确保默认位置在角落，且用户可以拖拽移开 |
| 下拉菜单在移动端可能被截断 | 检查 z-index 和 overflow 设置 |

---

**相关文档:**
- [API 文档](../../02-api/)
- [项目状态](../../04-projects/nuxt-moxton.md)
