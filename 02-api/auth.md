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
- Admin user: `"roles": ["admin"]`
- Regular user: `"roles": ["user"]`

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

- **user**: Regular user with standard access
- **admin**: Administrator with elevated privileges

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

## Admin User Management API

> All admin endpoints require `Authorization: Bearer <token>` with admin role.

### GET /auth/admin/users

Get paginated user list with search and filters.

**Query Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| pageNum | number | 1 | Page number |
| pageSize | number | 20 | Items per page |
| keyword | string | - | Search username/email/nickname |
| status | number | - | Filter by status (1=active, 0=inactive) |
| role | string | - | Filter by role (user/admin) |

**Success Response (200):**

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
        "role": "user",
        "status": 1,
        "createdAt": "2025-12-18T10:00:00.000Z",
        "updatedAt": "2025-12-18T10:00:00.000Z"
      }
    ],
    "total": 50,
    "pageNum": 1,
    "pageSize": 20
  },
  "timestamp": "2025-12-18T10:00:00.000Z",
  "success": true
}
```

### GET /auth/admin/users/:id

Get user detail by ID.

**Success Response (200):** Same user object as list item, wrapped in `{ code, data, success }`.

---

### PUT /auth/admin/users/:id/status

Toggle user active/inactive status.

**Request Body:**

```json
{
  "status": 0  // 1=active, 0=inactive
}
```

**Business Rule:** Admin cannot deactivate their own account.

**Success Response (200):** Updated user object.

---

### PUT /auth/admin/users/:id/role

Change user role.

**Request Body:**

```json
{
  "role": "admin"  // "user" | "admin"
}
```

**Business Rule:** Admin cannot change their own role.

**Success Response (200):** Updated user object.

---

### DELETE /auth/admin/users/:id

Delete a user.

**Business Rule:** Admin cannot delete themselves.

**Success Response (200):**

```json
{
  "code": 200,
  "message": "User deleted successfully",
  "data": null,
  "success": true
}
```

**Error: Self-deletion (403):**

```json
{
  "code": 403,
  "message": "Cannot delete your own account",
  "data": null,
  "success": false
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
| 404  | Not Found |
| 409  | Conflict (username/email already exists) |
