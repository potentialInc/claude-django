# Architecture Overview

## Django REST Framework Architecture

### MTV + ViewSets Pattern

Django REST Framework extends Django's MTV (Model-Template-View) pattern with serializers and ViewSets for building APIs.

```
Request Flow:
┌─────────────────────────────────────────────────────────────────┐
│                          HTTP Request                            │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                         URL Router                               │
│  • DefaultRouter for ViewSets                                    │
│  • path() for function-based views                               │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Authentication                              │
│  • JWTAuthentication                                             │
│  • Token validation                                              │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Permission Check                            │
│  • IsAuthenticated                                               │
│  • Custom permissions                                            │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                    ViewSet / APIView                             │
│  • Request handling                                              │
│  • Action routing (list, create, retrieve, etc.)                │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Serializer                                │
│  • Request validation                                            │
│  • Data deserialization                                          │
│  • Response serialization                                        │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Model / Manager                              │
│  • Business logic                                                │
│  • Data access patterns                                          │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Django ORM                                  │
│  • QuerySet operations                                           │
│  • Database transactions                                         │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                       Database                                   │
│  • PostgreSQL                                                    │
└─────────────────────────────────────────────────────────────────┘
```

---

## Project Structure

### Recommended Layout

```
backend/
├── config/                    # Project configuration
│   ├── __init__.py
│   ├── settings/
│   │   ├── __init__.py
│   │   ├── base.py           # Shared settings
│   │   ├── development.py    # Dev-specific
│   │   ├── production.py     # Prod-specific
│   │   └── test.py           # Test-specific
│   ├── urls.py               # Root URL config
│   ├── wsgi.py
│   └── asgi.py
│
├── apps/                      # Django applications
│   ├── __init__.py
│   ├── core/                  # Shared utilities
│   │   ├── __init__.py
│   │   ├── models.py         # BaseModel
│   │   ├── views.py          # Base views
│   │   ├── serializers.py    # Base serializers
│   │   ├── permissions.py    # Custom permissions
│   │   ├── exceptions.py     # Custom exceptions
│   │   └── pagination.py     # Custom pagination
│   │
│   ├── users/                 # User management
│   │   ├── __init__.py
│   │   ├── admin.py
│   │   ├── apps.py
│   │   ├── models.py
│   │   ├── managers.py
│   │   ├── serializers.py
│   │   ├── views.py
│   │   ├── urls.py
│   │   ├── signals.py
│   │   └── tests/
│   │       ├── __init__.py
│   │       ├── test_models.py
│   │       ├── test_views.py
│   │       └── factories.py
│   │
│   └── {feature}/            # Feature-specific apps
│
├── tests/                     # Global test utilities
│   ├── __init__.py
│   ├── conftest.py           # Shared fixtures
│   └── factories/            # Shared factories
│
├── manage.py
├── requirements/
│   ├── base.txt
│   ├── development.txt
│   └── production.txt
├── pyproject.toml
└── .env.example
```

---

## Core Components

### BaseModel

```python
# apps/core/models.py
import uuid
from django.db import models

class BaseManager(models.Manager):
    def get_queryset(self):
        return super().get_queryset().filter(deleted_at__isnull=True)

class BaseModel(models.Model):
    """Abstract base model with common fields."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    deleted_at = models.DateTimeField(null=True, blank=True)

    objects = BaseManager()
    all_objects = models.Manager()  # Include soft-deleted

    class Meta:
        abstract = True
        ordering = ['-created_at']

    def soft_delete(self):
        from django.utils import timezone
        self.deleted_at = timezone.now()
        self.save(update_fields=['deleted_at'])
```

### Base Serializers

```python
# apps/core/serializers.py
from rest_framework import serializers

class BaseModelSerializer(serializers.ModelSerializer):
    """Base serializer with common fields."""

    class Meta:
        read_only_fields = ['id', 'created_at', 'updated_at']

class TimestampMixin(serializers.Serializer):
    """Mixin for timestamp fields."""
    created_at = serializers.DateTimeField(read_only=True)
    updated_at = serializers.DateTimeField(read_only=True)
```

### Custom Permissions

```python
# apps/core/permissions.py
from rest_framework import permissions

class IsOwner(permissions.BasePermission):
    """Object-level permission to only allow owners."""

    def has_object_permission(self, request, view, obj):
        return obj.user == request.user

class IsOwnerOrReadOnly(permissions.BasePermission):
    """Allow read to anyone, write only to owner."""

    def has_object_permission(self, request, view, obj):
        if request.method in permissions.SAFE_METHODS:
            return True
        return obj.user == request.user

class IsAdminOrReadOnly(permissions.BasePermission):
    """Allow read to anyone, write only to admin."""

    def has_permission(self, request, view):
        if request.method in permissions.SAFE_METHODS:
            return True
        return request.user and request.user.is_staff
```

---

## Django Apps Pattern

### Creating a New App

```bash
# Create app in apps directory
cd backend/apps
python ../manage.py startapp feature
```

### App Structure

```python
# apps/feature/apps.py
from django.apps import AppConfig

class FeatureConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'apps.feature'
    verbose_name = 'Feature Management'

    def ready(self):
        import apps.feature.signals  # noqa
```

```python
# config/settings/base.py
INSTALLED_APPS = [
    # Django
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',

    # Third-party
    'rest_framework',
    'rest_framework_simplejwt',
    'corsheaders',
    'drf_spectacular',

    # Local apps
    'apps.core',
    'apps.users',
    'apps.auth',
    'apps.feature',
]
```

---

## URL Configuration

### Root URLs

```python
# config/urls.py
from django.contrib import admin
from django.urls import path, include
from drf_spectacular.views import SpectacularAPIView, SpectacularSwaggerView

urlpatterns = [
    path('admin/', admin.site.urls),

    # API routes
    path('api/', include([
        path('auth/', include('apps.auth.urls')),
        path('users/', include('apps.users.urls')),
        path('features/', include('apps.feature.urls')),
    ])),

    # API documentation
    path('api/schema/', SpectacularAPIView.as_view(), name='schema'),
    path('api/docs/', SpectacularSwaggerView.as_view(url_name='schema'), name='swagger-ui'),
]
```

### App URLs with Router

```python
# apps/feature/urls.py
from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import FeatureViewSet

router = DefaultRouter()
router.register(r'', FeatureViewSet, basename='feature')

urlpatterns = [
    path('', include(router.urls)),
]
```

---

## Settings Configuration

### Base Settings

```python
# config/settings/base.py
import os
from pathlib import Path
from datetime import timedelta

BASE_DIR = Path(__file__).resolve().parent.parent.parent

SECRET_KEY = os.getenv('SECRET_KEY')
DEBUG = False

# REST Framework
REST_FRAMEWORK = {
    'DEFAULT_AUTHENTICATION_CLASSES': [
        'rest_framework_simplejwt.authentication.JWTAuthentication',
    ],
    'DEFAULT_PERMISSION_CLASSES': [
        'rest_framework.permissions.IsAuthenticated',
    ],
    'DEFAULT_PAGINATION_CLASS': 'rest_framework.pagination.PageNumberPagination',
    'PAGE_SIZE': 20,
    'DEFAULT_SCHEMA_CLASS': 'drf_spectacular.openapi.AutoSchema',
    'EXCEPTION_HANDLER': 'apps.core.exceptions.custom_exception_handler',
}

# Simple JWT
SIMPLE_JWT = {
    'ACCESS_TOKEN_LIFETIME': timedelta(minutes=60),
    'REFRESH_TOKEN_LIFETIME': timedelta(days=7),
    'ROTATE_REFRESH_TOKENS': True,
    'BLACKLIST_AFTER_ROTATION': True,
    'AUTH_HEADER_TYPES': ('Bearer',),
}

# drf-spectacular
SPECTACULAR_SETTINGS = {
    'TITLE': 'API Documentation',
    'DESCRIPTION': 'Django REST Framework API',
    'VERSION': '1.0.0',
    'SERVE_INCLUDE_SCHEMA': False,
}
```

### Development Settings

```python
# config/settings/development.py
from .base import *

DEBUG = True

ALLOWED_HOSTS = ['localhost', '127.0.0.1']

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': os.getenv('DB_NAME', 'app_dev'),
        'USER': os.getenv('DB_USER', 'postgres'),
        'PASSWORD': os.getenv('DB_PASSWORD', 'postgres'),
        'HOST': os.getenv('DB_HOST', 'localhost'),
        'PORT': os.getenv('DB_PORT', '5432'),
    }
}

# CORS for development
CORS_ALLOW_ALL_ORIGINS = True
```

---

## Best Practices Summary

1. **Use apps for feature separation** - Each feature gets its own Django app
2. **Centralize shared code in core app** - Base models, permissions, utilities
3. **Use model managers for queries** - Keep query logic in managers
4. **Thin views, fat models** - Business logic in models/managers
5. **Serializers for validation** - All input validation in serializers
6. **Permission classes for auth** - Use DRF permission classes
7. **Document with drf-spectacular** - Add OpenAPI decorators
8. **Test with pytest-django** - Use fixtures and factories
