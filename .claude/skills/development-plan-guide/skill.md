---
name: development-plan-guide
description: 指导 Team Lead 如何为 Moxton 项目编写正确的开发计划，理解项目角色分工，确定任务归属，使用正确的模板和命名规范
---

# 开发计划编写指南

## 概述

本 skill 指导 Team Lead 如何为 Moxton 项目编写正确的开发计划。帮助理解项目角色分工，确定任务归属，使用正确的模板和命名规范。

## 三个关键概念

### 1. 固定角色模板 (`.claude/agents/`)
**用途**: 定义 Codex worker 的身份和行为规范

**文件列表**:
- `team-lead.md` - Team Lead 角色定义（CCB 编排者）
- `shop-frontend.md` - 商城前端开发者
- `admin-frontend.md` - 管理后台前端开发者
- `backend.md` - 后端开发者
- `shop-fe-qa.md` - 商城前端 QA
- `admin-fe-qa.md` - 管理后台 QA
- `backend-qa.md` - 后端 QA
- `protocol.md` - 跨 agent 通信协议

**何时使用**:
- Codex worker 启动时自动加载对应角色模板
- Team Lead 不需要手动引用这些文件

### 2. 开发计划任务模板 (`01-tasks/templates/`)
**用途**: 创建新任务时使用的标准化文档结构

**文件列表**:
- `tech-spec-shop-frontend.md` - 商城前端任务模板
- `tech-spec-admin-frontend.md` - 管理后台任务模板
- `tech-spec-backend.md` - 后端任务模板

**模板结构**:
```markdown
# Tech-Spec: [任务标题]
- 概述（问题陈述、解决方案、范围）
- 开发上下文（现有实现、依赖项）
- 技术方案（API 设计、数据模型、业务逻辑）
- 实施步骤
- 验收标准
- 风险和注意事项
```

**何时使用**:
- Team Lead 创建新任务时，复制对应角色的模板
- 填充具体的需求和技术细节

### 3. 开发计划任务示例 (`.claude/skills/development-plan-guide/examples/`)
**用途**: 展示如何正确填写任务模板的完整示例

**文件列表**:
- `shop-frontend-example.md` - 商城支付功能示例
- `admin-frontend-example.md` - 商品管理页面示例
- `backend-example.md` - 支付 API 示例
- `cross-role-example.md` - 跨角色任务示例

**何时使用**:
- Team Lead 不确定如何填写任务模板时参考
- 学习任务拆分和技术方案编写的最佳实践

## 使用场景

当以下情况发生时，Team Lead 应该调用此 skill：
- 用户要求"编写开发计划"或"创建任务"
- 用户询问"这个任务应该给谁做？"
- 需要将需求拆分为具体的开发任务
- 需要确定任务的角色归属

---

## 工作流程

### 步骤 1: 理解需求并确定角色归属

使用决策树确定任务应该分配给哪个角色：

```
用户需求
    │
    ├─ 涉及商城用户界面？（产品展示、购物车、结账、支付页面）
    │   └─ 是 → SHOP-FE
    │
    ├─ 涉及后台管理界面？（商品管理、订单管理、用户权限、数据统计）
    │   └─ 是 → ADMIN-FE
    │
    ├─ 涉及 API 接口或数据库？（CRUD 操作、业务逻辑、数据存储）
    │   └─ 是 → BACKEND
    │
    └─ 涉及多个角色？
        └─ 创建主任务 + 按角色拆分子任务
```

**角色判断关键词**:
| 角色 | 关键词 | 技术栈 |
|------|--------|--------|
| SHOP-FE | 商城、产品、购物车、结账、支付、用户界面 | Nuxt 3 + Vue 3 + TypeScript |
| ADMIN-FE | 管理、后台、仪表板、统计、报表、CRUD | Vue 3 + TypeScript + SoybeanAdmin |
| BACKEND | API、接口、数据库、后端、服务、逻辑 | Node.js + Koa + TypeScript + Prisma |

### 步骤 2: 选择正确的任务模板

根据角色归属，从 `01-tasks/templates/` 选择对应模板：

| 角色 | 模板文件 | 工作目录 |
|------|----------|----------|
| SHOP-FE | `tech-spec-shop-frontend.md` | `E:\nuxt-moxton` |
| ADMIN-FE | `tech-spec-admin-frontend.md` | `E:\moxton-lotadmin` |
| BACKEND | `tech-spec-backend.md` | `E:\moxton-lotapi` |

### 步骤 3: 创建任务文档

**命名规范**: `[角色代码]-[序号]-[任务标题].md`

**示例**:
- `SHOP-FE-001-stripe-integration.md`
- `ADMIN-FE-001-product-management.md`
- `BACKEND-001-payment-api.md`

**创建位置**:
```
01-tasks/active/
├── shop-frontend/      # SHOP-FE 任务
├── admin-frontend/     # ADMIN-FE 任务
└── backend/            # BACKEND 任务
```

**使用 Python 脚本创建**:
```bash
# 方式 1: 使用 --intake 接收需求并生成任务
python scripts/assign_task.py --intake "实现订单支付状态查询接口"

# 方式 2: 使用 --split-request 拆分跨角色需求
python scripts/assign_task.py --split-request "实现 Stripe webhook + 管理后台状态 UI + 商城支付状态"
```

### 步骤 4: 填写任务内容

参考 `.claude/skills/development-plan-guide/examples/` 中的示例，填写以下部分：

1. **概述**
   - 问题陈述：描述当前问题或需求
   - 解决方案：概述解决方案
   - 范围：明确包含和不包含的内容

2. **开发上下文**
   - 现有实现：相关文件位置和当前实现
   - 依赖项：依赖的其他任务或 API

3. **技术方案**
   - API 设计（BACKEND）/ 组件设计（前端）
   - 数据模型（BACKEND）/ 状态管理（前端）
   - 业务逻辑流程

4. **实施步骤**
   - 列出具体的开发步骤

5. **验收标准**
   - 可测试的验收条件（使用 checkbox）

6. **风险和注意事项**
   - 列出潜在风险和缓解措施

### 步骤 5: 处理跨角色任务

当任务涉及多个角色时：

1. **创建主任务文档**（放在 `01-tasks/active/` 根目录）
2. **按角色拆分子任务**（放在对应角色的子目录）
3. **在主任务中引用所有子任务**

**示例结构**:
```
01-tasks/active/
├── FEATURE-001-complete-order-flow.md (主任务)
├── shop-frontend/
│   ├── SHOP-FE-001-checkout-page.md
│   └── SHOP-FE-002-payment-integration.md
└── backend/
    ├── BACKEND-001-order-api.md
    └── BACKEND-002-payment-api.md
```

**主任务模板**:
```markdown
# FEATURE-001: 完整订单流程

## 概述
实现从浏览产品到支付完成的完整订单流程。

## 子任务

### 商城前端任务
- [SHOP-FE-001](./shop-frontend/SHOP-FE-001-checkout-page.md) - 结账页面
- [SHOP-FE-002](./shop-frontend/SHOP-FE-002-payment-integration.md) - 支付集成

### 后端任务
- [BACKEND-001](./backend/BACKEND-001-order-api.md) - 订单 API
- [BACKEND-002](./backend/BACKEND-002-payment-api.md) - 支付 API

## 依赖关系
SHOP-FE-002 依赖 BACKEND-002 完成
```

---

## 快速参考

### 任务创建检查清单

创建任务前，确认以下各项：

- [ ] **确定角色归属** - 使用决策树确定任务属于哪个角色
- [ ] **选择正确模板** - 从 `01-tasks/templates/` 选择对应模板
- [ ] **命名符合规范** - 格式：`[角色代码]-[序号]-[任务标题].md`
- [ ] **放置正确目录** - 任务放在 `01-tasks/active/[角色]/` 下
- [ ] **填写完整内容** - 概述、技术方案、实施步骤、验收标准
- [ ] **参考示例文档** - 查看 `examples/` 中的示例
- [ ] **添加任务锁** - 使用 `--lock-task` 添加任务锁

### 常用命令

```bash
# 查看当前活动任务
python scripts/assign_task.py --list

# 接收需求并生成任务
python scripts/assign_task.py --intake "需求描述"

# 拆分跨角色需求
python scripts/assign_task.py --split-request "需求描述"

# 添加任务锁
python scripts/assign_task.py --lock-task BACKEND-001 --task-owner team-lead --task-state assigned

# 分派任务给 worker
python scripts/assign_task.py --dispatch-ccb BACKEND-001

# 查看任务锁状态
python scripts/assign_task.py --show-task-locks
```

---

## 示例场景

### 场景 1: 单角色任务（后端 API）

**需求**: 开发订单支付状态查询接口

**分析**:
- 涉及 API 接口 → BACKEND
- 单一角色任务

**操作**:
```bash
python scripts/assign_task.py --intake "开发订单支付状态查询接口"
```

**生成任务**:
- 位置: `01-tasks/active/backend/BACKEND-001-payment-status-api.md`
- 模板: `tech-spec-backend.md`
- 参考示例: `examples/backend-example.md`

### 场景 2: 单角色任务（前端 UI）

**需求**: 实现管理后台订单列表页面

**分析**:
- 涉及后台管理界面 → ADMIN-FE
- 单一角色任务

**操作**:
```bash
python scripts/assign_task.py --intake "实现管理后台订单列表页面"
```

**生成任务**:
- 位置: `01-tasks/active/admin-frontend/ADMIN-FE-001-order-list-page.md`
- 模板: `tech-spec-admin-frontend.md`
- 参考示例: `examples/admin-frontend-example.md`

### 场景 3: 跨角色任务

**需求**: 实现完整的 Stripe 支付流程（前端 + 后端）

**分析**:
- 涉及商城用户界面 → SHOP-FE
- 涉及支付 API → BACKEND
- 跨角色任务

**操作**:
```bash
python scripts/assign_task.py --split-request "实现 Stripe 支付流程：前端集成 Stripe Elements + 后端处理支付 webhook"
```

**生成任务**:
- 主任务: `01-tasks/active/FEATURE-001-stripe-payment.md`
- 子任务 1: `01-tasks/active/shop-frontend/SHOP-FE-001-stripe-elements.md`
- 子任务 2: `01-tasks/active/backend/BACKEND-001-stripe-webhook.md`
- 参考示例: `examples/cross-role-example.md`

---

## 最佳实践

1. **先阅读示例** - 查看 `examples/` 中的完整示例，了解写作风格
2. **保持验收标准可测试** - 每个验收标准都应该能被验证
3. **注明依赖关系** - 如果任务依赖其他任务或 API，明确说明
4. **使用具体文件路径** - 在技术方案中引用具体的文件路径（如 `E:\moxton-lotapi\src\controllers\Order.ts`）
5. **考虑边界情况** - 在风险部分列出可能的边界情况
6. **引用相关文档** - 链接到 `02-api/`、`03-guides/`、`04-projects/` 中的相关文档

---

## 故障排查

### 问题: 不确定任务归属

**解决方案**:
1. 使用决策树逐步判断
2. 参考"角色判断关键词"表格
3. 查看 `01-tasks/completed/` 中类似任务的归属

### 问题: 不知道如何填写技术方案

**解决方案**:
1. 阅读 `.claude/skills/development-plan-guide/examples/` 中的对应示例
2. 查看 `01-tasks/completed/` 中已完成任务的写法
3. 参考 `02-api/` 中的 API 文档

### 问题: 任务涉及多个角色，不知道如何拆分

**解决方案**:
1. 按技术边界拆分（前端 vs 后端）
2. 按功能模块拆分（支付、订单、用户等）
3. 确保每个子任务可以独立完成和测试
4. 参考 `examples/cross-role-example.md`

---

## 相关文档

| 文档 | 路径 | 说明 |
|------|------|------|
| 固定角色模板 | `.claude/agents/` | Codex worker 的身份定义 |
| 任务模板 | `01-tasks/templates/` | 创建新任务时使用的模板 |
| 任务示例 | `.claude/skills/development-plan-guide/examples/` | 完整的任务编写示例 |
| 任务状态 | `01-tasks/STATUS.md` | 当前任务统计 |
| API 文档 | `02-api/` | 后端 API 规范 |
| 开发指南 | `03-guides/` | 技术指南和最佳实践 |
| 项目状态 | `04-projects/` | 三端项目状态 |
| CCB 通信协议 | `.claude/agents/protocol.md` | 跨 agent 通信规范 |



Moxton 项目有 3 个核心角色，每个角色负责不同的项目和技术栈：

| 角色 | 代码 | 项目 | 工作目录 | 技术栈 |
|------|------|------|----------|--------|
| 独立站前端工程师 | `SHOP-FE` | nuxt-moxton | `E:\nuxt-moxton` | Nuxt 3 + Vue 3 + TypeScript + Reka UI + UnoCSS |
| CRUD前端工程师 | `ADMIN-FE` | moxton-lotadmin | `E:\moxton-lotadmin` | Vue 3 + TypeScript + SoybeanAdmin + Naive UI |
| 后端工程师 | `BACKEND` | moxton-lotapi | `E:\moxton-lotapi` | Node.js + Koa + TypeScript + Prisma + MySQL |

---

## 任务归属决策树

使用以下决策树来确定任务应该分配给哪个角色：

```
用户需求
    │
    ├─ 涉及商城用户界面？（产品展示、购物车、结账、支付页面）
    │   └─ 是 → SHOP-FE
    │
    ├─ 涉及后台管理界面？（商品管理、订单管理、用户权限、数据统计）
    │   └─ 是 → ADMIN-FE
    │
    ├─ 涉及 API 接口或数据库？（CRUD 操作、业务逻辑、数据存储）
    │   └─ 是 → BACKEND
    │
    └─ 涉及多个角色？
        └─ 创建主任务 + 按角色拆分子任务
```

### 角色任务特征

#### SHOP-FE（独立站前端）
**典型任务：**
- 商城页面开发（首页、产品页、分类页）
- 购物车功能
- 结账流程
- 支付集成（Stripe 等）
- 用户界面交互
- 响应式布局

**判断关键词：** 商城、产品、购物车、结账、支付、用户界面、页面

#### ADMIN-FE（CRUD前端）
**典型任务：**
- 商品管理界面
- 订单管理界面
- 用户权限管理
- 数据统计和报表
- 后台仪表板
- 表单和列表组件

**判断关键词：** 管理、后台、仪表板、统计、报表、CRUD

#### BACKEND（后端）
**典型任务：**
- API 接口开发
- 数据库设计和迁移
- 认证和授权
- 业务逻辑实现
- 第三方服务集成
- 数据处理和存储

**判断关键词：** API、接口、数据库、后端、服务、逻辑

---

## 任务目录结构

```
E:\moxton-ccb\01-tasks\
├── active/
│   ├── shop-frontend/      # SHOP-FE 任务
│   ├── admin-frontend/     # ADMIN-FE 任务
│   └── backend/            # BACKEND 任务
├── backlog/
│   ├── shop-frontend/
│   ├── admin-frontend/
│   └── backend/
├── completed/
│   ├── shop-frontend/
│   ├── admin-frontend/
│   └── backend/
└── templates/
    ├── tech-spec-shop-frontend.md
    ├── tech-spec-admin-frontend.md
    └── tech-spec-backend.md
```

---

## 命名规范

### 格式

```
[角色代码]-[序号]-[任务标题].md
```

### 示例

| 角色 | 文件名示例 |
|------|-----------|
| SHOP-FE | `SHOP-FE-001-stripe-integration.md` |
| SHOP-FE | `SHOP-FE-002-shopping-cart-refactor.md` |
| ADMIN-FE | `ADMIN-FE-001-product-management.md` |
| ADMIN-FE | `ADMIN-FE-002-order-list-page.md` |
| BACKEND | `BACKEND-001-payment-api.md` |
| BACKEND | `BACKEND-002-user-authentication.md` |

### 命名规则

1. **角色代码**：使用大写代码（SHOP-FE、ADMIN-FE、BACKEND）
2. **序号**：三位数字，从 001 开始递增
3. **任务标题**：小写字母，单词用连字符连接
4. **文件扩展名**：`.md`

---

## 任务模板使用指南

### 选择正确的模板

| 角色 | 模板文件 | 路径 |
|------|----------|------|
| SHOP-FE | `tech-spec-shop-frontend.md` | `01-tasks/templates/` |
| ADMIN-FE | `tech-spec-admin-frontend.md` | `01-tasks/templates/` |
| BACKEND | `tech-spec-backend.md` | `01-tasks/templates/` |

### 创建任务步骤

```bash
# 1. 复制对应角色的模板
cp E:\moxton-ccb\01-tasks\templates\tech-spec-shop-frontend.md \
   E:\moxton-ccb\01-tasks\active\shop-frontend\SHOP-FE-001-new-feature.md

# 2. 编辑任务文档，填写以下部分：
#    - 概述（问题陈述、解决方案、范围）
#    - 开发上下文（现有实现、依赖项）
#    - 技术方案（架构设计、数据模型、API 调用）
#    - 实施步骤
#    - 验收标准
#    - 风险和注意事项

# 3. 更新 STATUS.md
```

---

## 任务拆分指南

### 单角色任务

当任务只涉及一个角色时：

1. 确定角色归属
2. 在对应角色的 `active/` 目录创建任务
3. 使用该角色的模板
4. 直接编写技术规格

**示例：**
```
需求：实现 Stripe 支付集成
→ 角色：SHOP-FE
→ 位置：01-tasks/active/shop-frontend/SHOP-FE-001-stripe-integration.md
```

### 跨角色任务

当任务涉及多个角色时：

1. **创建主任务文档**（放在 `01-tasks/active/` 根目录）
2. **按角色拆分子任务**
3. **每个子任务使用对应角色的模板**
4. **在主任务中引用所有子任务**

**示例结构：**
```
01-tasks/active/
├── FEATURE-001-complete-order-flow.md (主任务)
└── shop-frontend/
    ├── SHOP-FE-001-checkout-page.md
    └── SHOP-FE-002-payment-integration.md
```

**主任务模板：**
```markdown
# FEATURE-001: 完整订单流程

## 概述
实现从浏览产品到支付完成的完整订单流程。

## 子任务

### 前端任务
- [SHOP-FE-001](./shop-frontend/SHOP-FE-001-checkout-page.md) - 结账页面
- [SHOP-FE-002](./shop-frontend/SHOP-FE-002-payment-integration.md) - 支付集成

### 后端任务
- [BACKEND-001](./backend/BACKEND-001-order-api.md) - 订单 API
- [BACKEND-002](./backend/BACKEND-002-payment-api.md) - 支付 API

## 依赖关系
```

---

## 快速检查清单

创建任务前，确认以下各项：

- [ ] **确定角色归属** - 使用决策树确定任务属于哪个角色
- [ ] **选择正确目录** - 任务将放在 `active/` 下的哪个子目录
- [ ] **使用正确模板** - 根据角色选择对应的模板文件
- [ ] **命名符合规范** - 格式：`[角色代码]-[序号]-[任务标题].md`
- [ ] **填写完整内容** - 概述、技术方案、实施步骤、验收标准
- [ ] **更新 STATUS.md** - 记录新任务的创建

---

## 示例场景

### 场景 1：商城支付功能

**需求：** 实现 Stripe 支付集成

**分析：**
- 涉及商城用户界面 → SHOP-FE
- 需要调用支付 API → 涉及后端

**决策：** 跨角色任务

**任务结构：**
```
01-tasks/active/
├── FEATURE-001-stripe-payment.md (主任务)
├── shop-frontend/
│   └── SHOP-FE-001-stripe-elements-integration.md
└── backend/
    └── BACKEND-001-stripe-api-endpoint.md
```

### 场景 2：商品管理页面

**需求：** 实现后台商品管理界面

**分析：**
- 涉及后台管理界面 → ADMIN-FE

**决策：** 单角色任务（ADMIN-FE）

**任务位置：**
```
01-tasks/active/admin-frontend/ADMIN-FE-001-product-management.md
```

### 场景 3：支付 API 开发

**需求：** 开发支付处理 API

**分析：**
- 涉及 API 接口和业务逻辑 → BACKEND

**决策：** 单角色任务（BACKEND）

**任务位置：**
```
01-tasks/active/backend/BACKEND-001-payment-api.md
```

---

## 相关文档

| 文档 | 路径 | 说明 |
|------|------|------|
| 任务状态 | `01-tasks/STATUS.md` | 当前任务统计 |
| 角色定义 | `.claude/agents/` | AI 角色提示词 |
| API 文档 | `02-api/` | 后端 API 规范 |
| 项目状态 | `04-projects/` | 三端项目状态 |

---

## 技巧和最佳实践

1. **先阅读现有任务** - 查看 `active/` 和 `completed/` 中的任务，了解写作风格
2. **保持验收标准可测试** - 每个验收标准都应该能被验证
3. **注明依赖关系** - 如果任务依赖其他任务或 API，明确说明
4. **使用具体文件路径** - 在技术方案中引用具体的文件路径
5. **考虑边界情况** - 在风险部分列出可能的边界情况
6. **更新相关文档** - 创建任务后更新 STATUS.md

---

## 故障排查

### 问题：不确定任务归属

**解决方案：**
1. 使用决策树逐步判断
2. 参考上述"角色任务特征"
3. 查看现有类似任务属于哪个角色

### 问题：任务涉及多个角色

**解决方案：**
1. 创建主任务文档描述整体需求
2. 按角色拆分为多个子任务
3. 在主任务中明确子任务之间的关系

### 问题：不确定如何拆分任务

**解决方案：**
1. 按技术边界拆分（前端 vs 后端）
2. 按功能模块拆分（支付、订单、用户等）
3. 确保每个任务可以独立完成和测试

