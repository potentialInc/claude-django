# Authentication

## JWT Authentication with Simple JWT

### Installation

```bash
pip install djangorestframework-simplejwt
```

### Configuration

```python
# config/settings/base.py
from datetime import timedelta

INSTALLED_APPS = [
    # ...
    'rest_framework_simplejwt',
    'rest_framework_simplejwt.token_blacklist',  # For token refresh rotation
]

REST_FRAMEWORK = {
    'DEFAULT_AUTHENTICATION_CLASSES': [
        'rest_framework_simplejwt.authentication.JWTAuthentication',
    ],
    'DEFAULT_PERMISSION_CLASSES': [
        'rest_framework.permissions.IsAuthenticated',
    ],
}

SIMPLE_JWT = {
    'ACCESS_TOKEN_LIFETIME': timedelta(minutes=60),
    'REFRESH_TOKEN_LIFETIME': timedelta(days=7),
    'ROTATE_REFRESH_TOKENS': True,
    'BLACKLIST_AFTER_ROTATION': True,
    'UPDATE_LAST_LOGIN': True,

    'ALGORITHM': 'HS256',
    'SIGNING_KEY': SECRET_KEY,

    'AUTH_HEADER_TYPES': ('Bearer',),
    'AUTH_HEADER_NAME': 'HTTP_AUTHORIZATION',
    'USER_ID_FIELD': 'id',
    'USER_ID_CLAIM': 'user_id',

    'AUTH_TOKEN_CLASSES': ('rest_framework_simplejwt.tokens.AccessToken',),
    'TOKEN_TYPE_CLAIM': 'token_type',
}
```

### URL Configuration

```python
# apps/auth/urls.py
from django.urls import path
from rest_framework_simplejwt.views import (
    TokenObtainPairView,
    TokenRefreshView,
    TokenVerifyView,
    TokenBlacklistView,
)
from .views import RegisterView, LogoutView

urlpatterns = [
    path('login/', TokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('refresh/', TokenRefreshView.as_view(), name='token_refresh'),
    path('verify/', TokenVerifyView.as_view(), name='token_verify'),
    path('logout/', LogoutView.as_view(), name='logout'),
    path('register/', RegisterView.as_view(), name='register'),
]
```

---

## Custom Token Claims

```python
# apps/auth/serializers.py
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer

class CustomTokenObtainPairSerializer(TokenObtainPairSerializer):
    """Custom token serializer with additional claims."""

    @classmethod
    def get_token(cls, user):
        token = super().get_token(user)

        # Add custom claims
        token['name'] = user.name
        token['email'] = user.email
        token['is_staff'] = user.is_staff

        return token

    def validate(self, attrs):
        data = super().validate(attrs)

        # Add extra response data
        data['user'] = {
            'id': str(self.user.id),
            'email': self.user.email,
            'name': self.user.name,
        }

        return data
```

```python
# apps/auth/views.py
from rest_framework_simplejwt.views import TokenObtainPairView
from .serializers import CustomTokenObtainPairSerializer

class CustomTokenObtainPairView(TokenObtainPairView):
    serializer_class = CustomTokenObtainPairSerializer
```

---

## Registration View

```python
# apps/auth/views.py
from rest_framework import status
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import AllowAny
from rest_framework_simplejwt.tokens import RefreshToken
from drf_spectacular.utils import extend_schema

from .serializers import RegisterSerializer, UserSerializer

class RegisterView(APIView):
    """User registration view."""

    permission_classes = [AllowAny]

    @extend_schema(
        summary="Register new user",
        request=RegisterSerializer,
        responses={201: UserSerializer},
        tags=["Authentication"],
    )
    def post(self, request):
        serializer = RegisterSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()

        # Generate tokens for the new user
        refresh = RefreshToken.for_user(user)

        return Response({
            'user': UserSerializer(user).data,
            'tokens': {
                'refresh': str(refresh),
                'access': str(refresh.access_token),
            }
        }, status=status.HTTP_201_CREATED)
```

```python
# apps/auth/serializers.py
from rest_framework import serializers
from django.contrib.auth import get_user_model

User = get_user_model()

class RegisterSerializer(serializers.ModelSerializer):
    """Serializer for user registration."""

    password = serializers.CharField(write_only=True, min_length=8)
    password_confirm = serializers.CharField(write_only=True)

    class Meta:
        model = User
        fields = ['email', 'name', 'password', 'password_confirm']

    def validate_email(self, value):
        if User.objects.filter(email=value).exists():
            raise serializers.ValidationError("Email already registered")
        return value.lower()

    def validate(self, attrs):
        if attrs['password'] != attrs['password_confirm']:
            raise serializers.ValidationError({
                'password_confirm': "Passwords don't match"
            })
        attrs.pop('password_confirm')
        return attrs

    def create(self, validated_data):
        password = validated_data.pop('password')
        user = User.objects.create(**validated_data)
        user.set_password(password)
        user.save()
        return user
```

---

## Logout View

```python
# apps/auth/views.py
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.exceptions import TokenError

class LogoutView(APIView):
    """Logout view that blacklists the refresh token."""

    @extend_schema(
        summary="Logout user",
        request={"type": "object", "properties": {"refresh": {"type": "string"}}},
        responses={200: {"type": "object", "properties": {"detail": {"type": "string"}}}},
        tags=["Authentication"],
    )
    def post(self, request):
        try:
            refresh_token = request.data.get('refresh')
            if refresh_token:
                token = RefreshToken(refresh_token)
                token.blacklist()
            return Response({'detail': 'Successfully logged out'})
        except TokenError:
            return Response(
                {'detail': 'Invalid token'},
                status=status.HTTP_400_BAD_REQUEST
            )
```

---

## Permission Classes

### Built-in Permissions

```python
from rest_framework.permissions import (
    AllowAny,              # Anyone can access
    IsAuthenticated,       # Must be logged in
    IsAdminUser,           # Must be staff/admin
    IsAuthenticatedOrReadOnly,  # Read: anyone, Write: authenticated
)

class FeatureViewSet(viewsets.ModelViewSet):
    permission_classes = [IsAuthenticated]
```

### Custom Permissions

```python
# apps/core/permissions.py
from rest_framework import permissions

class IsOwner(permissions.BasePermission):
    """Permission to only allow owners of an object."""

    def has_object_permission(self, request, view, obj):
        return obj.user == request.user

class IsOwnerOrAdmin(permissions.BasePermission):
    """Permission for owner or admin."""

    def has_object_permission(self, request, view, obj):
        return obj.user == request.user or request.user.is_staff

class IsOwnerOrReadOnly(permissions.BasePermission):
    """Read for anyone, write only for owner."""

    def has_object_permission(self, request, view, obj):
        if request.method in permissions.SAFE_METHODS:
            return True
        return obj.user == request.user

class HasRole(permissions.BasePermission):
    """Permission based on user role."""

    def __init__(self, required_role):
        self.required_role = required_role

    def has_permission(self, request, view):
        return (
            request.user.is_authenticated and
            request.user.role == self.required_role
        )
```

### Action-Specific Permissions

```python
class FeatureViewSet(viewsets.ModelViewSet):
    permission_classes = [IsAuthenticated]

    def get_permissions(self):
        """Return different permissions based on action."""
        if self.action == 'list':
            return [AllowAny()]
        elif self.action == 'create':
            return [IsAuthenticated()]
        elif self.action in ['update', 'partial_update', 'destroy']:
            return [IsAuthenticated(), IsOwner()]
        return super().get_permissions()
```

---

## Current User

### Getting Current User in Views

```python
class FeatureViewSet(viewsets.ModelViewSet):
    def get_queryset(self):
        # Filter by current user
        return Feature.objects.filter(user=self.request.user)

    def perform_create(self, serializer):
        # Set current user on create
        serializer.save(user=self.request.user)
```

### Getting Current User in Serializers

```python
class FeatureSerializer(serializers.ModelSerializer):
    is_owner = serializers.SerializerMethodField()

    def get_is_owner(self, obj):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            return obj.user == request.user
        return False

    def create(self, validated_data):
        validated_data['user'] = self.context['request'].user
        return super().create(validated_data)
```

---

## Custom User Model

```python
# apps/users/models.py
import uuid
from django.contrib.auth.models import AbstractBaseUser, PermissionsMixin
from django.db import models
from .managers import UserManager

class User(AbstractBaseUser, PermissionsMixin):
    """Custom user model with email as username."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    email = models.EmailField(unique=True)
    name = models.CharField(max_length=100)
    is_active = models.BooleanField(default=True)
    is_staff = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    objects = UserManager()

    USERNAME_FIELD = 'email'
    REQUIRED_FIELDS = ['name']

    class Meta:
        db_table = 'users'

    def __str__(self):
        return self.email
```

```python
# apps/users/managers.py
from django.contrib.auth.base_user import BaseUserManager

class UserManager(BaseUserManager):
    """Custom user manager."""

    def create_user(self, email, password=None, **extra_fields):
        if not email:
            raise ValueError('Email is required')
        email = self.normalize_email(email)
        user = self.model(email=email, **extra_fields)
        user.set_password(password)
        user.save()
        return user

    def create_superuser(self, email, password=None, **extra_fields):
        extra_fields.setdefault('is_staff', True)
        extra_fields.setdefault('is_superuser', True)
        return self.create_user(email, password, **extra_fields)
```

```python
# config/settings/base.py
AUTH_USER_MODEL = 'users.User'
```

---

## Testing Authentication

```python
import pytest
from rest_framework.test import APIClient
from django.urls import reverse

@pytest.mark.django_db
class TestAuthentication:
    def test_login_success(self, api_client, user):
        url = reverse('token_obtain_pair')
        response = api_client.post(url, {
            'email': user.email,
            'password': 'password123'
        })
        assert response.status_code == 200
        assert 'access' in response.data
        assert 'refresh' in response.data

    def test_protected_route_without_token(self, api_client):
        url = reverse('feature-list')
        response = api_client.get(url)
        assert response.status_code == 401

    def test_protected_route_with_token(self, authenticated_client):
        url = reverse('feature-list')
        response = authenticated_client.get(url)
        assert response.status_code == 200
```

---

## Best Practices

1. **Use Simple JWT** - Industry standard for Django REST
2. **Rotate refresh tokens** - Enable `ROTATE_REFRESH_TOKENS`
3. **Blacklist old tokens** - Enable `BLACKLIST_AFTER_ROTATION`
4. **Custom user model** - Use email as username
5. **Separate permission classes** - Create reusable permission classes
6. **Add custom claims** - Include user info in token
7. **Test authentication** - Test all auth flows
