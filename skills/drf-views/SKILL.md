---
name: drf-views
description: Generate Django REST Framework views, viewsets, and URL routing following project conventions (service layer, filtering, custom renderer, plan-first workflow)
argument-hint: <model or view description - natural language or structured>
disable-model-invocation: true
---

# DRF View Generator

Generate DRF view code from the user's description: **$ARGUMENTS**

## Workflow — FOLLOW THIS ORDER STRICTLY

### Phase 1: Understand Context

1. **Search the codebase** to understand the current state:
   - Find the model(s) this view is for — read the model file to understand fields, relationships
   - Find existing serializers for the model — read them to understand read/write split
   - Check if views already exist for this model (auto-detect and extend/update, don't duplicate)
   - Check if services exist for the model — read them to understand available methods
   - Look at existing views in the project to follow established patterns
   - Check the app's `urls.py` for existing router registrations
2. **If insufficient context is found**, interview the user using `AskUserQuestion` to gather:
   - Which model is this view for?
   - What endpoints are needed? (CRUD, list, detail, custom actions)
   - What permissions are required? (IsAuthenticated, IsAdminUser, custom, per-action)
   - Are there custom actions beyond standard CRUD? (e.g., `/activate`, `/export`)
   - Which fields should be searchable, filterable, orderable?
   - Does a service layer exist for this model, or should one be created?
3. **Keep asking** until you have a clear, complete picture. Do NOT guess — ask.

### Phase 2: Design the Views

1. **Enter plan mode** using `EnterPlanMode`
2. Design the complete view(s) in the plan file, including:
   - View class names and types (ViewSet, APIView, generic)
   - Serializer mapping per action
   - Permission classes per action
   - Filter/search/ordering configuration
   - Service layer method calls
   - Custom actions (if any)
   - URL routing configuration
3. Present the design to the user via `ExitPlanMode` for approval

### Phase 3: Build

1. **Only after user approves the plan**, create or update the view files
2. Follow all conventions below
3. Generate/update the app's `urls.py` with router registrations
4. If existing views were found, update the file — do not create a duplicate

---

## File Structure

One file per model, all views for that model in the same file:

```
<app_name>/
├── views/
│   ├── __init__.py          # Re-exports all views
│   └── <model_name_views>.py      # All views for this model
├── urls.py                  # Router registration + urlpatterns
```

- Filename: `snake_case` of the model name
- Always update `views/__init__.py` to re-export all view classes
- Always update/create `urls.py` with router registrations

## View Types

| Type | Use Case |
|------|----------|
| `ModelViewSet` | Full CRUD for a model |
| `APIView` | Custom endpoints with manual request handling like webhooks |
| `ViewSet` | Multiple actions grouped together (e.g., dashboard stats, charts, reports) |

## ViewSet Template

```python
from django_filters.rest_framework import DjangoFilterBackend
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.filters import OrderingFilter, SearchFilter
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from <app>.models import ModelName
from <app>.serializers import (
    ModelNameDetailSerializer,
    ModelNameListSerializer,
    ModelNameSerializer,
)
from <app>.services import ModelNameService


class ModelNameViewSet(viewsets.ModelViewSet):
    """ViewSet for ModelName CRUD operations."""

    queryset = ModelName.objects.all()
    service = ModelNameService()

    # -- Filtering --
    filterset_fields = ["status", "category"]
    search_fields = ["name"]
    ordering_fields = ["name", "created_at"]
    ordering = ["-created_at"]
    # filterset_class = ModelNameFilterSet  # if using django-filter FilterSet

    def get_serializer_class(self):
        if self.action == "list":
            return ModelNameListSerializer
        if self.action == "retrieve":
            return ModelNameDetailSerializer
        return ModelNameSerializer

    def get_permissions(self):
        """Override to set per-action permissions."""
        if self.action in ["create", "update", "partial_update", "destroy"]:
            return [IsAuthenticated()]
        return super().get_permissions()

    # -- Custom Actions (via Service Layer) --

    @action(detail=True, methods=["post"], url_path="custom-action")
    def custom_action(self, request, pk=None):
        instance = self.get_object()
        result = self.service.custom_action(instance)
        serializer = self.get_serializer(result)
        return Response(serializer.data, status=status.HTTP_200_OK)
```

## APIView Template

```python
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from <app>.serializers import CustomSerializer
from <app>.services import CustomService


class CustomAPIView(APIView):
    """Custom endpoint for non-CRUD operations."""

    permission_classes = [IsAuthenticated]
    service = CustomService()

    def post(self, request):
        serializer = CustomSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        result = self.service.process(serializer.validated_data)
        return Response(
            {"message": "Operation successful", "data": result},
            status=status.HTTP_200_OK,
        )
```

## URL Routing Template

```python
from django.urls import include, path
from rest_framework.routers import DefaultRouter

from <app>.views import ModelNameViewSet, CustomAPIView

router = DefaultRouter()
router.register(r"model-names", ModelNameViewSet, basename="model-name")

urlpatterns = [
    path("", include(router.urls)),
    path("custom-endpoint/", CustomAPIView.as_view(), name="custom-endpoint"),
]
```

- URL prefix: plural `kebab-case` of the model name (e.g., `order-items`)
- Basename: singular `kebab-case` (e.g., `order-item`)
- Include in project's main `urls.py` under `/api/v1/`

---

## Conventions

### Service Layer — Custom Logic Only

**Basic CRUD** (create, update, destroy) uses DRF's default behavior — do NOT override `perform_create`, `perform_update`, `perform_destroy` unless there's custom logic beyond standard save/delete.

**Service layer** is for reusable business logic beyond CRUD — custom actions, complex operations, workflows, calculations, integrations, etc.:

```python
# CRUD — use DRF defaults (no override needed)
# Custom business logic — delegate to service
@action(detail=True, methods=["post"], url_path="activate")
def activate(self, request, pk=None):
    instance = self.get_object()
    result = self.service.activate(instance)
    serializer = self.get_serializer(result)
    return Response(serializer.data)
```

If a service doesn't exist yet for the model and custom actions are needed, note it as a prerequisite and remind the user.

### Serializer Mapping

Use `get_serializer_class()` to return the correct serializer per action:

| Action | Serializer |
|--------|------------|
| `list` | `ModelNameListSerializer` |
| `retrieve` | `ModelNameDetailSerializer` |
| `create`, `update`, `partial_update` | `ModelNameSerializer` (write) |

### Permissions — Ask Per View

Ask the user which permissions to apply. Common patterns:

```python
# Per-view class level
permission_classes = [IsAuthenticated]

# Per-action override
def get_permissions(self):
    if self.action in ["create", "update", "partial_update", "destroy"]:
        return [IsAuthenticated()]
    return [AllowAny()]
```

### Filtering, Searching, Ordering

Always include filter backends (configured globally in settings, but override per view as needed):

```python
filterset_fields = ["status", "category"]
search_fields = ["name", "description"]       # fields searchable via ?search=
ordering_fields = ["name", "created_at"]       # fields orderable via ?ordering=
ordering = ["-created_at"]                     # default ordering
# filterset_class = ModelNameFilterSet         # for complex filters
```

### Pagination

Pagination is handled globally by `CustomPagination` from `utils.extensions.custom_pagination`. No per-view override needed unless the view requires different page sizes:

```python
# Only if different from global default
pagination_class = CustomPagination
```

### Response Format

Responses are automatically wrapped by `CustomJSONRenderer` (configured in settings). Do NOT manually wrap responses in `{success, message, data, errors}` — the renderer handles it.

For custom actions that need a message:

```python
return Response(
    {"message": "Action completed", "data": serializer.data},
    status=status.HTTP_200_OK,
)
```

### Custom Actions

Use `@action` decorator for non-CRUD endpoints on ViewSets:

```python
@action(detail=True, methods=["post"], url_path="action-name")
def action_name(self, request, pk=None):
    instance = self.get_object()
    result = self.service.action_name(instance, request.data)
    return Response({"message": "Done", "data": result})

@action(detail=False, methods=["get"], url_path="action-name")
def action_name(self, request):
    result = self.service.action_name()
    serializer = self.get_serializer(result, many=True)
    return Response(serializer.data)
```

- `detail=True`: operates on a single instance (`/model-names/{pk}/action-name/`)
- `detail=False`: operates on the collection (`/model-names/action-name/`)

### QuerySet Optimization

**Always** optimize querysets with `select_related`, `prefetch_related`, and `Prefetch` to avoid N+1 queries. Analyze the model's relationships and the serializer's fields to determine what needs prefetching.

```python
from django.db.models import Prefetch

class ModelNameViewSet(viewsets.ModelViewSet):
    queryset = ModelName.objects.all()

    def get_queryset(self):
        qs = super().get_queryset()

        if self.action == "list":
            # select_related — FK and O2O (single object, JOIN)
            qs = qs.select_related("parent", "author__profile")

            # prefetch_related — M2M and reverse FK (multiple objects, separate query)
            qs = qs.prefetch_related("tags", "comments")

        elif self.action == "retrieve":
            # Detail view may need deeper prefetching
            qs = qs.select_related("parent", "author__profile")
            qs = qs.prefetch_related(
                "tags",
                "comments__author",  # nested prefetch
                # Prefetch with custom queryset for filtering/ordering
                Prefetch(
                    "items",
                    queryset=ChildModel.objects.select_related("product").order_by("-created_at"),
                ),
            )

        return qs
```

**When to use which:**

| Method | Relation Type | How It Works |
|--------|--------------|--------------|
| `select_related` | FK, O2O | SQL JOIN — single query, use for single-object relations |
| `prefetch_related` | M2M, reverse FK (O2M) | Separate query — use for multi-object relations |
| `Prefetch` | Any prefetchable | Custom queryset — use when you need to filter, order, or `select_related` on the prefetched set |

**Rules for optimization:**
- Read the serializer fields to know which relations are accessed — only prefetch what's needed
- `select_related` for FK/O2O accessed in the serializer
- `prefetch_related` for M2M/reverse FK accessed in the serializer
- Use `Prefetch` with a custom queryset when the nested serializer accesses deeper relations
- Optimize differently per action — list views may need fewer prefetches than detail views
- If `to_representation` accesses related objects, those must be prefetched too

### Role-Based QuerySet Filtering

Override `get_queryset()` to filter data based on the authenticated user's role or ownership:

```python
def get_queryset(self):
    qs = super().get_queryset()
    user = self.request.user

    # Filter by ownership
    if not user.is_staff:
        qs = qs.filter(owner=user)

    # Filter by role
    if hasattr(user, "role"):
        if user.role == "manager":
            qs = qs.filter(department=user.department)
        elif user.role == "member":
            qs = qs.filter(assigned_to=user)
        # admin/staff sees all — no filter

    # Combine with optimization
    qs = qs.select_related("parent").prefetch_related("tags")

    return qs
```

**Patterns:**
- **Ownership**: `qs.filter(owner=request.user)` — user sees only their own data
- **Department/Team**: `qs.filter(department=user.department)` — user sees team data
- **Role hierarchy**: admin sees all, manager sees department, member sees assigned
- **Always combine** role filtering with query optimization in the same `get_queryset()`
- **Never hardcode roles** — read the user model to understand the role field/choices, ask the user about the hierarchy

### Rules

- **Views are thin** — no business logic, no direct model queries beyond `get_queryset()` and `get_object()`
- **Service layer for custom logic only** — basic CRUD uses DRF defaults, services handle custom actions and reusable business logic
- **Serializer per action** — use `get_serializer_class()` to map actions to serializers
- **Import models** from `<app>.models`, serializers from `<app>.serializers`, services from `<app>.services`
- **`queryset`**: always set on ViewSet class for router introspection, even if overriding `get_queryset()`
- **`basename`**: always set in router.register for explicit URL naming
- **Naming**: `ModelNameViewSet`, `ModelNameAPIView`, `ModelNameListView`, etc.

## After Generating

- If serializers don't exist yet for this model, note they need to be created first
- If custom actions require a service and it doesn't exist yet, note it needs to be created first
- If the app's urls.py is not included in the project's main `urls.py`, remind the user to add it
- Show the final URL patterns that will be available
