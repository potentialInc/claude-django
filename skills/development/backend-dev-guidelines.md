---
name: backend-dev-guidelines
description: Comprehensive backend development guide for Django REST Framework applications. Use when creating views, serializers, models, or working with Django APIs, database access, validation, JWT authentication, or async patterns. Covers Django MTV architecture with DRF ViewSets, model managers, serializer validation, permission classes, testing strategies, and best practices. Auto-suggests pytest tests after creating new views or API endpoints.
---

# Backend Development Guidelines - Django REST Framework

## Purpose

Establish consistency and best practices for Django REST Framework applications using the **MTV pattern with ViewSets** and model managers that provide clean, maintainable code.

## When to Use This Skill

Automatically activates when working on:

- Creating or modifying views, serializers, models
- Building REST APIs with Django REST Framework
- Database operations with Django ORM
- Input validation with DRF serializers
- JWT authentication with Simple JWT
- Permission patterns
- Backend testing and refactoring
- Error handling

---

## Quick Start

### New Feature Checklist

- [ ] **Model**: Create model with proper fields and manager
- [ ] **Serializer**: Create serializers with validation
- [ ] **ViewSet**: Create ViewSet or APIView
- [ ] **URLs**: Register routes with router or path()
- [ ] **Permissions**: Apply appropriate permission classes
- [ ] **Tests**: Unit tests with pytest-django
- [ ] **Docs**: Add drf-spectacular decorators

### New Django Project Checklist

- [ ] Configure environment (.env)
- [ ] Setup virtual environment
- [ ] Run database migrations
- [ ] Create superuser
- [ ] Review core app (core/)
- [ ] Read documentation (docs/)
- [ ] Verify setup (pytest)

---

## Architecture Overview

### Django MTV + DRF Pattern

```
HTTP Request
    ↓
URL Router
    ↓
ViewSet/APIView (request handling)
    ↓
Serializer (validation & serialization)
    ↓
Model Manager (data access)
    ↓
Database (Django ORM + PostgreSQL)
```

**Key Principle:** Keep business logic in models/managers, keep views thin, use serializers for validation.

See [architecture-overview.md](../../guides/architecture-overview.md) for complete details.

---

## Directory Structure

```
artlive-backend/
├── core/                          # Project configuration
│   ├── settings/                  # Modular settings (IMPORTANT!)
│   │   ├── base_settings.py       # Base Django settings
│   │   ├── database_settings.py   # Database configuration
│   │   ├── drf_settings.py        # DRF configuration
│   │   ├── cors_settings.py       # CORS settings
│   │   ├── redis_settings.py      # Redis/cache settings
│   │   ├── email_settings.py      # Email configuration
│   │   ├── social_auth_settings.py # OAuth settings
│   │   ├── payment_settings.py    # Payment gateway settings
│   │   ├── storage_settings.py    # AWS S3 settings
│   │   └── ...
│   ├── urls.py                    # Root URL configuration
│   ├── asgi.py                    # ASGI config (WebSockets)
│   ├── wsgi.py                    # WSGI application
│   └── models.py                  # BaseModel, CompressedImageField
│
├── authentications/               # User management (NOT users/)
│   ├── models.py                  # AuthUser, UserInformation, TwoStepVerify
│   ├── views/                     # Organized by feature
│   │   ├── auth_views.py          # Login, logout
│   │   ├── profile_views.py       # Profile management
│   │   └── registration_views.py  # Registration
│   ├── serializers/               # Organized by feature
│   │   ├── user_serializers.py
│   │   └── registration_serializers.py
│   └── urls.py
│
├── experts/                       # Expert profiles & services
│   ├── models/                    # Split models
│   │   ├── expert_information.py
│   │   ├── expert_service.py
│   │   ├── expert_education.py
│   │   └── ...
│   ├── views.py
│   ├── serializers.py
│   └── urls.py
│
├── article/                       # Articles/blog
├── forum/                         # Forum/community
├── chat/                          # Real-time messaging
├── payment/                       # Payment processing
├── support/                       # Support/notifications
├── scheduling/                    # Event scheduling
├── site_settings/                 # Site configuration/taxonomy
├── service/                       # Service management
├── options/                       # Application options
│
├── utils/                         # Shared utilities
│   └── extensions/                # Custom renderers, pagination
│
├── manage.py
├── requirements.txt               # Dependencies
└── .env.dummy                     # Environment template
```

---

## Core Principles (8 Key Rules)

### 1. Use Model Managers for Complex Queries

```python
# ALWAYS: Use managers for query logic
class FeatureManager(models.Manager):
    def active(self):
        return self.filter(is_active=True, deleted_at__isnull=True)

    def for_user(self, user):
        return self.active().filter(user=user)

class Feature(BaseModel):
    objects = FeatureManager()

# Usage in views
features = Feature.objects.for_user(request.user)

# NEVER: Complex queries in views
features = Feature.objects.filter(
    is_active=True,
    deleted_at__isnull=True,
    user=request.user
)  # Wrong! Move to manager
```

### 2. Use Serializers for Validation

```python
# ALWAYS: Validation in serializers
class CreateFeatureSerializer(serializers.ModelSerializer):
    class Meta:
        model = Feature
        fields = ['name', 'description']

    def validate_name(self, value):
        if Feature.objects.filter(name=value).exists():
            raise serializers.ValidationError("Name already exists")
        return value

    def validate(self, attrs):
        # Cross-field validation
        if not attrs.get('name') and not attrs.get('description'):
            raise serializers.ValidationError("Name or description required")
        return attrs
```

### 3. Keep Views Thin

```python
# GOOD: Thin view
class FeatureViewSet(viewsets.ModelViewSet):
    serializer_class = FeatureSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return Feature.objects.for_user(self.request.user)

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)

# BAD: Fat view with business logic
class FeatureViewSet(viewsets.ModelViewSet):
    def create(self, request):
        # Don't do complex logic here!
        if Feature.objects.filter(name=request.data['name']).exists():
            return Response({"error": "exists"})
        # ... more logic
```

### 4. Use Permission Classes

```python
# ALWAYS: Use DRF permission classes
from rest_framework.permissions import IsAuthenticated, IsAdminUser

class FeatureViewSet(viewsets.ModelViewSet):
    permission_classes = [IsAuthenticated]

    def get_permissions(self):
        if self.action == 'destroy':
            return [IsAdminUser()]
        return super().get_permissions()

# Custom permissions
class IsOwner(permissions.BasePermission):
    def has_object_permission(self, request, view, obj):
        return obj.user == request.user
```

### 5. Standardized API Responses

```python
# Use DRF's Response class
from rest_framework.response import Response
from rest_framework import status

# Success response
return Response(serializer.data, status=status.HTTP_201_CREATED)

# Error response - raise exceptions, let DRF handle it
from rest_framework.exceptions import NotFound, ValidationError
raise NotFound("Feature not found")
raise ValidationError({"name": "This field is required"})
```

### 6. Error Handling

```python
# Use DRF exceptions - they're automatically handled
from rest_framework.exceptions import (
    NotFound,
    ValidationError,
    PermissionDenied,
    AuthenticationFailed,
)

# In views
def retrieve(self, request, pk=None):
    try:
        feature = Feature.objects.get(pk=pk, user=request.user)
    except Feature.DoesNotExist:
        raise NotFound("Feature not found")
    return Response(FeatureSerializer(feature).data)

# Custom exception handler (optional)
# config/exceptions.py
def custom_exception_handler(exc, context):
    response = exception_handler(exc, context)
    if response is not None:
        response.data['status_code'] = response.status_code
    return response
```

### 7. Use Django ORM Properly

```python
# GOOD: Use select_related and prefetch_related
Feature.objects.select_related('user').prefetch_related('tags').all()

# GOOD: Use F() and Q() for complex queries
from django.db.models import F, Q
Feature.objects.filter(Q(status='active') | Q(priority__gt=F('threshold')))

# GOOD: Use annotations
from django.db.models import Count
Feature.objects.annotate(tag_count=Count('tags'))

# BAD: N+1 queries
for feature in Feature.objects.all():
    print(feature.user.name)  # N+1!
```

### 8. Document with drf-spectacular

```python
from drf_spectacular.utils import extend_schema, OpenApiParameter

class FeatureViewSet(viewsets.ModelViewSet):
    @extend_schema(
        summary="List all features",
        description="Returns a list of features for the authenticated user",
        parameters=[
            OpenApiParameter(name='status', type=str, enum=['active', 'inactive']),
        ],
        responses={200: FeatureSerializer(many=True)},
        tags=['Features'],
    )
    def list(self, request):
        return super().list(request)
```

---

## Common Imports

```python
# Django
from django.db import models
from django.contrib.auth import get_user_model
from django.conf import settings

# Django REST Framework
from rest_framework import viewsets, status, serializers
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated, AllowAny
from rest_framework.exceptions import NotFound, ValidationError

# drf-spectacular
from drf_spectacular.utils import extend_schema, extend_schema_view

# Simple JWT
from rest_framework_simplejwt.authentication import JWTAuthentication

# Testing
import pytest
from rest_framework.test import APIClient
```

---

## Quick Reference

### HTTP Status Codes

| Code | Use Case     | DRF Exception |
| ---- | ------------ | ------------- |
| 200  | Success      | - |
| 201  | Created      | - |
| 204  | No Content   | - |
| 400  | Bad Request  | ValidationError |
| 401  | Unauthorized | AuthenticationFailed |
| 403  | Forbidden    | PermissionDenied |
| 404  | Not Found    | NotFound |
| 500  | Server Error | APIException |

### ViewSet Actions

| Action | HTTP Method | URL | Description |
|--------|-------------|-----|-------------|
| list | GET | /features/ | List all |
| create | POST | /features/ | Create new |
| retrieve | GET | /features/{id}/ | Get one |
| update | PUT | /features/{id}/ | Full update |
| partial_update | PATCH | /features/{id}/ | Partial update |
| destroy | DELETE | /features/{id}/ | Delete |

### Custom Actions

```python
@action(detail=True, methods=['post'])
def activate(self, request, pk=None):
    """Custom action on single object: POST /features/{id}/activate/"""
    feature = self.get_object()
    feature.activate()
    return Response({'status': 'activated'})

@action(detail=False, methods=['get'])
def recent(self, request):
    """Custom action on collection: GET /features/recent/"""
    recent = self.get_queryset().order_by('-created_at')[:5]
    serializer = self.get_serializer(recent, many=True)
    return Response(serializer.data)
```

---

## Anti-Patterns to Avoid

- Business logic in views (move to models/managers/services)
- Raw SQL queries (use Django ORM)
- Not using select_related/prefetch_related (N+1 queries)
- Validation in views (use serializers)
- Using process.env directly (use django.conf.settings)
- print() for debugging (use Python logging)
- Not using permission classes
- Forgetting @extend_schema decorators

---

## Navigation Guide

| Need to... | Read this |
|------------|-----------|
| Understand architecture | [architecture-overview.md](../../guides/architecture-overview.md) |
| Create views | [views-and-urls.md](../../guides/views-and-urls.md) |
| Work with serializers | [serializers.md](../../guides/serializers.md) |
| Database operations | [models-and-orm.md](../../guides/models-and-orm.md) |
| Validate input | [validation-patterns.md](../../guides/validation-patterns.md) |
| Add authentication | [authentication.md](../../guides/authentication.md) |
| Write tests | [testing-guide.md](../../guides/testing-guide.md) |
| See examples | [complete-examples.md](../../guides/complete-examples.md) |

---

## Commands Reference

```bash
# Development
python manage.py runserver              # Start dev server
python manage.py shell_plus             # Enhanced shell (django-extensions)

# Database
python manage.py makemigrations         # Create migrations
python manage.py migrate                # Apply migrations
python manage.py showmigrations         # Show migration status
python manage.py dbshell                # Database shell

# Testing
pytest                                  # Run all tests
pytest apps/{app}/tests/ -v            # Run app tests
pytest -k "test_create" -v             # Run specific tests
pytest --cov=apps --cov-report=html    # Coverage report

# Code Quality
mypy .                                  # Type checking
ruff check .                           # Linting
ruff format .                          # Formatting
black .                                # Alternative formatting

# API Documentation
python manage.py spectacular --file schema.yml  # Generate OpenAPI schema
```

---

## ArtLive-Specific Patterns

### BaseModel

All models inherit from `core.models.BaseModel`:

```python
from core.models import BaseModel

class Feature(BaseModel):
    # Inherits: created_at, updated_at
    name = models.CharField(max_length=255)
```

### CompressedImageField

For image fields with auto WebP conversion:

```python
from core.models import CompressedImageField

class Expert(BaseModel):
    profile_picture = CompressedImageField(quality=85, width=800)
```

### Custom JSON Renderer

All responses use `CustomJSONRenderer` with standardized format:

```json
{
    "message": "Success",
    "errors": null,
    "status": "success",
    "status_code": 200,
    "links": {"next": null, "previous": null},
    "count": 0,
    "total_pages": 0,
    "data": []
}
```

---

**Skill Status**: ArtLive Backend
**Framework**: Django 5.1.2 + DRF 3.15.2 + Python 3.11+
**Database**: PostgreSQL with Django ORM + Redis
**Features**: JWT auth, WebSockets, Toss/Authorize.net payments
**Progressive Disclosure**: 8 resource files
