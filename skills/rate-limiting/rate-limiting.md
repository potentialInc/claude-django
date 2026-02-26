---
name: rate-limiting
description: IP-based rate limiting for Django REST Framework using Redis. Use when implementing throttling, protecting against brute-force attacks, limiting API request rates, or configuring DRF throttle scopes. Covers BaseIPThrottle pattern, scope-based throttling (login/unauthenticated/authenticated), custom 429 error responses, proxy-safe IP detection, and extending with new scopes.
---

# Rate Limiting Skill - Django REST Framework

## Purpose

Provide a production-ready, IP-based rate limiting system for DRF APIs using Redis as the cache backend. This skill covers the established throttling pattern used across Potential Inc Django projects.

## When This Skill Activates

- Adding or modifying rate limits / throttle classes
- Protecting endpoints against brute-force or API abuse
- Working with `SimpleRateThrottle` or `throttle_classes`
- Configuring `DEFAULT_THROTTLE_RATES` in DRF settings
- Debugging 429 (Too Many Requests) responses

---

## Architecture

```
HTTP Request
    |
    v
DRF Throttle Check (before view executes)
    |
    +-- LoginRateThrottle        -> per-view, scope="login"
    +-- UnauthenticatedRateThrottle -> global, skips if authenticated
    +-- AuthenticatedRateThrottle   -> global, skips if unauthenticated
    |
    v
Cache Key: throttle_{scope}_{client_ip}
    |
    v
Redis Cache (check count vs rate limit)
    |
    +-- Under limit -> proceed to view
    +-- Over limit  -> 429 response via exception handler
```

**Key Design Decisions:**
- All throttles are **IP-based** (same IP shares the limit regardless of user)
- `UnauthenticatedRateThrottle` and `AuthenticatedRateThrottle` are **global defaults** that self-select based on `request.user.is_authenticated`
- `LoginRateThrottle` is **per-view only** (attached explicitly to login views)
- DRF's `get_ident()` handles `X-Forwarded-For` with `NUM_PROXIES` awareness

---

## Quick Start - New Project Setup

### Step 1: Prerequisites

Ensure Redis is configured:
```python
# core/settings/redis_settings.py (or equivalent)
CACHES = {
    "default": {
        "BACKEND": "django_redis.cache.RedisCache",
        "LOCATION": f"redis://{REDIS_HOST}:{REDIS_PORT}/{REDIS_DB}",
        "OPTIONS": {"CLIENT_CLASS": "django_redis.client.DefaultClient"},
    }
}
```

Ensure `django-redis` is in requirements:
```
django-redis>=5.0.0
redis>=5.0.0
```

### Step 2: Copy Throttle Module

Copy `core/skills/throttling.py` and `core/skills/exception_handlers.py` into your project.

### Step 3: Add DRF Settings

```python
# In REST_FRAMEWORK dict:
"DEFAULT_THROTTLE_CLASSES": [
    "core.skills.throttling.UnauthenticatedRateThrottle",
    "core.skills.throttling.AuthenticatedRateThrottle",
],
"DEFAULT_THROTTLE_RATES": {
    "login": "10/min",
    "unauthenticated": "100/min",
    "authenticated": "500/min",
},
"EXCEPTION_HANDLER": "core.skills.exception_handlers.throttle_exception_handler",
```

### Step 4: Apply Login Throttle

```python
from core.skills.throttling import LoginRateThrottle

class LoginView(TokenObtainPairView):
    throttle_classes = [LoginRateThrottle]
```

### Step 5: Add Proxy Setting

```python
# base_settings.py
NUM_PROXIES = config("NUM_PROXIES", default=1, cast=int)
```

---

## Built-in Throttle Scopes

| Scope | Rate | Applied To | Method |
|-------|------|-----------|--------|
| `login` | 10/min | Login views only | Per-view `throttle_classes` |
| `unauthenticated` | 100/min | All unauthenticated requests | Global default (auto-skips auth users) |
| `authenticated` | 500/min | All authenticated requests | Global default (auto-skips anon users) |

---

## How to Add a New Throttle Scope

### 3-Step Process

**1. Create the throttle class** in `core/skills/throttling.py`:

```python
class SignupRateThrottle(BaseIPThrottle):
    """Throttle for signup endpoints. 5 requests/hour per IP."""
    scope = "signup"
```

**2. Add the rate** in `drf_settings.py`:

```python
"DEFAULT_THROTTLE_RATES": {
    "login": "10/min",
    "unauthenticated": "100/min",
    "authenticated": "500/min",
    "signup": "5/hour",       # <-- new scope
},
```

**3. Apply to view(s)**:

```python
from core.skills.throttling import SignupRateThrottle

class RegisterView(GenericAPIView):
    throttle_classes = [SignupRateThrottle]
```

### Rate Format

DRF supports: `{number}/{period}` where period is `second`, `minute`, `hour`, `day`.

---

## Per-View Throttle Override

Override global throttles on any view:

```python
from core.skills.throttling import LoginRateThrottle

# Replace global throttles entirely for this view
class MyView(APIView):
    throttle_classes = [LoginRateThrottle]

# Disable throttling for a specific view
class HealthCheckView(APIView):
    throttle_classes = []
```

---

## Custom Exception Handler

The handler in `core/skills/exception_handlers.py` intercepts `Throttled` exceptions only:

```python
def throttle_exception_handler(exc, context):
    response = exception_handler(exc, context)
    if isinstance(exc, Throttled) and response is not None:
        wait = math.ceil(exc.wait) if exc.wait else 60
        response.data = {
            "detail": f"Request limit exceeded. Try again in {wait} seconds."
        }
    return response
```

**429 Response** (through `CustomJSONRenderer`):
```json
{
    "message": "Request limit exceeded. Try again in 30 seconds.",
    "status": "failure",
    "status_code": 429,
    "data": []
}
```

The `Retry-After` header is automatically included by DRF.

---

## Proxy & IP Safety

DRF's `SimpleRateThrottle.get_ident()` reads `X-Forwarded-For` and uses `NUM_PROXIES` to determine how many proxy hops to skip:

```python
# base_settings.py
NUM_PROXIES = config("NUM_PROXIES", default=1, cast=int)
```

| Environment | NUM_PROXIES |
|------------|-------------|
| Direct (no proxy) | 0 |
| Single nginx/LB | 1 |
| CDN + nginx | 2 |

**Do NOT trust** `X-Forwarded-For` without `NUM_PROXIES` set correctly — clients can spoof this header.

---

## Source Files

- **Throttle classes**: `backend/core/skills/throttling.py`
- **Exception handler**: `backend/core/skills/exception_handlers.py`
- **DRF config**: `backend/core/settings/drf_settings.py`
- **Proxy setting**: `backend/core/settings/base_settings.py` (`NUM_PROXIES`)
