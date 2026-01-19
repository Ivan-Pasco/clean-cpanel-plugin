# Frame cPanel Plugin - API Reference

This document provides complete API documentation for the Frame cPanel Plugin.

## Table of Contents

1. [WHM API](#whm-api)
2. [cPanel UAPI](#cpanel-uapi)
3. [Manager Daemon REST API](#manager-daemon-rest-api)

---

## WHM API

The WHM API is available to server administrators through the WHM interface.

**Module**: `Whostmgr::API::1::Frame`

### status

Get the current status of the Frame manager service.

**Endpoint**: `GET /json-api/Frame/status`

**Parameters**: None

**Response**:
```json
{
    "status": "running",
    "version": "1.0.0",
    "uptime": 86400,
    "memory_mb": 128,
    "instance_count": 15,
    "port_range": "30001-32000",
    "ports_allocated": 15,
    "ports_available": 1985
}
```

### instances

List all user Frame instances.

**Endpoint**: `GET /json-api/Frame/instances`

**Parameters**:
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| status | string | No | Filter by status: running, stopped, all |
| limit | integer | No | Maximum results (default: 100) |
| offset | integer | No | Offset for pagination |

**Response**:
```json
{
    "total": 15,
    "instances": [
        {
            "user": "johndoe",
            "status": "running",
            "port": 30001,
            "memory_mb": 256,
            "app_count": 3,
            "uptime": 3600,
            "created_at": 1704067200
        }
    ]
}
```

### start_instance

Start a user's Frame instance.

**Endpoint**: `POST /json-api/Frame/start_instance`

**Parameters**:
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| user | string | Yes | cPanel username |

**Response**:
```json
{
    "success": true,
    "user": "johndoe",
    "port": 30001,
    "pid": 12345
}
```

### stop_instance

Stop a user's Frame instance.

**Endpoint**: `POST /json-api/Frame/stop_instance`

**Parameters**:
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| user | string | Yes | cPanel username |

**Response**:
```json
{
    "success": true,
    "user": "johndoe"
}
```

### restart_instance

Restart a user's Frame instance.

**Endpoint**: `POST /json-api/Frame/restart_instance`

**Parameters**:
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| user | string | Yes | cPanel username |

**Response**:
```json
{
    "success": true,
    "user": "johndoe",
    "port": 30001,
    "pid": 12346
}
```

### get_settings

Get global Frame settings.

**Endpoint**: `GET /json-api/Frame/get_settings`

**Parameters**: None

**Response**:
```json
{
    "service": {
        "enabled": true,
        "api_port": 9500
    },
    "ports": {
        "range_start": 30001,
        "range_end": 32000
    },
    "defaults": {
        "memory_limit_mb": 512,
        "max_apps_per_user": 10,
        "auto_start": true
    }
}
```

### save_settings

Update global Frame settings.

**Endpoint**: `POST /json-api/Frame/save_settings`

**Parameters**:
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| memory_limit_mb | integer | No | Default memory limit |
| max_apps_per_user | integer | No | Default max apps |
| auto_start | boolean | No | Auto-start instances |

**Response**:
```json
{
    "success": true
}
```

### packages

List resource limit packages.

**Endpoint**: `GET /json-api/Frame/packages`

**Parameters**: None

**Response**:
```json
{
    "packages": [
        {
            "name": "default",
            "memory_mb": 512,
            "cpu_percent": 100,
            "max_apps": 10
        },
        {
            "name": "premium",
            "memory_mb": 2048,
            "cpu_percent": 200,
            "max_apps": 50
        }
    ]
}
```

---

## cPanel UAPI

The cPanel UAPI is available to end users through the cPanel interface.

**Module**: `Cpanel::API::Frame`

### status

Get the current user's Frame instance status.

**Endpoint**: `GET /execute/Frame/status`

**Parameters**: None

**Response**:
```json
{
    "status": "running",
    "port": 30001,
    "memory_usage_mb": 128,
    "app_count": 3,
    "uptime": 3600
}
```

### start

Start the current user's Frame instance.

**Endpoint**: `POST /execute/Frame/start`

**Parameters**: None

**Response**:
```json
{
    "success": true,
    "port": 30001,
    "pid": 12345
}
```

### stop

Stop the current user's Frame instance.

**Endpoint**: `POST /execute/Frame/stop`

**Parameters**: None

**Response**:
```json
{
    "success": true
}
```

### restart

Restart the current user's Frame instance.

**Endpoint**: `POST /execute/Frame/restart`

**Parameters**: None

**Response**:
```json
{
    "success": true,
    "port": 30001,
    "pid": 12346
}
```

### list_apps

List the current user's Frame applications.

**Endpoint**: `GET /execute/Frame/list_apps`

**Parameters**: None

**Response**:
```json
{
    "apps": [
        {
            "name": "myapp",
            "domain": "myapp.example.com",
            "created_at": 1704067200,
            "status": "active"
        }
    ]
}
```

### deploy_app

Create a new Frame application.

**Endpoint**: `POST /execute/Frame/deploy_app`

**Parameters**:
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| name | string | Yes | Application name (lowercase, hyphens) |
| domain | string | No | Domain to assign |

**Response**:
```json
{
    "success": true,
    "name": "myapp",
    "path": "/var/frame/instances/johndoe/apps/myapp"
}
```

### delete_app

Delete a Frame application.

**Endpoint**: `POST /execute/Frame/delete_app`

**Parameters**:
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| name | string | Yes | Application name |

**Response**:
```json
{
    "success": true
}
```

### get_app

Get details for a specific application.

**Endpoint**: `GET /execute/Frame/get_app`

**Parameters**:
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| name | string | Yes | Application name |

**Response**:
```json
{
    "name": "myapp",
    "domain": "myapp.example.com",
    "created_at": 1704067200,
    "status": "active",
    "env": {
        "DATABASE_URL": "mysql://...",
        "API_KEY": "***"
    }
}
```

### update_app_domain

Update an application's domain.

**Endpoint**: `POST /execute/Frame/update_app_domain`

**Parameters**:
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| name | string | Yes | Application name |
| domain | string | Yes | New domain |

**Response**:
```json
{
    "success": true,
    "name": "myapp",
    "domain": "newdomain.example.com"
}
```

### set_env

Set an environment variable for an application.

**Endpoint**: `POST /execute/Frame/set_env`

**Parameters**:
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| name | string | Yes | Application name |
| key | string | Yes | Variable name |
| value | string | Yes | Variable value |

**Response**:
```json
{
    "success": true
}
```

### remove_env

Remove an environment variable from an application.

**Endpoint**: `POST /execute/Frame/remove_env`

**Parameters**:
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| name | string | Yes | Application name |
| key | string | Yes | Variable name |

**Response**:
```json
{
    "success": true
}
```

### logs

Get logs for the user's instance or a specific application.

**Endpoint**: `GET /execute/Frame/logs`

**Parameters**:
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| app | string | No | Application name (optional) |
| lines | integer | No | Number of lines (default: 100) |
| level | string | No | Filter by level: ERROR, WARN, INFO, DEBUG |

**Response**:
```json
{
    "logs": [
        "2024-01-01 12:00:00 INFO Application started",
        "2024-01-01 12:00:01 INFO Listening on port 30001"
    ]
}
```

---

## Manager Daemon REST API

The Frame manager daemon exposes a REST API for internal communication.

**Base URL**: `http://127.0.0.1:9500`

> **Note**: This API is only accessible from localhost for security.

### GET /api/status

Get manager daemon status.

**Response**:
```json
{
    "status": "running",
    "version": "1.0.0",
    "uptime": 86400,
    "memory_mb": 128,
    "instance_count": 15
}
```

### GET /api/instances

List all instances.

**Response**:
```json
{
    "instances": [
        {
            "user": "johndoe",
            "status": "running",
            "port": 30001,
            "pid": 12345,
            "memory_mb": 256
        }
    ]
}
```

### GET /api/instances/:user

Get a specific user's instance.

**Response**:
```json
{
    "user": "johndoe",
    "status": "running",
    "port": 30001,
    "pid": 12345,
    "memory_mb": 256,
    "apps": ["myapp", "otherapp"]
}
```

### POST /api/instances/:user/start

Start a user's instance.

**Response**:
```json
{
    "success": true,
    "port": 30001,
    "pid": 12345
}
```

### POST /api/instances/:user/stop

Stop a user's instance.

**Response**:
```json
{
    "success": true
}
```

### POST /api/instances/:user/restart

Restart a user's instance.

**Response**:
```json
{
    "success": true,
    "port": 30001,
    "pid": 12346
}
```

### GET /api/ports

List port allocations.

**Response**:
```json
{
    "range": {
        "start": 30001,
        "end": 32000
    },
    "allocated": 15,
    "available": 1985,
    "allocations": [
        {"user": "johndoe", "port": 30001},
        {"user": "janedoe", "port": 30002}
    ]
}
```

### POST /api/ports/allocate

Allocate a port for a user.

**Request**:
```json
{
    "user": "newuser"
}
```

**Response**:
```json
{
    "success": true,
    "user": "newuser",
    "port": 30016
}
```

### POST /api/ports/release

Release a user's port allocation.

**Request**:
```json
{
    "user": "olduser"
}
```

**Response**:
```json
{
    "success": true
}
```

### GET /api/health

Health check endpoint.

**Response**:
```json
{
    "status": "healthy",
    "checks": {
        "database": "ok",
        "disk": "ok",
        "memory": "ok"
    }
}
```

### GET /metrics

Prometheus metrics endpoint.

**Response** (text/plain):
```
# HELP frame_instances_total Total number of Frame instances
# TYPE frame_instances_total gauge
frame_instances_total 15

# HELP frame_instances_running Number of running instances
# TYPE frame_instances_running gauge
frame_instances_running 12

# HELP frame_memory_usage_bytes Total memory usage
# TYPE frame_memory_usage_bytes gauge
frame_memory_usage_bytes 1073741824
```

---

## Error Responses

All APIs return errors in a consistent format:

```json
{
    "success": false,
    "error": "Error message",
    "code": "ERROR_CODE"
}
```

### Common Error Codes

| Code | Description |
|------|-------------|
| `INVALID_PARAMETER` | Missing or invalid parameter |
| `USER_NOT_FOUND` | User does not exist |
| `INSTANCE_NOT_FOUND` | Instance does not exist |
| `INSTANCE_RUNNING` | Instance is already running |
| `INSTANCE_STOPPED` | Instance is already stopped |
| `APP_NOT_FOUND` | Application does not exist |
| `APP_EXISTS` | Application already exists |
| `PORT_EXHAUSTED` | No available ports |
| `PERMISSION_DENIED` | Insufficient permissions |
| `INTERNAL_ERROR` | Internal server error |

---

## Authentication

### WHM API

WHM API calls require WHM authentication. Use one of:

1. **Session Token**: Passed via `WHM-Session` header
2. **Access Hash**: Passed via `Authorization: WHM root:hash` header
3. **API Token**: Passed via `Authorization: whm root:token` header

### cPanel UAPI

cPanel UAPI calls require cPanel authentication. Use one of:

1. **Session Token**: Passed via cookies
2. **API Token**: Passed via `Authorization: cpanel user:token` header

### Manager Daemon API

The manager daemon API is restricted to localhost and does not require authentication.
