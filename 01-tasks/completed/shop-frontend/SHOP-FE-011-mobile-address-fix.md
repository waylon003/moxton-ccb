# Tech-Spec: 移动端地址管理优化

**任务ID:** SHOP-FE-011
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

当前移动端地址管理页面存在以下问题：
1. "添加地址"按钮宽度占据剩余空间，导致左侧标题被迫分行显示
2. 地址编辑弹窗高度不固定，在移动端内容过多时体验不佳
3. 保存/取消按钮随表单内容滚动，不够便捷

### 解决方案

1. 给"添加地址"按钮设置固定宽度（如 w-auto 或具体 px 值），不再占据剩余空间
2. 弹窗固定高度为 80vh，内部表单区域可独立滚动
3. 将保存/取消按钮固定在弹窗底部，使用 flex 布局分离滚动区域和按钮区域

### 范围 (包含/排除)

**包含:**
- addresses.vue 列表页布局修复
- addresses.vue 弹窗结构和样式修复
- 移动端响应式适配

**不包含:**
- 地址表单的字段修改
- 后端 API 调用修改
- 桌面端弹窗样式的修改（保持兼容即可）

---

## 开发上下文

### 现有实现

**addresses.vue (`pages/account/addresses.vue`)**
- 第242-256行：收货地址标题栏，使用 `flex items-center justify-between`，但按钮没有固定宽度
- 第340-422行：地址编辑弹窗
- 第346行：`max-w-xl` 限制最大宽度，但没有固定高度
- 第356-399行：表单内容区域
- 第408-419行：保存/取消按钮在 form 标签内部

### 依赖项

- UnoCSS 原子化样式
- Reka UI Dialog 组件
- 现有的地址 API

---

## 技术方案

### 架构设计

```
addresses.vue (修改)
├── 问题3修复：标题栏布局
│   ├── "收货地址" 标题保持原样
│   └── "添加地址"按钮改为固定宽度（如 w-32 或 w-auto）
│
└── 问题4修复：弹窗结构
    ├── DialogContent: 固定高度 h-[80vh]
    ├── 内容区域: flex-col
    │   ├── 滚动区域: flex-1 overflow-y-auto (表单内容)
    │   └── 按钮区域: flex-none py-4 (保存/取消按钮)
    └── 按钮在同一行显示 (flex gap-4)
```

### 实施步骤

1. **读取现有代码**
   - 仔细阅读 addresses.vue 的标题栏和弹窗实现
   - 理解当前的 flex 布局和 Dialog 结构

2. **修复问题3 - 标题栏布局**
   - 定位到第242-256行的标题栏区域
   - 给 GradientButton 添加固定宽度类（如 `w-32` 或 `w-auto`）
   - 确保与左侧标题之间有合理间距（已有 gap-4）
   - 验证按钮不再占据剩余空间

3. **修复问题4 - 弹窗结构**
   - 定位到第340-422行的 Dialog 实现
   - 给 DialogContent 添加固定高度：`h-[80vh]`
   - 重构内部结构：
     ```vue
     <DialogContent class="... h-[80vh] flex flex-col">
       <!-- 标题区域 -->
       <DialogHeader>...</DialogHeader>

       <!-- 滚动表单区域 -->
       <div class="flex-1 overflow-y-auto px-6">
         <form>...</form>
       </div>

       <!-- 固定按钮区域 -->
       <div class="flex-none py-4 px-6 border-t">
         <button>取消</button>
         <button>保存</button>
       </div>
     </DialogContent>
     ```
   - 确保保存/取消按钮在同一行（flex row）

4. **集成测试**
   - 验证"添加地址"按钮宽度固定，标题不再分行
   - 验证弹窗高度固定为 80vh
   - 验证表单内容可以独立滚动
   - 验证保存/取消按钮始终可见，不随内容滚动
   - 验证桌面端样式不受影响

---

## 验收标准

- [ ] "添加地址"按钮宽度固定，不占据剩余空间
- [ ] "收货地址"标题与按钮在同一行显示，不再被迫分行
- [ ] 地址编辑弹窗高度固定为 80vh
- [ ] 弹窗内表单内容区域可独立滚动
- [ ] 保存/取消按钮固定在弹窗底部，不随表单滚动
- [ ] 保存/取消按钮在同一行显示
- [ ] 桌面端弹窗表现正常（无破坏性变更）

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 固定高度可能在极小屏幕上溢出 | 使用 max-h 配合 overflow-hidden，或添加媒体查询 |
| 按钮区域可能被遮挡 | 确保按钮区域有足够 padding 和背景色 |
| 桌面端样式受影响 | 使用 md: 前缀限定移动端样式，或确保修改是通用的 |

---

**相关文档:**
- [API 文档](../../02-api/)
- [项目状态](../../04-projects/nuxt-moxton.md)
