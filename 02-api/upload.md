# 文件上传 API

## 概述

该模块用于图片上传/删除，基于 `multer` + OSS。

- 路由前缀：`/upload`
- 鉴权：
  - 头像上传：仅需登录
  - 其他上传/删除接口：登录 + `admin/operator`

## 通用响应格式

```json
{
  "code": 200,
  "message": "Success",
  "data": {},
  "timestamp": "2026-02-27T16:00:00.000Z",
  "success": true
}
```

## 文件约束

- 允许 MIME：`image/jpeg`、`image/png`、`image/gif`、`image/webp`
- 允许扩展名：`.jpg`、`.jpeg`、`.png`、`.gif`、`.webp`
- 单文件最大：`10MB`
- 批量最大数量：`10`

---

## POST /upload/single

上传单张图片（管理端）。

**鉴权要求**
- `Authorization: Bearer <admin_or_operator_token>`

**Content-Type**
- `multipart/form-data`

**请求参数**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| file | file | 是 | 上传文件 |
| dir | string | 否 | OSS 子目录，默认 `uploads` |

**成功响应（200）**
```json
{
  "code": 200,
  "message": "File uploaded successfully",
  "data": {
    "url": "https://oss.moxton.cn/FLQ/uploads/1701234567890_abc123.jpg",
    "fileName": "FLQ/uploads/1701234567890_abc123.jpg",
    "originalName": "avatar.jpg",
    "size": 1024000,
    "mimeType": "image/jpeg"
  },
  "timestamp": "2026-02-27T16:00:00.000Z",
  "success": true
}
```

---

## POST /upload/image

`/upload/single` 的别名接口，行为一致。

**鉴权要求**
- `Authorization: Bearer <admin_or_operator_token>`

**请求参数**
- 同 `POST /upload/single`

---

## POST /upload/avatar

上传用户头像（登录用户可用）。

**鉴权要求**
- `Authorization: Bearer <user_or_operator_or_admin_token>`

**Content-Type**
- `multipart/form-data`

**请求参数**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| file | file | 是 | 头像文件 |

**说明**
- 服务端会将文件固定存储到 `avatars` 目录
- 不接受自定义 `dir`

**成功响应（200）**
```json
{
  "code": 200,
  "message": "File uploaded successfully",
  "data": {
    "url": "https://oss.moxton.cn/FLQ/avatars/1701234567890_abc123.jpg",
    "fileName": "FLQ/avatars/1701234567890_abc123.jpg",
    "originalName": "avatar.jpg",
    "size": 1024000,
    "mimeType": "image/jpeg"
  },
  "timestamp": "2026-02-27T16:00:00.000Z",
  "success": true
}
```

---

## POST /upload/multiple

批量上传图片（管理端）。

**鉴权要求**
- `Authorization: Bearer <admin_or_operator_token>`

**Content-Type**
- `multipart/form-data`

**请求参数**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| files | file[] | 是 | 文件数组（最多 10 个） |
| dir | string | 否 | OSS 子目录，默认 `uploads` |

**成功响应（200）**
```json
{
  "code": 200,
  "message": "Upload completed with some failures",
  "data": {
    "uploaded": [
      {
        "url": "https://oss.moxton.cn/FLQ/products/1701234567890_abc123.jpg",
        "fileName": "FLQ/products/1701234567890_abc123.jpg",
        "originalName": "image1.jpg",
        "size": 1024000,
        "mimeType": "image/jpeg"
      }
    ],
    "failed": [
      {
        "fileName": "bad.txt",
        "error": "Invalid file type"
      }
    ],
    "totalUploaded": 1,
    "totalFailed": 1
  },
  "timestamp": "2026-02-27T16:00:00.000Z",
  "success": true
}
```

---

## DELETE /upload/delete

删除 OSS 文件（管理端）。

**鉴权要求**
- `Authorization: Bearer <admin_or_operator_token>`

**Content-Type**
- `application/json`

**请求体**
```json
{
  "fileName": "FLQ/uploads/1701234567890_abc123.jpg"
}
```

**成功响应（200）**
```json
{
  "code": 200,
  "message": "File deleted successfully",
  "data": {
    "deleted": true,
    "fileName": "FLQ/uploads/1701234567890_abc123.jpg"
  },
  "timestamp": "2026-02-27T16:00:00.000Z",
  "success": true
}
```

---

## 常见失败响应

### 未认证或 token 无效（401）
```json
{
  "code": 401,
  "message": "No token provided",
  "data": null,
  "timestamp": "2026-02-27T16:00:00.000Z",
  "success": false
}
```

### 角色不足（403，仅管理端上传/删除接口）
```json
{
  "code": 403,
  "message": "Access denied. Required role: admin or operator",
  "data": null,
  "timestamp": "2026-02-27T16:00:00.000Z",
  "success": false
}
```

### 参数校验失败（400）
```json
{
  "code": 400,
  "message": "Validation Error",
  "data": {
    "errors": [
      "No file uploaded"
    ]
  },
  "timestamp": "2026-02-27T16:00:00.000Z",
  "success": false
}
```
