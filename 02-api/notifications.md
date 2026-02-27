### 用户通知管理
#### 获取用户通知列表
**GET** `/notifications/user`
**认证**: Required
**Header**: `Authorization: Bearer <token>`
**查询参数**:
- `pageNum` (可选: 页码，默认1
- `pageSize` (可选: 每页数量，默认10
- `type` (可选: 通知类型 (ORDER, PAYMENT, SYSTEM, PROMOTION)
- `status` (可选: 读取状(READ, UNREAD)
**响应**:
```json
{
  "code": 200,
  "message": "User notifications retrieved successfully",
  "data": {
    "list": [
      {
        "id": "clt123456789",
        "title": "订单状态更,
        "content": "您的订单 ORD2025120210001 已确认发,
        "type": "ORDER",
        "status": "UNREAD",
        "priority": "NORMAL",
        "actionUrl": "/orders/ORD2025120210001",
        "data": {
          "orderNo": "ORD2025120210001",
          "status": "SHIPPED"
        },
        "createdAt": "2025-12-02T10:00:00.000Z"
      }
    ],
    "total": 1,
    "pageNum": 1,
    "pageSize": 10,
    "totalPages": 1
  },
  "success": true
}
```
#### 获取通知详情
**GET** `/notifications/:id`
**认证**: Required
**Header**: `Authorization: Bearer <token>`
**响应**:
```json
{
  "code": 200,
  "message": "Notification retrieved successfully",
  "data": {
    "id": "clt123456789",
    "title": "订单状态更,
    "content": "您的订单 ORD2025120210001 已确认发货，预计3-5个工作日送达。您可以点击下方链接查看物流信息,
    "type": "ORDER",
    "status": "UNREAD",
    "priority": "NORMAL",
    "actionUrl": "/orders/ORD2025120210001",
    "data": {
      "orderNo": "ORD2025120210001",
      "status": "SHIPPED",
      "trackingNumber": "SF1234567890"
    },
    "userId": "clt123456788",
    "createdAt": "2025-12-02T10:00:00.000Z",
    "updatedAt": "2025-12-02T10:00:00.000Z"
  },
  "success": true
}
```
#### 标记通知为已
**PUT** `/notifications/:id/read`
**认证**: Required
**Header**: `Authorization: Bearer <token>`
**响应**:
```json
{
  "code": 200,
  "message": "Notification marked as read",
  "data": {
    "id": "clt123456789",
    "status": "READ",
    "readAt": "2025-12-02T11:00:00.000Z"
  },
  "success": true
}
```
#### 批量标记通知为已
**PUT** `/notifications/batch/read`
**认证**: Required
**Header**: `Authorization: Bearer <token>`
**请求*:
```json
{
  "notificationIds": ["clt123456789", "clt123456790", "clt123456791"]
}
```
**响应**:
```json
{
  "code": 200,
  "message": "Notifications marked as read successfully",
  "data": {
    "marked": 3,
    "failed": [],
    "message": "3 notifications marked as read"
  },
  "success": true
}
```
#### 标记所有通知为已
**PUT** `/notifications/all/read`
**认证**: Required
**Header**: `Authorization: Bearer <token>`
**响应**:
```json
{
  "code": 200,
  "message": "All notifications marked as read",
  "data": {
    "marked": 15,
    "userId": "clt123456788"
  },
  "success": true
}
```
#### 删除通知
**DELETE** `/notifications/:id`
**认证**: Required
**Header**: `Authorization: Bearer <token>`
**响应**:
```json
{
  "code": 200,
  "message": "Notification deleted successfully",
  "data": {
    "deleted": true,
    "id": "clt123456789"
  },
  "success": true
}
```
#### 获取未读通知数量
**GET** `/notifications/unread/count`
**认证**: Required
**Header**: `Authorization: Bearer <token>`
**响应**:
```json
{
  "code": 200,
  "message": "Unread notifications count retrieved successfully",
  "data": {
    "unreadCount": 5,
    "userId": "clt123456788"
  },
  "success": true
}
```
#### 获取通知统计
**GET** `/notifications/user/stats`
**认证**: Required
**Header**: `Authorization: Bearer <token>`
**响应**:
```json
{
  "code": 200,
  "message": "Notification statistics retrieved successfully",
  "data": {
    "totalNotifications": 45,
    "unreadNotifications": 8,
    "readNotifications": 37,
    "orderNotifications": 12,
    "paymentNotifications": 8,
    "systemNotifications": 15,
    "promotionNotifications": 10,
    "thisWeekNotifications": 6,
    "thisMonthNotifications": 28
  },
  "success": true
}
```
#### 获取最新通知
**GET** `/notifications/user/latest`
**认证**: Required
**Header**: `Authorization: Bearer <token>`
**查询参数**:
- `limit` (可选: 数量限制，默认5
**响应**:
```json
{
  "code": 200,
  "message": "Latest notifications retrieved successfully",
  "data": [
    {
      "id": "clt123456789",
      "title": "订单状态更,
      "content": "您的订单已确认发,
      "type": "ORDER",
      "status": "UNREAD",
      "createdAt": "2025-12-02T10:00:00.000Z"
    }
  ],
  "success": true
}
```
### 管理员通知功能
#### 创建通知（管理员
**POST** `/notifications`
**认证**: Required (Admin)
**请求*:
```json
{
  "userId": "clt123456788",
  "title": "系统维护通知",
  "content": "系统将于今晚22:00-23:00进行维护升级，期间可能影响正常使用,
  "type": "SYSTEM",
  "priority": "HIGH",
  "actionUrl": "/system/maintenance"
}
```
**响应**:
```json
{
  "code": 200,
  "message": "Notification created successfully",
  "data": {
    "id": "clt123456790",
    "title": "系统维护通知",
    "type": "SYSTEM",
    "status": "UNREAD",
    "createdAt": "2025-12-02T12:00:00.000Z"
  },
  "success": true
}
```
#### 批量创建通知（管理员
**POST** `/notifications/batch`
**认证**: Required (Admin)
**请求*:
```json
{
  "userIds": ["clt123456788", "clt123456789", "clt123456790"],
  "title": "新品上市通知",
  "content": "我们很高兴地通知您，全新的智能传感器系列现已上市,
  "type": "PROMOTION",
  "priority": "NORMAL",
  "actionUrl": "/products/new"
}
```
#### 清理过期通知（管理员
**DELETE** `/notifications/cleanup`
**认证**: Required (Admin)
**查询参数**:
- `days` (可选: 保留天数，默认30
**响应**:
```json
{
  "code": 200,
  "message": "Old notifications cleaned up successfully",
  "data": {
    "deleted": 125,
    "retentionDays": 30,
    "cleanupDate": "2025-12-02T12:00:00.000Z"
  },
  "success": true
}
```
---
## 🌍 地址补全 API (新增)
