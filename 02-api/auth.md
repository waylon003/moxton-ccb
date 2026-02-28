# Authentication API

**Base URL**: `http://localhost:3033`

## Overview

The Authentication API provides user registration, login, profile management, and password change functionality. It supports both guest and authenticated users using JWT tokens.

---

## POST /auth/register

Register a new user account.

### Request Body

```json
{
  "username": "string",      // Required, min 3 characters
  "email": "string",         // Required, valid email format
  "password": "string",      // Required, min 6 characters
  "nickname": "string",      // Optional, user display name
  "phone": "string"          // Optional, phone number
}
```

**Field Validation Rules:**
- `username`: Minimum 3 characters, must be unique
- `email`: Must be valid email format, must be unique
- `password`: Minimum 6 characters (will be hashed with bcrypt, 10 salt rounds)
- `nickname`: Optional display name
- `phone`: Optional phone number

**Alternative Field Name:** The API accepts both `username` and `userName` for compatibility.

### Success Response (200)

```json
{
  "code": 200,
  "message": "User registered successfully",
  "data": {
    "user": {
      "id": "clt1234567890",                    // User unique ID (CUID)
      "username": "testuser",                    // Username
      "email": "test@example.com",               // Email address
      "nickname": "测试昵称",                      // Display name (if provided)
      "phone": "+86-13800138000",                // Phone number (if provided)
      "avatar": null,                            // Avatar URL (default null)
      "role": "user",                            // User role: "user" or "admin"
      "status": 1,                               // Account status: 1=active, 0=inactive
      "createdAt": "2025-12-18T10:00:00.000Z",   // Account creation timestamp
      "updatedAt": "2025-12-18T10:00:00.000Z"    // Last update timestamp
    },
    "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."  // JWT access token
  },
  "timestamp": "2025-12-18T10:00:00.000Z",
  "success": true
}
```

### Error Responses

**Username Already Exists (409)**
```json
{
  "code": 409,
  "message": "用户名已存在",
  "data": null,
  "timestamp": "2025-12-18T10:00:00.000Z",
  "success": false
}
```

**Email Already Exists (409)**
```json
{
  "code": 409,
  "message": "邮箱已存在",
  "data": null,
  "timestamp": "2025-12-18T10:00:00.000Z",
  "success": false
}
```

**Validation Error (400)**
```json
{
  "code": 400,
  "message": "Validation failed",
  "data": {
    "errors": [
      "Username must be at least 3 characters long",
      "Invalid email format",
      "Password must be at least 6 characters long"
    ]
  },
  "timestamp": "2025-12-18T10:00:00.000Z",
  "success": false
}
```

---

## POST /auth/login

Login with username/email and password.

### Request Body

```json
{
  "username": "string",      // Required: username or email
  "password": "string"       // Required: account password
}
```

**Supported Login Methods:**
- Login with username: `{ "username": "testuser", "password": "..." }`
- Login with email: `{ "username": "test@example.com", "password": "..." }`
- Alternative field name: `userName` (accepted for compatibility)

### Success Response (200)

```json
{
  "code": 200,
  "message": "Login successful",
  "data": {
    "user": {
      "id": "clt1234567890",                    // User unique ID
      "username": "testuser",                    // Username
      "email": "test@example.com",               // Email address
      "nickname": "测试昵称",                      // Display name
      "phone": "+86-13800138000",                // Phone number
      "avatar": "https://example.com/avatar.jpg", // Avatar URL
      "role": "user",                            // User role: "user" or "admin"
      "status": 1,                               // Account status: 1=active, 0=inactive
      "createdAt": "2025-12-18T10:00:00.000Z",   // Account creation timestamp
      "updatedAt": "2025-12-18T10:00:00.000Z"    // Last update timestamp
    },
    "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."  // JWT access token
  },
  "timestamp": "2025-12-18T10:00:00.000Z",
  "success": true
}
```

### Error Responses

**Invalid Credentials (401)**
```json
{
  "code": 401,
  "message": "Invalid credentials",
  "data": null,
  "timestamp": "2025-12-18T10:00:00.000Z",
  "success": false
}
```

**Account Deactivated (401)**
```json
{
  "code": 401,
  "message": "Account is deactivated",
  "data": null,
  "timestamp": "2025-12-18T10:00:00.000Z",
  "success": false
}
```

**Missing Required Fields (400)**
```json
{
  "code": 400,
  "message": "Validation failed",
  "data": {
    "errors": ["Username and password are required"]
  },
  "timestamp": "2025-12-18T10:00:00.000Z",
  "success": false
}
```

---

## GET /auth/getUserInfo

Get current user information (frontend compatible format).

**Authentication**: Required

**Request Headers:**
```
Authorization: Bearer <token>
```

### Success Response (200)

```json
{
  "code": 200,
  "message": "Success",
  "data": {
    "userId": "clt1234567890",              // User ID
    "userName": "testuser",                 // Username
    "roles": ["user"],                      // User roles array
    "buttons": []                           // Permission buttons (reserved for future use)
  },
  "timestamp": "2025-12-18T10:00:00.000Z",
  "success": true
}
```

**Role Mapping:**
- 管理员: `"roles": ["admin"]`
- 运营: `"roles": ["operator"]`
- 普通用户: `"roles": ["user"]`

### Error Responses

**Unauthorized (401)**
```json
{
  "code": 401,
  "message": "Unauthorized",
  "data": null,
  "timestamp": "2025-12-18T10:00:00.000Z",
  "success": false
}
```

**User Not Found (404)**
```json
{
  "code": 404,
  "message": "User not found",
  "data": null,
  "timestamp": "2025-12-18T10:00:00.000Z",
  "success": false
}
```

---

## GET /auth/profile

Get complete user profile information.

**Authentication**: Required

**Request Headers:**
```
Authorization: Bearer <token>
```

### Success Response (200)

```json
{
  "code": 200,
  "message": "Success",
  "data": {
    "id": "clt1234567890",                    // User unique ID
    "username": "testuser",                    // Username
    "email": "test@example.com",               // Email address
    "nickname": "测试昵称",                      // Display name
    "phone": "+86-13800138000",                // Phone number
    "avatar": "https://example.com/avatar.jpg", // Avatar URL
    "role": "user",                            // User role: "user" or "admin"
    "status": 1,                               // Account status: 1=active, 0=inactive
    "createdAt": "2025-12-18T10:00:00.000Z",   // Account creation timestamp
    "updatedAt": "2025-12-18T10:00:00.000Z"    // Last update timestamp
  },
  "timestamp": "2025-12-18T10:00:00.000Z",
  "success": true
}
```

### Error Responses

**Unauthorized (401)**
```json
{
  "code": 401,
  "message": "Unauthorized",
  "data": null,
  "timestamp": "2025-12-18T10:00:00.000Z",
  "success": false
}
```

**User Not Found (404)**
```json
{
  "code": 404,
  "message": "User not found",
  "data": null,
  "timestamp": "2025-12-18T10:00:00.000Z",
  "success": false
}
```

---

## POST /auth/logout

Logout the current user (frontend compatible).

**Authentication**: Required

**Request Headers:**
```
Authorization: Bearer <token>
```

**Note:** Since JWT tokens are stateless, the server doesn't perform any token invalidation. The frontend should remove the token from localStorage.

### Success Response (200)

```json
{
  "code": 200,
  "message": "Logout successful",
  "data": null,
  "timestamp": "2025-12-18T10:00:00.000Z",
  "success": true
}
```

---

## PUT /auth/profile

Update user profile information.

**Authentication**: Required

**Request Headers:**
```
Authorization: Bearer <token>
```

### Request Body

```json
{
  "nickname": "string",      // Optional: new display name
  "phone": "string",         // Optional: new phone number
  "avatar": "string"         // Optional: new avatar URL
}
```

**Note:** All fields are optional. Only provided fields will be updated.

### Success Response (200)

```json
{
  "code": 200,
  "message": "Profile updated successfully",
  "data": {
    "id": "clt1234567890",                    // User unique ID
    "username": "testuser",                    // Username (unchanged)
    "email": "test@example.com",               // Email (unchanged)
    "nickname": "新昵称",                      // Updated display name
    "phone": "+86-13900139000",                // Updated phone number
    "avatar": "https://example.com/new-avatar.jpg",  // Updated avatar URL
    "role": "user",                            // User role (unchanged)
    "status": 1,                               // Account status (unchanged)
    "createdAt": "2025-12-18T10:00:00.000Z",   // Original creation timestamp
    "updatedAt": "2025-12-18T11:00:00.000Z"    // Update timestamp
  },
  "timestamp": "2025-12-18T11:00:00.000Z",
  "success": true
}
```

### Error Responses

**Unauthorized (401)**
```json
{
  "code": 401,
  "message": "Unauthorized",
  "data": null,
  "timestamp": "2025-12-18T10:00:00.000Z",
  "success": false
}
```

**User Not Found (404)**
```json
{
  "code": 404,
  "message": "User not found",
  "data": null,
  "timestamp": "2025-12-18T10:00:00.000Z",
  "success": false
}
```

---

## PUT /auth/password

Change user password.

**Authentication**: Required

**Request Headers:**
```
Authorization: Bearer <token>
```

### Request Body

```json
{
  "currentPassword": "string",   // Required: current password
  "newPassword": "string"        // Required: new password (min 6 characters)
}
```

**Validation Rules:**
- `currentPassword`: Must match the user's current password
- `newPassword`: Minimum 6 characters (will be hashed with bcrypt, 10 salt rounds)

### Success Response (200)

```json
{
  "code": 200,
  "message": "Password changed successfully",
  "data": null,
  "timestamp": "2025-12-18T10:00:00.000Z",
  "success": true
}
```

### Error Responses

**Missing Required Fields (400)**
```json
{
  "code": 400,
  "message": "Validation failed",
  "data": {
    "errors": ["Current password and new password are required"]
  },
  "timestamp": "2025-12-18T10:00:00.000Z",
  "success": false
}
```

**New Password Too Short (400)**
```json
{
  "code": 400,
  "message": "Validation failed",
  "data": {
    "errors": ["New password must be at least 6 characters long"]
  },
  "timestamp": "2025-12-18T10:00:00.000Z",
  "success": false
}
```

**Current Password Incorrect (401)**
```json
{
  "code": 401,
  "message": "Current password is incorrect",
  "data": null,
  "timestamp": "2025-12-18T10:00:00.000Z",
  "success": false
}
```

**User Not Found (404)**
```json
{
  "code": 404,
  "message": "User not found",
  "data": null,
  "timestamp": "2025-12-18T10:00:00.000Z",
  "success": false
}
```

---

## Authentication Details

### JWT Token Structure

The JWT token contains the following user information:

```javascript
{
  "id": "clt1234567890",        // User ID
  "username": "testuser",       // Username
  "email": "test@example.com",  // Email
  "role": "user"                // User role
}
```

### Token Usage

Include the token in the `Authorization` header for authenticated requests:

```
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

### User Roles

- **user**: 普通用户，标准前台权限
- **operator**: 运营角色，具备商品/分类/订单/上传管理权限
- **admin**: 管理员，具备全部管理权限（含用户管理）

### Account Status

- **1** (active): Account is active and can login
- **0** (inactive): Account is deactivated and cannot login

### Password Security

- Passwords are hashed using bcryptjs with 10 salt rounds
- Plain text passwords are never stored or returned in API responses
- Minimum password length: 6 characters

### Error Response Format

All error responses follow this structure:

```json
{
  "code": <HTTP_STATUS_CODE>,
  "message": "<Error message>",
  "data": null | { "errors": ["<error details>"] },
  "timestamp": "<ISO_8601_TIMESTAMP>",
  "success": false
}
```

---

## 管理端用户管理 API（BACKEND-008）

> 路由前缀：`/auth/admin/users`  
> 鉴权要求：`Authorization: Bearer <token>` 且角色必须为 `admin`（`operator` 不可访问该组接口）

### GET /auth/admin/users

分页查询用户列表，支持关键字与角色/状态筛选。

**Query 参数**

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| pageNum | number | 1 | 页码 |
| pageSize | number | 20 | 每页数量 |
| keyword | string | - | 模糊匹配 `username/email/nickname` |
| status | number | - | 状态筛选：`1` 启用，`0` 停用 |
| role | string | - | 角色筛选：`user` / `operator` / `admin` |

**成功响应（200）**
```json
{
  "code": 200,
  "message": "Success",
  "data": {
    "list": [
      {
        "id": "clt1234567890",
        "username": "testuser",
        "email": "test@example.com",
        "nickname": "Test",
        "phone": "+86-13800138000",
        "avatar": null,
        "role": "operator",
        "status": 1,
        "createdAt": "2025-12-18T10:00:00.000Z",
        "updatedAt": "2025-12-18T10:00:00.000Z"
      }
    ],
    "total": 50,
    "pageNum": 1,
    "pageSize": 20,
    "totalPages": 3
  },
  "timestamp": "2025-12-18T10:00:00.000Z",
  "success": true
}
```

**常见失败响应**
- `401`：未登录或 token 无效
- `403`：非 `admin` 角色

### GET /auth/admin/users/:id

根据用户 ID 查询详情。

**路径参数**
| 参数 | 类型 | 说明 |
|------|------|------|
| id | string | 用户 ID |

**成功响应（200）**
```json
{
  "code": 200,
  "message": "Success",
  "data": {
    "id": "clt1234567890",
    "username": "testuser",
    "email": "test@example.com",
    "nickname": "Test",
    "phone": null,
    "avatar": null,
    "role": "user",
    "status": 1,
    "createdAt": "2025-12-18T10:00:00.000Z",
    "updatedAt": "2025-12-18T10:00:00.000Z"
  },
  "timestamp": "2025-12-18T10:00:00.000Z",
  "success": true
}
```

---

### PUT /auth/admin/users/:id/status

更新用户状态（启用/停用）。

**请求体**
```json
{
  "status": 0
}
```

**业务规则**
- `status` 仅允许 `0` 或 `1`
- 管理员不能停用自己账号（返回 `403`）

**成功响应（200）**  
返回更新后的用户对象（不含密码）。

---

### PUT /auth/admin/users/:id/role

更新用户角色。

**请求体**
```json
{
  "role": "operator"
}
```

**role 允许值**
- `user`
- `operator`
- `admin`

**业务规则**
- 管理员不能修改自己的角色（返回 `403`）
- 非法角色值返回 `400`

**成功响应（200）**  
返回更新后的用户对象（不含密码）。

**非法角色示例（400）**
```json
{
  "code": 400,
  "message": "Validation Error",
  "data": {
    "errors": [
      "Role must be \"user\", \"operator\" or \"admin\""
    ]
  },
  "timestamp": "2025-12-18T10:00:00.000Z",
  "success": false
}
```

---

### DELETE /auth/admin/users/:id

删除用户。

**路径参数**
| 参数 | 类型 | 说明 |
|------|------|------|
| id | string | 用户 ID |

**业务规则**
- 管理员不能删除自己（返回 `403`）

**成功响应（200）**
```json
{
  "code": 200,
  "message": "User deleted successfully",
  "data": null,
  "timestamp": "2025-12-18T10:00:00.000Z",
  "success": true
}
```

---

## Common HTTP Status Codes

| Code | Description |
|------|-------------|
| 200  | Success |
| 201  | Created |
| 400  | Bad Request (validation error) |
| 401  | Unauthorized (invalid/missing token or credentials) |
| 403  | Forbidden (insufficient role/permission) |
| 404  | Not Found |
| 409  | Conflict (username/email already exists) |
