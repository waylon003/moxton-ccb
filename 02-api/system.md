# 系统与诊断接口

本文档记录后端根路由下的运行探针接口，供本地联调、QA 与运维排查使用。

## 基础信息

- Base URL: `http://localhost:3033`
- 认证: 无需认证
- 依据: `BACKEND-016` QA `PASS`，核心证据位于 `05-verification/BACKEND-016/`；并于 2026-03-23 12:40 +08:00 本地 spot check 复核 `/health`、`/version` 与未知路由错误包
- 最后核对时间: 2026-03-23 12:40 +08:00（实时 spot check）+ 2026-03-23 12:38:27 +08:00（任务文件内 QA 摘要）；历史原始证据时间为 2026-03-19 17:49-17:50 +08:00（`curl-health.txt`、`curl-version.txt`、`failure-path.json`、`automated-test.json`）

## 统一响应包说明

- 成功响应包含顶层字段：`code`、`message`、`data`、`timestamp`、`success`
- 错误响应同样保留顶层 `timestamp`，便于联调和 QA 对时排查
- 历史说明：`05-verification/BACKEND-016/contract-check.json` 中 `api_doc` 仍显示旧路径 `02-api/addresses.md`，这是旧校验脚本残留；自 2026-03-19 起，根路由系统接口以本文档为准，迁移依据见 `02-api/addresses.md` 末尾说明

## 健康检查

**GET** `/health`

**说明**: 返回服务是否可用，以及当前运行环境、时间戳和进程运行时长。

**状态码**:
- `200 OK`: 服务正常

**响应示例**:

```json
{
  "code": 200,
  "message": "Server is healthy",
  "data": {
    "status": "ok",
    "timestamp": "2026-03-23T04:40:02.560Z",
    "uptime": 51549.939524,
    "environment": "development"
  },
  "timestamp": "2026-03-23T04:40:02.560Z",
  "success": true
}
```

**字段说明**:
- `data.status`: 固定为 `ok`
- `data.timestamp`: 服务端生成的 ISO 时间戳
- `data.uptime`: Node 进程运行秒数
- `data.environment`: 当前环境标识，例如 `development`
- `timestamp`: 当前响应包生成时间

## 版本信息

**GET** `/version`

**说明**: 返回当前 API 服务版本、服务名称与运行环境。

**状态码**:
- `200 OK`: 版本信息读取成功

**响应示例**:

```json
{
  "code": 200,
  "message": "Version information retrieved successfully",
  "data": {
    "version": "1.0.0",
    "name": "Moxton Lot API",
    "environment": "development",
    "timestamp": "2026-03-23T04:40:02.633Z"
  },
  "timestamp": "2026-03-23T04:40:02.633Z",
  "success": true
}
```

**字段说明**:
- `data.version`: 当前 API 版本号
- `data.name`: 服务名称
- `data.environment`: 当前环境标识
- `data.timestamp`: 服务端生成的 ISO 时间戳

## 标准错误示例

以下示例用于说明后端根路由的统一错误包结构；`/health-not-found` 仅为 QA 验证未知路由时使用的示例路径，不是正式接口。

**GET** `/health-not-found`

**状态码**:
- `404 Not Found`: 路由不存在

**响应示例**:

```json
{
  "message": "API endpoint not found",
  "code": 404,
  "data": null,
  "timestamp": "2026-03-23T04:40:02.693Z",
  "success": false
}
```

**字段说明**:
- `message`: 标准未知路由提示
- `code`: 业务错误码，对应 `404`
- `timestamp`: 当前响应包生成时间
- `success`: 固定为 `false`
