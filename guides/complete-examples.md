# Complete Examples

## Full Feature Implementation

This example shows a complete feature implementation with all layers.

### 1. Model

```python
# apps/feature/models.py
import uuid
from django.db import models
from django.contrib.auth import get_user_model
from apps.core.models import BaseModel

User = get_user_model()

class FeatureManager(models.Manager):
    """Custom manager for Feature model."""

    def get_queryset(self):
        return super().get_queryset().filter(deleted_at__isnull=True)

    def active(self):
        return self.get_queryset().filter(status='active')

    def for_user(self, user):
        return self.get_queryset().filter(user=user)

    def with_related(self):
        return self.get_queryset().select_related('user', 'category').prefetch_related('tags')


class Category(BaseModel):
    """Category model for organizing features."""

    name = models.CharField(max_length=100, unique=True)
    description = models.TextField(blank=True)

    class Meta:
        db_table = 'categories'
        verbose_name_plural = 'categories'

    def __str__(self):
        return self.name


class Tag(BaseModel):
    """Tag model for labeling features."""

    name = models.CharField(max_length=50, unique=True)
    color = models.CharField(max_length=7, default='#6366f1')  # Hex color

    class Meta:
        db_table = 'tags'

    def __str__(self):
        return self.name


class Feature(BaseModel):
    """Main feature model."""

    STATUS_CHOICES = [
        ('draft', 'Draft'),
        ('active', 'Active'),
        ('archived', 'Archived'),
    ]

    name = models.CharField(max_length=100)
    description = models.TextField(blank=True)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='draft')
    priority = models.IntegerField(default=0)
    is_featured = models.BooleanField(default=False)
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='features')
    category = models.ForeignKey(Category, on_delete=models.SET_NULL, null=True, blank=True)
    tags = models.ManyToManyField(Tag, blank=True, related_name='features')

    objects = FeatureManager()

    class Meta:
        db_table = 'features'
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['status', 'user']),
        ]
        constraints = [
            models.UniqueConstraint(
                fields=['user', 'name'],
                condition=models.Q(deleted_at__isnull=True),
                name='unique_feature_name_per_user'
            ),
        ]

    def __str__(self):
        return self.name

    def activate(self):
        self.status = 'active'
        self.save(update_fields=['status', 'updated_at'])

    def archive(self):
        self.status = 'archived'
        self.save(update_fields=['status', 'updated_at'])
```

### 2. Serializers

```python
# apps/feature/serializers.py
from rest_framework import serializers
from .models import Feature, Category, Tag


class TagSerializer(serializers.ModelSerializer):
    """Serializer for Tag model."""

    class Meta:
        model = Tag
        fields = ['id', 'name', 'color']


class CategorySerializer(serializers.ModelSerializer):
    """Serializer for Category model."""

    class Meta:
        model = Category
        fields = ['id', 'name', 'description']


class FeatureSerializer(serializers.ModelSerializer):
    """Serializer for reading Feature."""

    category = CategorySerializer(read_only=True)
    tags = TagSerializer(many=True, read_only=True)
    user_name = serializers.CharField(source='user.name', read_only=True)

    class Meta:
        model = Feature
        fields = [
            'id', 'name', 'description', 'status', 'priority', 'is_featured',
            'category', 'tags', 'user', 'user_name', 'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'user', 'created_at', 'updated_at']


class CreateFeatureSerializer(serializers.ModelSerializer):
    """Serializer for creating Feature."""

    category_id = serializers.UUIDField(required=False, allow_null=True)
    tag_ids = serializers.ListField(
        child=serializers.UUIDField(),
        required=False,
        write_only=True
    )

    class Meta:
        model = Feature
        fields = ['name', 'description', 'category_id', 'tag_ids']

    def validate_name(self, value):
        user = self.context['request'].user
        if Feature.objects.filter(name=value, user=user).exists():
            raise serializers.ValidationError("You already have a feature with this name")
        return value

    def validate_category_id(self, value):
        if value and not Category.objects.filter(id=value).exists():
            raise serializers.ValidationError("Category not found")
        return value

    def create(self, validated_data):
        tag_ids = validated_data.pop('tag_ids', [])
        category_id = validated_data.pop('category_id', None)

        validated_data['user'] = self.context['request'].user
        if category_id:
            validated_data['category_id'] = category_id

        feature = Feature.objects.create(**validated_data)

        if tag_ids:
            tags = Tag.objects.filter(id__in=tag_ids)
            feature.tags.set(tags)

        return feature


class UpdateFeatureSerializer(serializers.ModelSerializer):
    """Serializer for updating Feature."""

    category_id = serializers.UUIDField(required=False, allow_null=True)
    tag_ids = serializers.ListField(
        child=serializers.UUIDField(),
        required=False,
        write_only=True
    )

    class Meta:
        model = Feature
        fields = ['name', 'description', 'status', 'priority', 'is_featured', 'category_id', 'tag_ids']

    def validate_name(self, value):
        user = self.context['request'].user
        instance = self.instance
        if Feature.objects.filter(name=value, user=user).exclude(pk=instance.pk).exists():
            raise serializers.ValidationError("You already have a feature with this name")
        return value

    def update(self, instance, validated_data):
        tag_ids = validated_data.pop('tag_ids', None)
        category_id = validated_data.pop('category_id', None)

        for attr, value in validated_data.items():
            setattr(instance, attr, value)

        if category_id is not None:
            instance.category_id = category_id

        instance.save()

        if tag_ids is not None:
            tags = Tag.objects.filter(id__in=tag_ids)
            instance.tags.set(tags)

        return instance
```

### 3. Views

```python
# apps/feature/views.py
from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from django_filters.rest_framework import DjangoFilterBackend
from rest_framework.filters import SearchFilter, OrderingFilter
from drf_spectacular.utils import extend_schema, extend_schema_view

from .models import Feature, Category, Tag
from .serializers import (
    FeatureSerializer,
    CreateFeatureSerializer,
    UpdateFeatureSerializer,
    CategorySerializer,
    TagSerializer,
)


@extend_schema_view(
    list=extend_schema(summary="List categories", tags=["Categories"]),
    retrieve=extend_schema(summary="Get category", tags=["Categories"]),
)
class CategoryViewSet(viewsets.ReadOnlyModelViewSet):
    """ViewSet for Category (read-only)."""

    queryset = Category.objects.all()
    serializer_class = CategorySerializer
    permission_classes = [IsAuthenticated]


@extend_schema_view(
    list=extend_schema(summary="List tags", tags=["Tags"]),
    retrieve=extend_schema(summary="Get tag", tags=["Tags"]),
)
class TagViewSet(viewsets.ReadOnlyModelViewSet):
    """ViewSet for Tag (read-only)."""

    queryset = Tag.objects.all()
    serializer_class = TagSerializer
    permission_classes = [IsAuthenticated]


@extend_schema_view(
    list=extend_schema(summary="List features", tags=["Features"]),
    retrieve=extend_schema(summary="Get feature", tags=["Features"]),
    create=extend_schema(summary="Create feature", tags=["Features"]),
    update=extend_schema(summary="Update feature", tags=["Features"]),
    partial_update=extend_schema(summary="Partial update feature", tags=["Features"]),
    destroy=extend_schema(summary="Delete feature", tags=["Features"]),
)
class FeatureViewSet(viewsets.ModelViewSet):
    """ViewSet for Feature CRUD operations."""

    permission_classes = [IsAuthenticated]
    filter_backends = [DjangoFilterBackend, SearchFilter, OrderingFilter]
    filterset_fields = ['status', 'category', 'is_featured']
    search_fields = ['name', 'description']
    ordering_fields = ['created_at', 'priority', 'name']
    ordering = ['-created_at']

    def get_queryset(self):
        return Feature.objects.with_related().for_user(self.request.user)

    def get_serializer_class(self):
        if self.action == 'create':
            return CreateFeatureSerializer
        elif self.action in ['update', 'partial_update']:
            return UpdateFeatureSerializer
        return FeatureSerializer

    def perform_destroy(self, instance):
        instance.soft_delete()

    @action(detail=True, methods=['post'])
    @extend_schema(summary="Activate feature", tags=["Features"])
    def activate(self, request, pk=None):
        """Activate a feature."""
        feature = self.get_object()
        feature.activate()
        return Response(FeatureSerializer(feature).data)

    @action(detail=True, methods=['post'])
    @extend_schema(summary="Archive feature", tags=["Features"])
    def archive(self, request, pk=None):
        """Archive a feature."""
        feature = self.get_object()
        feature.archive()
        return Response(FeatureSerializer(feature).data)

    @action(detail=False, methods=['get'])
    @extend_schema(summary="Get active features", tags=["Features"])
    def active(self, request):
        """Get all active features."""
        queryset = self.get_queryset().filter(status='active')
        serializer = self.get_serializer(queryset, many=True)
        return Response(serializer.data)

    @action(detail=False, methods=['get'])
    @extend_schema(summary="Get featured features", tags=["Features"])
    def featured(self, request):
        """Get all featured features."""
        queryset = self.get_queryset().filter(is_featured=True)
        serializer = self.get_serializer(queryset, many=True)
        return Response(serializer.data)
```

### 4. URLs

```python
# apps/feature/urls.py
from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import FeatureViewSet, CategoryViewSet, TagViewSet

router = DefaultRouter()
router.register(r'features', FeatureViewSet, basename='feature')
router.register(r'categories', CategoryViewSet, basename='category')
router.register(r'tags', TagViewSet, basename='tag')

urlpatterns = [
    path('', include(router.urls)),
]
```

### 5. Tests

```python
# apps/feature/tests/test_views.py
import pytest
from django.urls import reverse
from rest_framework import status
from .factories import FeatureFactory, CategoryFactory, TagFactory


@pytest.mark.django_db
class TestFeatureViewSet:
    """Tests for FeatureViewSet."""

    def test_list_features(self, authenticated_client, feature):
        url = reverse('feature-list')
        response = authenticated_client.get(url)
        assert response.status_code == status.HTTP_200_OK
        assert len(response.data) == 1

    def test_create_feature(self, authenticated_client, category):
        url = reverse('feature-list')
        data = {
            'name': 'New Feature',
            'description': 'Description',
            'category_id': str(category.id),
        }
        response = authenticated_client.post(url, data)
        assert response.status_code == status.HTTP_201_CREATED
        assert response.data['name'] == 'New Feature'

    def test_create_feature_with_tags(self, authenticated_client):
        tags = TagFactory.create_batch(2)
        url = reverse('feature-list')
        data = {
            'name': 'Tagged Feature',
            'tag_ids': [str(tag.id) for tag in tags],
        }
        response = authenticated_client.post(url, data)
        assert response.status_code == status.HTTP_201_CREATED

    def test_update_feature(self, authenticated_client, feature):
        url = reverse('feature-detail', kwargs={'pk': feature.id})
        data = {'name': 'Updated Name', 'status': 'active'}
        response = authenticated_client.patch(url, data)
        assert response.status_code == status.HTTP_200_OK
        assert response.data['name'] == 'Updated Name'
        assert response.data['status'] == 'active'

    def test_delete_feature_soft_delete(self, authenticated_client, feature):
        from apps.feature.models import Feature

        url = reverse('feature-detail', kwargs={'pk': feature.id})
        response = authenticated_client.delete(url)
        assert response.status_code == status.HTTP_204_NO_CONTENT
        assert Feature.all_objects.filter(pk=feature.id).exists()
        assert not Feature.objects.filter(pk=feature.id).exists()

    def test_activate_feature(self, authenticated_client, feature):
        url = reverse('feature-activate', kwargs={'pk': feature.id})
        response = authenticated_client.post(url)
        assert response.status_code == status.HTTP_200_OK
        assert response.data['status'] == 'active'

    def test_archive_feature(self, authenticated_client, feature):
        url = reverse('feature-archive', kwargs={'pk': feature.id})
        response = authenticated_client.post(url)
        assert response.status_code == status.HTTP_200_OK
        assert response.data['status'] == 'archived'

    def test_filter_by_status(self, authenticated_client, feature_factory):
        feature_factory(user=authenticated_client.user, status='active')
        feature_factory(user=authenticated_client.user, status='draft')
        url = reverse('feature-list')
        response = authenticated_client.get(url, {'status': 'active'})
        assert response.status_code == status.HTTP_200_OK
        assert len(response.data) == 1
        assert response.data[0]['status'] == 'active'

    def test_search_features(self, authenticated_client, feature_factory):
        feature_factory(user=authenticated_client.user, name='Searchable Feature')
        feature_factory(user=authenticated_client.user, name='Other Feature')
        url = reverse('feature-list')
        response = authenticated_client.get(url, {'search': 'Searchable'})
        assert response.status_code == status.HTTP_200_OK
        assert len(response.data) == 1
```

### 6. Factories

```python
# apps/feature/tests/factories.py
import factory
from apps.feature.models import Feature, Category, Tag
from apps.users.tests.factories import UserFactory


class CategoryFactory(factory.django.DjangoModelFactory):
    class Meta:
        model = Category

    name = factory.Sequence(lambda n: f'Category {n}')
    description = factory.Faker('paragraph')


class TagFactory(factory.django.DjangoModelFactory):
    class Meta:
        model = Tag

    name = factory.Sequence(lambda n: f'Tag {n}')
    color = factory.Faker('hex_color')


class FeatureFactory(factory.django.DjangoModelFactory):
    class Meta:
        model = Feature

    name = factory.Sequence(lambda n: f'Feature {n}')
    description = factory.Faker('paragraph')
    status = 'draft'
    priority = factory.Faker('random_int', min=0, max=10)
    is_featured = False
    user = factory.SubFactory(UserFactory)
    category = factory.SubFactory(CategoryFactory)

    @factory.post_generation
    def tags(self, create, extracted, **kwargs):
        if not create or not extracted:
            return
        self.tags.add(*extracted)
```

---

## API Endpoints Summary

| Method | URL | Description |
|--------|-----|-------------|
| GET | /api/features/ | List features |
| POST | /api/features/ | Create feature |
| GET | /api/features/{id}/ | Get feature |
| PUT | /api/features/{id}/ | Update feature |
| PATCH | /api/features/{id}/ | Partial update |
| DELETE | /api/features/{id}/ | Delete feature |
| POST | /api/features/{id}/activate/ | Activate feature |
| POST | /api/features/{id}/archive/ | Archive feature |
| GET | /api/features/active/ | List active features |
| GET | /api/features/featured/ | List featured features |
| GET | /api/categories/ | List categories |
| GET | /api/categories/{id}/ | Get category |
| GET | /api/tags/ | List tags |
| GET | /api/tags/{id}/ | Get tag |
