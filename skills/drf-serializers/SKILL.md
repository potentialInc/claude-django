---
name: drf-serializers
description: Generate Django REST Framework serializer code following project conventions (split read/write, service layer pattern, to_representation for computed fields)
argument-hint: <model or serializer description - natural language or structured>
disable-model-invocation: true
---

# DRF Serializer Generator

Generate DRF serializer code from the user's description: **$ARGUMENTS**

## Workflow — FOLLOW THIS ORDER STRICTLY

### Phase 1: Understand Context

1. **Search the codebase** to understand the current state:
   - Find the model(s) this serializer is for — read the model file to understand all fields, relationships, and choices
   - Check if serializers already exist for this model (auto-detect and extend/update, don't duplicate)
   - Look at existing serializers in the project to follow established patterns
   - Identify related models and their serializers (for nesting)
2. **If insufficient context is found**, interview the user using `AskUserQuestion` to gather:
   - Which model is this serializer for?
   - What operations are needed? (list, detail, write, or custom)
   - Which fields should be included/excluded per operation?
   - What relationships exist and what type? (FK, O2O, M2M, reverse FK)
   - For **each relationship at every nesting level**: nested serializer or PrimaryKeyRelatedField?
   - Any computed/derived fields needed in the response?
   - Should create/update logic live in the serializer or be delegated to a service?
3. **Ask about naming convention** for this specific model's serializers — do NOT assume.
4. **Keep asking** until you have a clear, complete picture. Do NOT guess — ask.

### Phase 2: Design the Serializers

1. **Enter plan mode** using `EnterPlanMode`
2. Design the complete serializer(s) in the plan file, including:
   - Serializer class names (confirmed with user)
   - Fields per serializer (read vs write)
   - Relationship handling per field (nested vs PrimaryKeyRelatedField)
   - Nested serializer definitions at every level
   - `to_representation` overrides for computed fields
   - Validation methods (field-level and object-level)
   - Create/update method placement (serializer vs service)
3. Present the design to the user via `ExitPlanMode` for approval

### Phase 3: Build

1. **Only after user approves the plan**, create or update the serializer files
2. Follow all conventions below
3. If existing serializers were found, update the file — do not create a duplicate

---

## File Structure

One file per model, all serializers for that model in the same file:

```
<app_name>/
├── serializers/
│   ├── __init__.py          # Re-exports all serializers
│   └── <model_name_serializers>.py      # All serializers for this model
```

- Filename: `snake_case` of the model name (e.g., `model_name.py` for `ModelName`)
- Always update `__init__.py` to re-export all serializer classes

## Serializer Types

| Type | Use Case |
|------|----------|
| `ModelSerializer` | Standard CRUD tied to a model |
| `Serializer` | Request/response DTOs, custom input validation, non-model data |
| `ListSerializer` | Bulk operations on collections |
| Nested serializer | Inline representation of related models (read and write) |

## Split Serializers — Read vs Write

Generate **separate serializers** for read vs write — combine create and update into a single write serializer:

```python
from rest_framework import serializers

from <app>.models import ModelName


# -- Read Serializers --

class ModelNameListSerializer(serializers.ModelSerializer):
    """Lightweight serializer for list views."""

    class Meta:
        model = ModelName
        fields = [
            "id",
            "name",
            "created_at",
        ]


class ModelNameDetailSerializer(serializers.ModelSerializer):
    """Full serializer for detail views with nested relationships."""

    related = RelatedModelSerializer(read_only=True)

    class Meta:
        model = ModelName
        fields = [
            "id",
            "name",
            "description",
            "related",
            "created_at",
            "updated_at",
        ]

    def to_representation(self, instance):
        data = super().to_representation(instance)
        data["computed_field"] = instance.some_related.count()
        return data


# -- Write Serializer --

class ModelNameSerializer(serializers.ModelSerializer):
    """Serializer for creating and updating records."""

    class Meta:
        model = ModelName
        fields = [
            "name",
            "description",
            "related",
        ]

    def validate_name(self, value):
        """Field-level validation."""
        if len(value) < 3:
            raise serializers.ValidationError("Name must be at least 3 characters.")
        return value
```

---

## Conventions

### Relationships — Ask User Per Relation

For **every relationship** (FK, O2O, M2M, reverse FK / O2M) at **every nesting level**, ask the user which approach to use. Relationships can be deeply nested — ask for each one individually.

| Relation Type | Option 1: PrimaryKeyRelatedField | Option 2: Nested Serializer |
|---------------|----------------------------------|----------------------------|
| **FK** | `serializers.PrimaryKeyRelatedField(queryset=Model.objects.all())` | `ModelSerializer()` |
| **O2O** | `serializers.PrimaryKeyRelatedField(queryset=Model.objects.all())` | `ModelSerializer()` |
| **M2M** | `serializers.PrimaryKeyRelatedField(queryset=Model.objects.all(), many=True)` | `ModelSerializer(many=True)` |
| **Reverse FK (O2M)** | N/A — typically nested | `ChildSerializer(many=True)` |
| **SlugRelatedField** | `serializers.SlugRelatedField(queryset=Model.objects.all(), slug_field="name")` | Use when referencing by a unique field other than ID |

**Read serializers**: always use nested serializers with `read_only=True` for rich representation.

### Computed Fields — Use `to_representation`

Do NOT use `SerializerMethodField`. Override `to_representation` instead:

```python
def to_representation(self, instance):
    data = super().to_representation(instance)
    data["full_name"] = f"{instance.first_name} {instance.last_name}"
    data["is_overdue"] = instance.due_date < timezone.now().date()
    return data
```

### Validation

Apply validation at **both layers**:

- **Serializer**: field-level constraints (`validate_<field>`) and cross-field validation (`validate`)
- **Service layer**: business rules, uniqueness checks that require DB queries, complex logic

```python
def validate_field_name(self, value):
    """Field-level validation."""
    if some_condition:
        raise serializers.ValidationError("Error message.")
    return value

def validate(self, attrs):
    """Cross-field validation."""
    if attrs.get("start_date") and attrs.get("end_date"):
        if attrs["start_date"] >= attrs["end_date"]:
            raise serializers.ValidationError(
                {"end_date": "End date must be after start date."}
            )
    return attrs
```

### Create/Update Logic

- **Simple CRUD**: override `create()` / `update()` directly on the serializer
- **Complex operations** (multi-model writes, side effects, notifications): delegate to the service layer

```python
# Simple — in serializer
def create(self, validated_data):
    return ModelName.objects.create(**validated_data)

# Complex — delegate to service (called from the view, NOT the serializer)
# serializer only validates, view calls: service.create_<model>(serializer.validated_data)
```

### Nested Writes — Create & Update in Same Serializer

When a model has nested children, handle **all** nested write cases in the same write serializer. This pattern applies to **any nested relation** (reverse FK, O2O, M2M):

```python
from django.db import transaction
from rest_framework import serializers

from <app>.models import ParentModel, ChildModel


class ChildModelSerializer(serializers.Serializer):
    """Nested serializer for child items — used inside ParentModelSerializer."""
    id = serializers.IntegerField(required=False)  # present = update, absent = create
    field_one = serializers.CharField(max_length=255)
    field_two = serializers.IntegerField(min_value=1)


class ParentModelSerializer(serializers.ModelSerializer):
    """Handles create and update with nested children."""

    children = ChildModelSerializer(many=True)

    class Meta:
        model = ParentModel
        fields = [
            "name",
            "description",
            "children",
        ]

    @transaction.atomic
    def create(self, validated_data):
        children_data = validated_data.pop("children")
        parent = ParentModel.objects.create(**validated_data)
        for child_data in children_data:
            ChildModel.objects.create(parent=parent, **child_data)
        return parent

    @transaction.atomic
    def update(self, instance, validated_data):
        children_data = validated_data.pop("children", None)

        # Update parent fields
        for attr, value in validated_data.items():
            setattr(instance, attr, value)
        instance.save()

        if children_data is not None:
            existing_children = {child.id: child for child in instance.children.all()}
            incoming_ids = set()

            for child_data in children_data:
                child_id = child_data.pop("id", None)

                if child_id and child_id in existing_children:
                    # Case 1: Update existing child
                    child = existing_children[child_id]
                    for attr, value in child_data.items():
                        setattr(child, attr, value)
                    child.save()
                    incoming_ids.add(child_id)
                else:
                    # Case 2: Create new child
                    new_child = ChildModel.objects.create(parent=instance, **child_data)
                    incoming_ids.add(new_child.id)

            # Case 3: Remove children not in the incoming payload
            for child_id, child in existing_children.items():
                if child_id not in incoming_ids:
                    child.delete()

        return instance
```

**Nested update must handle ALL cases:**
1. **Child has `id` and exists** → update the existing child
2. **Child has no `id`** → create a new child
3. **Existing child not in payload** → delete it (removed by user)
4. **Mixed** → update some, create others, delete the rest

### M2M Nested Write

For M2M relationships with nested serializers, the pattern differs — use `.set()` for simple ID-based or handle through-model writes:

```python
@transaction.atomic
def create(self, validated_data):
    m2m_data = validated_data.pop("m2m_field", [])
    instance = ModelName.objects.create(**validated_data)
    instance.m2m_field.set(m2m_data)  # if PrimaryKeyRelatedField
    return instance

@transaction.atomic
def update(self, instance, validated_data):
    m2m_data = validated_data.pop("m2m_field", None)
    for attr, value in validated_data.items():
        setattr(instance, attr, value)
    instance.save()
    if m2m_data is not None:
        instance.m2m_field.set(m2m_data)
    return instance
```

---

## Rules

- **No `SerializerMethodField`** — use `to_representation` for computed/derived fields
- **No drf-spectacular annotations** — API docs are a separate concern
- **`read_only_fields`**: use for fields the client should never write (`id`, `created_at`, `updated_at`)
- **`extra_kwargs`**: use for overriding field options without redefining the field
- **`fields` declaration**: use explicit `fields = [...]`, `fields = "__all__"`, or `exclude = [...]` — whichever fits best. If unsure, ask the user
- **Import models** from the app's models package — `from <app>.models import ModelName`
- **Import related serializers** from their respective app serializer files
- **Relationships**: ask user per relation (FK, O2O, M2M, reverse FK) at every nesting level whether to use nested serializer or `PrimaryKeyRelatedField`; for reads always use nested
- **`@transaction.atomic`**: always wrap `create()` and `update()` that do multi-object DB writes
- **`source` parameter**: use when the serializer field name differs from the model field

## After Generating

- If new models are referenced that don't have serializers yet, note which ones need serializers
- If views exist for this model, note that they may need updating to use the new serializers
