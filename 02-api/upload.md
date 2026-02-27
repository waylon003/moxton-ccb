### 单文件上
**POST** `/upload/single`
**认证**: Optional (支持游客和用户上
**Content-Type**: `multipart/form-data`
**请求参数**:
- `file` (必需): 上传的文
- `dir` (可选: 存储目录，默认'uploads'
**文件限制**:
- 支持类型: jpg, jpeg, png, gif, webp
- 最大大 10MB
- 自动生成唯一文件
**响应**:
```json
{
  "code": 200,
  "message": "File uploaded successfully",
  "data": {
    "url": "https://oss.moxton.cn/FLQ/uploads/1701234567890_abc123.jpg",
    "fileName": "FLQ/uploads/1701234567890_abc123.jpg",
    "originalName": "my-image.jpg",
    "size": 1024000,
    "mimeType": "image/jpeg"
  },
  "success": true
}
```
**使用示例**:
```javascript
const formData = new FormData();
formData.append('file', fileInput.files[0]);
formData.append('dir', 'products'); // 可选目
const response = await fetch('/upload/single', {
  method: 'POST',
  body: formData
});
```
### 批量文件上传
**POST** `/upload/multiple`
**认证**: Optional
**Content-Type**: `multipart/form-data`
**请求参数**:
- `files` (必需): 文件数组（最少0个文件）
- `dir` (可选: 存储目录，默认'uploads'
**响应**:
```json
{
  "code": 200,
  "message": "All files uploaded successfully",
  "data": {
    "uploaded": [
      {
        "url": "https://oss.moxton.cn/FLQ/uploads/1701234567890_abc123.jpg",
        "fileName": "FLQ/uploads/1701234567890_abc123.jpg",
        "originalName": "image1.jpg",
        "size": 1024000,
        "mimeType": "image/jpeg"
      }
    ],
    "failed": [],
    "totalUploaded": 2,
    "totalFailed": 0
  },
  "success": true
}
```
### 删除文件
**DELETE** `/upload/delete`
**认证**: Required
**Content-Type**: `application/json`
**请求*:
```json
{
  "fileName": "FLQ/uploads/1701234567890_abc123.jpg"
}
```
**响应**:
```json
{
  "code": 200,
  "message": "File deleted successfully",
  "data": {
    "deleted": true,
    "fileName": "FLQ/uploads/1701234567890_abc123.jpg"
  },
  "success": true
}
```
### OSS 配置说明
#### 支持的存储目
- `uploads` - 通用文件
- `products` - 商品图片
- `avatars` - 用户头像
- `documents` - 文档资料
- `categories` - 分类图片
#### 文件命名规则
```
{basePath}{dir}/{timestamp}_{hash}.{extension}
示例: FLQ/products/1701234567890_abc123.jpg
```
#### 返回的URL格式
```
https://oss.moxton.cn/{fileName}
示例: https://oss.moxton.cn/FLQ/products/1701234567890_abc123.jpg
```
---
## 🎯 前端集成指南
### 1. 商品图片上传示例
```javascript
// 上传商品主图
async function uploadProductImages(files, productId) {
  const uploadPromises = files.map(async (file) => {
    const formData = new FormData();
    formData.append('file', file);
    formData.append('dir', 'products');
    const response = await fetch('/upload/single', {
      method: 'POST',
      body: formData
    });
    const result = await response.json();
    return result.data.url; // 返回OSS URL
  });
  const urls = await Promise.all(uploadPromises);
  return urls; // ['https://oss.moxton.cn/FLQ/products/xxx.jpg', ...]
}
```
### 2. 用户头像上传
```javascript
// 更新用户头像
async function updateUserAvatar(file, token) {
  const formData = new FormData();
  formData.append('file', file);
  formData.append('dir', 'avatars');
  const response = await fetch('/upload/single', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`
    },
    body: formData
  });
  const result = await response.json();
  return result.data.url; // 头像URL
}
```
### 3. 富文本编辑器图片上传
```javascript
// 富文本编辑器图片上传集成
async function uploadEditorImage(file) {
  const formData = new FormData();
  formData.append('file', file);
  formData.append('dir', 'documents');
  const response = await fetch('/upload/single', {
    method: 'POST',
    body: formData
  });
  const result = await response.json();
  return result.data.url;
}
```
### v1.2.0 (2025-12-05) 📚 文档完整性更
**文档同步更新**:
#### 🔧 **接口路径修正**
- **认证接口修正** - `/auth/me` `/auth/getUserInfo` `/auth/profile`
- **订单接口修正** - `GET /orders` `GET /orders/user` (用户订单) + `GET /orders` (管理员订
- **支付接口完善** - 移除不存在的 `/payments/:paymentId/status`，补充实际接
#### 🆕 **新增模块文档**
##### 客户管理模块 (`/customers`)
- **咨询管理** - 完整的客户咨询CRUD操作，支持公开创建接口
- **客户列表** - 管理员客户管理，包含订单统计和消费数
- **客户统计** - 全面的客户数据分析，包含增长率、转化率等指
- **咨询跟踪** - 状态管理和分配功能，支持销售流程管
##### 通知系统模块 (`/notifications`)
- **用户通知** - 个人通知管理，支持已未读状态管
- **批量操作** - 批量标记已读、全部标记已读等高效操作
- **通知类型** - 订单、支付、系统、促销等多种通知类型
- **管理员功* - 通知创建、批量推送、过期清理等管理功能
- **统计数据** - 通知数量统计和用户行为分
#### 💳 **支付集成增强**
- **Stripe集成文档** - 完整的Stripe结账会话和Webhook文档
- **PayPal集成文档** - PayPal订单创建和支付捕获流
- **支付回调** - 支付网关回调接口文档
- **退款功* - 支付退款操作文
#### 🏥 **系统监控接口**
- **健康检查* - `/health` 接口，用于负载均衡器监控
- **版本信息** - `/version` 接口，提供API版本和环境信
- **公开访问** - 系统监控接口无需认证，便于运维集
#### 📋 **功能增强文档**
- **订单取消** - 用户订单取消功能
- **订单统计** - 管理员订单统计数据接
- **支付统计** - 管理员支付统计和成功率分
- **用户管理** - 完整的用户信息更新、密码修改功
- **混合认证** - 明确可选认证中间件的使用场
#### 🔍 **文档结构优化**
- **模块化组* - 按功能模块清晰分组，便于查阅
- **认证说明** - 每个接口明确标注认证要求和权限级
- **响应示例** - 完整的JSON响应格式示例，包含实际数据结
- **错误处理** - 统一的错误响应格式说
#### ⚠️ **重要修正**
- 🔧 **实际API为准** - 所有文档内容已与实际代码实现对比验
- 🔧 **移除不存在接* - 清理文档中的虚构接口，确保准确
- 🔧 **补充遗漏接口** - 添加实际存在但文档缺失的完整接口
- 🔧 **路径统一** - 确保所有API路径与实际路由完全一
**技术实现验*:
- 路由文件验证 - 检`src/routes/*.ts` 所有路由定
- 中间件验- 确认认证、权限、错误处理中间件使用
- 参数验证 - 所有请求参数和响应数据格式验证
- 功能完整- 核心业务流程的API覆盖200%
**前端集成就绪**:
- 混合模式架构完整支持游客和用户业务场
- 所有CRUD操作接口齐全，支持完整的增删改查
- 管理后台功能完备，支持完整的运营管理需
- 第三方集成接口齐全，支持支付和文件上传服
**向后兼容性*:
- 核心业务接口保持稳定
- 新增功能不影响现有前端代
- 响应格式保持一致，前端无需修改解析逻辑
## 📞 线上咨询线下订单 API (新增)
