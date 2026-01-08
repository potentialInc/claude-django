# Views and URLs

## ViewSets

### ModelViewSet (Full CRUD)

```python
from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from drf_spectacular.utils import extend_schema, extend_schema_view

from .models import Feature
from .serializers import (
    FeatureSerializer,
    CreateFeatureSerializer,
    UpdateFeatureSerializer,
)

@extend_schema_view(
    list=extend_schema(summary="List features", tags=["Features"]),
    retrieve=extend_schema(summary="Get feature", tags=["Features"]),
    create=extend_schema(summary="Create feature", tags=["Features"]),
    update=extend_schema(summary="Update feature", tags=["Features"]),
    partial_update=extend_schema(summary="Partial update", tags=["Features"]),
    destroy=extend_schema(summary="Delete feature", tags=["Features"]),
)
class FeatureViewSet(viewsets.ModelViewSet):
    """ViewSet for Feature CRUD operations."""

    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        """Filter features by authenticated user."""
        return Feature.objects.filter(user=self.request.user)

    def get_serializer_class(self):
        """Return appropriate serializer based on action."""
        if self.action == 'create':
            return CreateFeatureSerializer
        elif self.action in ['update', 'partial_update']:
            return UpdateFeatureSerializer
        return FeatureSerializer

    def perform_create(self, serializer):
        """Set user on create."""
        serializer.save(user=self.request.user)

    @action(detail=True, methods=['post'])
    @extend_schema(summary="Activate feature", tags=["Features"])
    def activate(self, request, pk=None):
        """Custom action: POST /features/{id}/activate/"""
        feature = self.get_object()
        feature.is_active = True
        feature.save()
        return Response({'status': 'activated'})

    @action(detail=False, methods=['get'])
    @extend_schema(summary="Get recent features", tags=["Features"])
    def recent(self, request):
        """Custom action: GET /features/recent/"""
        queryset = self.get_queryset().order_by('-created_at')[:5]
        serializer = self.get_serializer(queryset, many=True)
        return Response(serializer.data)
```

### Read-Only ViewSet

```python
from rest_framework import viewsets

class CategoryViewSet(viewsets.ReadOnlyModelViewSet):
    """Read-only ViewSet (list + retrieve only)."""

    queryset = Category.objects.all()
    serializer_class = CategorySerializer
    permission_classes = [IsAuthenticated]
```

### Generic ViewSet

```python
from rest_framework import viewsets, mixins

class CreateListViewSet(
    mixins.CreateModelMixin,
    mixins.ListModelMixin,
    viewsets.GenericViewSet
):
    """ViewSet for create and list only."""
    pass
```

---

## APIViews

### Class-Based APIView

```python
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from drf_spectacular.utils import extend_schema

class ProfileView(APIView):
    """View for user profile operations."""

    permission_classes = [IsAuthenticated]

    @extend_schema(
        summary="Get current user profile",
        responses={200: UserSerializer},
        tags=["Profile"],
    )
    def get(self, request):
        serializer = UserSerializer(request.user)
        return Response(serializer.data)

    @extend_schema(
        summary="Update current user profile",
        request=UpdateUserSerializer,
        responses={200: UserSerializer},
        tags=["Profile"],
    )
    def patch(self, request):
        serializer = UpdateUserSerializer(
            request.user,
            data=request.data,
            partial=True
        )
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(UserSerializer(request.user).data)
```

### Function-Based View

```python
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from drf_spectacular.utils import extend_schema

@extend_schema(
    summary="Health check endpoint",
    responses={200: {"type": "object", "properties": {"status": {"type": "string"}}}},
    tags=["System"],
)
@api_view(['GET'])
@permission_classes([AllowAny])
def health_check(request):
    """Health check endpoint."""
    return Response({'status': 'healthy'})
```

---

## URL Configuration

### Router for ViewSets

```python
# apps/feature/urls.py
from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import FeatureViewSet, CategoryViewSet

router = DefaultRouter()
router.register(r'features', FeatureViewSet, basename='feature')
router.register(r'categories', CategoryViewSet, basename='category')

urlpatterns = [
    path('', include(router.urls)),
]
```

### Mixed URL Patterns

```python
# apps/feature/urls.py
from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import (
    FeatureViewSet,
    ProfileView,
    health_check,
)

router = DefaultRouter()
router.register(r'features', FeatureViewSet, basename='feature')

urlpatterns = [
    # ViewSet routes
    path('', include(router.urls)),

    # APIView routes
    path('profile/', ProfileView.as_view(), name='profile'),

    # Function-based routes
    path('health/', health_check, name='health-check'),
]
```

### Nested Routes

```python
# For nested resources like /features/{id}/comments/
from rest_framework_nested import routers

router = routers.DefaultRouter()
router.register(r'features', FeatureViewSet, basename='feature')

# Nested router for comments
features_router = routers.NestedDefaultRouter(router, r'features', lookup='feature')
features_router.register(r'comments', CommentViewSet, basename='feature-comments')

urlpatterns = [
    path('', include(router.urls)),
    path('', include(features_router.urls)),
]
```

---

## Permission Handling

### View-Level Permissions

```python
class FeatureViewSet(viewsets.ModelViewSet):
    permission_classes = [IsAuthenticated]
```

### Action-Level Permissions

```python
class FeatureViewSet(viewsets.ModelViewSet):
    permission_classes = [IsAuthenticated]

    def get_permissions(self):
        """Different permissions per action."""
        if self.action == 'list':
            return [AllowAny()]
        elif self.action == 'destroy':
            return [IsAdminUser()]
        return super().get_permissions()
```

### Object-Level Permissions

```python
from apps.core.permissions import IsOwner

class FeatureViewSet(viewsets.ModelViewSet):
    permission_classes = [IsAuthenticated, IsOwner]

    # IsOwner.has_object_permission() is called
    # automatically for retrieve, update, destroy
```

---

## Filtering and Ordering

### Basic Filtering

```python
from django_filters.rest_framework import DjangoFilterBackend
from rest_framework.filters import SearchFilter, OrderingFilter

class FeatureViewSet(viewsets.ModelViewSet):
    queryset = Feature.objects.all()
    serializer_class = FeatureSerializer
    filter_backends = [DjangoFilterBackend, SearchFilter, OrderingFilter]
    filterset_fields = ['status', 'category']
    search_fields = ['name', 'description']
    ordering_fields = ['created_at', 'name']
    ordering = ['-created_at']
```

### Custom FilterSet

```python
import django_filters

class FeatureFilter(django_filters.FilterSet):
    min_date = django_filters.DateFilter(field_name='created_at', lookup_expr='gte')
    max_date = django_filters.DateFilter(field_name='created_at', lookup_expr='lte')

    class Meta:
        model = Feature
        fields = ['status', 'category', 'min_date', 'max_date']

class FeatureViewSet(viewsets.ModelViewSet):
    filterset_class = FeatureFilter
```

---

## Pagination

### Page Number Pagination

```python
from rest_framework.pagination import PageNumberPagination

class StandardPagination(PageNumberPagination):
    page_size = 20
    page_size_query_param = 'page_size'
    max_page_size = 100

class FeatureViewSet(viewsets.ModelViewSet):
    pagination_class = StandardPagination
```

### Cursor Pagination (for infinite scroll)

```python
from rest_framework.pagination import CursorPagination

class FeatureCursorPagination(CursorPagination):
    page_size = 20
    ordering = '-created_at'
```

---

## Error Handling

### Raising Exceptions

```python
from rest_framework.exceptions import (
    NotFound,
    ValidationError,
    PermissionDenied,
)

class FeatureViewSet(viewsets.ModelViewSet):
    def retrieve(self, request, pk=None):
        try:
            feature = Feature.objects.get(pk=pk)
        except Feature.DoesNotExist:
            raise NotFound("Feature not found")

        if feature.user != request.user:
            raise PermissionDenied("You don't have access to this feature")

        serializer = self.get_serializer(feature)
        return Response(serializer.data)
```

### Custom Exception Handler

```python
# apps/core/exceptions.py
from rest_framework.views import exception_handler

def custom_exception_handler(exc, context):
    response = exception_handler(exc, context)

    if response is not None:
        response.data['status_code'] = response.status_code

        # Add request ID for debugging
        if hasattr(context.get('request'), 'id'):
            response.data['request_id'] = context['request'].id

    return response
```

---

## Best Practices

1. **Use ViewSets for CRUD** - Less code, automatic URL routing
2. **Use APIView for custom logic** - When ViewSet doesn't fit
3. **Get serializer class dynamically** - Different serializers for different actions
4. **Override get_queryset()** - Filter by user, apply permissions
5. **Use perform_create/update** - Add user, timestamps, etc.
6. **Document with drf-spectacular** - Add @extend_schema decorators
7. **Handle errors with exceptions** - Let DRF convert to HTTP responses
