# Fix Django/DRF Bug Guide

Structured approach to debugging and fixing bugs in Django REST Framework applications.

## Purpose

Use this guide when you encounter Django/DRF bugs including:
- Django ORM errors
- DRF serializer/viewset issues
- Authentication/permission errors
- Database migration problems
- API response errors (400, 401, 403, 404, 500)

## Quick Diagnostic Checklist

Before diving into debugging, quickly check:

- [ ] Django debug page (if DEBUG=True)
- [ ] Server logs (`python manage.py runserver` output)
- [ ] Database state (`python manage.py shell`)
- [ ] API response body and status code
- [ ] Authentication token/session validity
- [ ] Recent migrations (`python manage.py showmigrations`)

## Debugging Workflow

### Step 1: Reproduce the Bug

```python
# Document the reproduction steps
# 1. Send request to [endpoint]
# 2. With payload [data]
# 3. Observe [unexpected response/error]
```

### Step 2: Identify the Error Type

| Error Type | Where to Look | Tools |
|------------|---------------|-------|
| 400 Bad Request | Serializer validation | DRF browsable API |
| 401 Unauthorized | Authentication backend | Token/session check |
| 403 Forbidden | Permission classes | Permission logs |
| 404 Not Found | URL routing, queryset | URLconf, get_queryset() |
| 500 Server Error | Exception traceback | Django debug page |

### Step 3: Isolate the Problem

```python
# Add logging to trace data flow
import logging
logger = logging.getLogger(__name__)

class MyViewSet(viewsets.ModelViewSet):
    def create(self, request):
        logger.debug(f"Request data: {request.data}")
        logger.debug(f"User: {request.user}")
        # ... rest of view
```

## Common Bug Categories & Solutions

### 1. Serializer Validation Errors

**Symptoms:**
- 400 Bad Request
- Validation error messages in response

**Common Causes & Fixes:**

```python
# ❌ Missing required field
class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ['email', 'password', 'name']
        # password is required but not provided

# ✅ Make field optional or provide default
class UserSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, required=False)

# ❌ Invalid field type
{"age": "twenty"}  # Should be integer

# ✅ Add custom validation
def validate_age(self, value):
    if not isinstance(value, int):
        raise serializers.ValidationError("Age must be an integer")
    return value

# ❌ Unique constraint violation
{"email": "existing@email.com"}

# ✅ Check in validate method
def validate_email(self, value):
    if User.objects.filter(email=value).exists():
        raise serializers.ValidationError("Email already registered")
    return value
```

### 2. Authentication Errors (401)

**Symptoms:**
- 401 Unauthorized
- "Authentication credentials were not provided"

**Common Causes & Fixes:**

```python
# ❌ Missing authentication class
class MyView(APIView):
    pass  # Uses default auth which may not match client

# ✅ Explicit authentication
from rest_framework_simplejwt.authentication import JWTAuthentication

class MyView(APIView):
    authentication_classes = [JWTAuthentication]

# ❌ Token expired or invalid
# Client sending: Authorization: Bearer <expired_token>

# ✅ Check token in shell
from rest_framework_simplejwt.tokens import AccessToken
try:
    token = AccessToken(token_string)
    print(f"Valid until: {token['exp']}")
except Exception as e:
    print(f"Invalid token: {e}")

# ❌ Wrong header format
# Client: Authorization: <token>  # Missing "Bearer"

# ✅ Correct format
# Authorization: Bearer <token>
```

### 3. Permission Errors (403)

**Symptoms:**
- 403 Forbidden
- "You do not have permission to perform this action"

**Common Causes & Fixes:**

```python
# ❌ Wrong permission class
class MyViewSet(viewsets.ModelViewSet):
    permission_classes = [IsAuthenticated]
    # User is authenticated but not owner

# ✅ Custom permission
from rest_framework.permissions import BasePermission

class IsOwner(BasePermission):
    def has_object_permission(self, request, view, obj):
        return obj.user == request.user

class MyViewSet(viewsets.ModelViewSet):
    permission_classes = [IsAuthenticated, IsOwner]

# ❌ Permission not checked at object level
def get_object(self):
    return MyModel.objects.get(pk=self.kwargs['pk'])
    # Missing permission check!

# ✅ Use get_object() which checks permissions
def get_object(self):
    obj = super().get_object()  # Calls check_object_permissions
    return obj
```

### 4. ORM/Database Errors

**Symptoms:**
- DoesNotExist, MultipleObjectsReturned
- IntegrityError
- OperationalError

**Common Causes & Fixes:**

```python
# ❌ Assuming object exists
user = User.objects.get(id=999)  # DoesNotExist if not found

# ✅ Handle missing object
from django.shortcuts import get_object_or_404
user = get_object_or_404(User, id=999)

# Or use filter
user = User.objects.filter(id=999).first()
if not user:
    return Response({"error": "User not found"}, status=404)

# ❌ Multiple objects returned
user = User.objects.get(email__contains='@')  # MultipleObjectsReturned

# ✅ Use filter or add unique constraint
users = User.objects.filter(email__contains='@')

# ❌ N+1 query problem
for order in Order.objects.all():
    print(order.user.name)  # Query per iteration!

# ✅ Use select_related/prefetch_related
for order in Order.objects.select_related('user').all():
    print(order.user.name)  # Single query
```

### 5. Migration Errors

**Symptoms:**
- "No migrations to apply" but schema differs
- "Table already exists"
- Migration conflicts

**Common Causes & Fixes:**

```bash
# ❌ Migrations out of sync
python manage.py migrate
# Error: table already exists

# ✅ Fake the migration
python manage.py migrate --fake app_name 0001

# ❌ Conflicting migrations
python manage.py makemigrations
# Error: Conflicting migrations detected

# ✅ Merge migrations
python manage.py makemigrations --merge

# ❌ Missing migration
python manage.py makemigrations
# No changes detected

# ✅ Check if app is in INSTALLED_APPS
# settings.py
INSTALLED_APPS = [
    ...
    'myapp',  # Make sure it's here
]
```

## Debugging Tools

### Django Debug Toolbar

```python
# settings.py (development only)
INSTALLED_APPS = [
    ...
    'debug_toolbar',
]

MIDDLEWARE = [
    'debug_toolbar.middleware.DebugToolbarMiddleware',
    ...
]

INTERNAL_IPS = ['127.0.0.1']
```

### pytest with pdb

```python
# Run tests with debugger
pytest --pdb

# Or set breakpoint in code
def test_something():
    breakpoint()  # Drops into pdb
    result = my_function()
    assert result == expected
```

### Django Shell

```bash
# Interactive debugging
python manage.py shell_plus

# Check object
>>> User.objects.get(id=1)
>>> User.objects.filter(email__contains='test').query  # See SQL
```

### Logging Configuration

```python
# settings.py
LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'handlers': {
        'console': {
            'class': 'logging.StreamHandler',
        },
    },
    'loggers': {
        'django.db.backends': {
            'level': 'DEBUG',  # See all SQL queries
            'handlers': ['console'],
        },
        'myapp': {
            'level': 'DEBUG',
            'handlers': ['console'],
        },
    },
}
```

## After Fixing the Bug

1. **Verify the fix** - Test the reproduction steps
2. **Check for side effects** - Ensure fix doesn't break other features
3. **Run tests**: `pytest`
4. **Run linting**: `ruff check .`
5. **Run type check**: `mypy .`
6. **Create PR** - Use git workflow

## Related Resources

- [backend-dev-guidelines](../backend-dev-guidelines.md) - Django/DRF best practices
- [route-tester](../route-tester.md) - API endpoint testing
- [Django Documentation](https://docs.djangoproject.com/)
- [DRF Documentation](https://www.django-rest-framework.org/)
