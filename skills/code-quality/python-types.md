# Python Type Organization Guide

Analyze and maintain Python type organization in Django/DRF codebases.

## What this skill does

Scans the Django codebase to identify type organization issues and maintain proper typing:

1. **Find missing type hints**: Identify functions/methods without type annotations
2. **Check Pydantic models**: Validate Pydantic model definitions
3. **Review dataclasses**: Ensure dataclasses are properly typed
4. **Validate serializers**: Check DRF serializer type consistency
5. **mypy compliance**: Identify mypy errors and typing issues

## When to use this skill

Run this skill when:
- **Adding new API endpoints** - to ensure proper type hints
- **Creating new models** - to add type annotations
- **Refactoring code** - to improve type safety
- **Before releases** - to catch typing issues
- **Setting up mypy** - to configure type checking

## Type Organization Structure

```
backend/
├── pyproject.toml          # mypy configuration
├── app/
│   ├── models/
│   │   ├── __init__.py
│   │   ├── user.py         # Django models with type hints
│   │   └── base.py         # Base model classes
│   ├── schemas/            # Pydantic schemas
│   │   ├── __init__.py
│   │   ├── user.py         # UserCreate, UserResponse
│   │   └── common.py       # Shared schemas
│   ├── serializers/        # DRF serializers
│   │   ├── __init__.py
│   │   └── user.py         # UserSerializer
│   └── types/              # Custom type definitions
│       ├── __init__.py
│       └── common.py       # TypedDict, Protocol, etc.
```

## Type Patterns

### 1. Function Type Hints

```python
# ❌ Missing type hints
def get_user(user_id):
    return User.objects.get(id=user_id)

# ✅ Proper type hints
def get_user(user_id: int) -> User:
    return User.objects.get(id=user_id)

# ✅ Optional return type
def get_user_or_none(user_id: int) -> User | None:
    return User.objects.filter(id=user_id).first()
```

### 2. Pydantic Models

```python
from pydantic import BaseModel, EmailStr
from datetime import datetime

class UserCreate(BaseModel):
    email: EmailStr
    password: str
    name: str

class UserResponse(BaseModel):
    id: int
    email: str
    name: str
    created_at: datetime

    class Config:
        from_attributes = True  # Pydantic v2
```

### 3. Django Models with Type Hints

```python
from django.db import models
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from .profile import Profile

class User(models.Model):
    email: models.EmailField = models.EmailField(unique=True)
    name: models.CharField = models.CharField(max_length=100)

    # Related manager type hint
    profile: "Profile"
```

### 4. DRF Serializers

```python
from rest_framework import serializers
from typing import Any

class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ['id', 'email', 'name']

    def validate_email(self, value: str) -> str:
        if User.objects.filter(email=value).exists():
            raise serializers.ValidationError("Email already exists")
        return value

    def create(self, validated_data: dict[str, Any]) -> User:
        return User.objects.create(**validated_data)
```

### 5. TypedDict for Complex Structures

```python
from typing import TypedDict, NotRequired

class UserDict(TypedDict):
    id: int
    email: str
    name: str
    profile: NotRequired[dict]

class PaginatedResponse(TypedDict):
    count: int
    next: str | None
    previous: str | None
    results: list[UserDict]
```

## mypy Configuration

```toml
# pyproject.toml
[tool.mypy]
python_version = "3.11"
strict = true
plugins = [
    "mypy_django_plugin.main",
    "mypy_drf_plugin.main",
]

[[tool.mypy.overrides]]
module = "*.migrations.*"
ignore_errors = true

[tool.django-stubs]
django_settings_module = "config.settings"
```

## What to Check

### ✅ Good Practices
- All public functions have type hints
- Pydantic models for request/response schemas
- TypedDict for complex dictionary structures
- mypy passes without errors
- Generic types used appropriately (list[T], dict[K, V])

### ❌ Issues to Flag
- Functions without return type hints
- `Any` used without justification
- Missing type hints on class attributes
- Inconsistent typing between serializers and schemas
- mypy errors ignored without reason

## Example Output

```
## Python Type Organization Report

### ✅ Well Typed
- app/models/user.py - All models properly typed
- app/schemas/user.py - Pydantic models complete
- app/views/user.py - All endpoints typed

### ⚠️ Issues Found

**1. Missing Type Hints**
- app/services/email.py:23 - `send_email()` missing return type
  **Fix**: Add `-> None` return type

**2. Using Any**
- app/utils/helpers.py:45 - `data: Any` should be specific
  **Fix**: Use `data: dict[str, str]` or TypedDict

**3. mypy Errors**
- app/views/auth.py:78 - Incompatible return type
  **Fix**: Return `Response` instead of `dict`

### 📊 Summary
- Total functions: 156
- Properly typed: 142 (91%)
- Missing hints: 14 (9%)
```

## Related Documentation

- [PEP 484 - Type Hints](https://peps.python.org/pep-0484/)
- [Pydantic Documentation](https://docs.pydantic.dev/)
- [mypy Documentation](https://mypy.readthedocs.io/)
- [django-stubs](https://github.com/typeddjango/django-stubs)
