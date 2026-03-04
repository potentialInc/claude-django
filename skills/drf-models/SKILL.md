---
name: drf-models
description: Generate Django REST Framework model code following project conventions (Service Layer Pattern, timestamps base model, PEP 8 naming, layered app structure)
argument-hint: <model description - natural language or structured>
disable-model-invocation: true
---

# DRF Model Generator

Generate Django model code from the user's description: **$ARGUMENTS**

## Workflow — FOLLOW THIS ORDER STRICTLY

### Phase 1: Understand Context

1. **Search the codebase** for existing models, apps, and related code to understand the project's current state
   - Look at existing models to understand relationships, naming patterns, and app structure
   - Check if the model already exists (update vs create)
   - Identify related models that this new model might reference or be referenced by
2. **If insufficient context is found**, interview the user using `AskUserQuestion` to gather:
   - What app does this model belong to?
   - What is the purpose/domain of this model?
   - What are the key fields and their types?
   - What relationships does it have with other models?
   - Are there any special constraints, indexes, or business rules?
   - Does it need choices/status fields? If so, what are the values?
3. **Keep asking** until you have a clear, complete picture. Do NOT guess or assume fields — ask.

### Phase 2: Design the Model

1. **Enter plan mode** using `EnterPlanMode`
2. Design the complete model in the plan file, including:
   - Model name and docstring
   - All fields with types and options
   - Choices (if any)
   - Meta class configuration
   - `__str__` method
   - Relationships and related names
   - Indexes and constraints
3. Present the design to the user via `ExitPlanMode` for approval

### Phase 3: Build

1. **Only after user approves the plan**, create or update the model files
2. Follow all conventions below
3. Remind the user to run migrations

---

## Base Model

If a `BaseModel` does not already exist in the project, create it at `<project>/core/models.py`:

```python
from django.db import models


class BaseModel(models.Model):
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        abstract = True
```

And re-export from `<project>/core/models.py`:

```python
from .base import BaseModel
```

## File Structure

Place models in the layered app structure:

```
<app_name>/
├── models/
│   ├── __init__.py      # Re-exports all models
│   └── <model_name>.py  # One model per file (snake_case filename)
```

- Filename: `snake_case` of the model name (e.g., `order_item.py` for `OrderItem`)
- Always update `__init__.py` to re-export: `from .<model_name> import <ModelName>`

## Model Conventions

### Naming
- **Model class**: `PascalCase` (e.g., `Product`, `OrderItem`)
- **Fields**: `snake_case` (e.g., `first_name`, `is_active`)
- **Related names**: plural snake_case of the model (e.g., `related_name="order_items"`)
- **Choices**: use plain list of tuples, NOT `TextChoices`/`IntegerChoices`

### Structure Template

```python
from django.db import models

from common.models import BaseModel


class ModelName(BaseModel):
    """Brief one-line description."""

    # -- Choices (if any) --
    STATUS = [
        ("active", "active"),
        ("inactive", "inactive"),
    ]

    # -- Fields --
    name = models.CharField(max_length=255)
    status = models.CharField(
        max_length=20,
        choices=STATUS,
        default="active",
    )

    class Meta:
        ordering = ["-created_at"]
        verbose_name = "Model Name"
        verbose_name_plural = "Model Names"

    def __str__(self):
        return self.name
```

### Rules
- **Always inherit from `BaseModel`** — never `models.Model` directly
- **NO soft delete** — no `is_deleted`, `deleted_at`, or custom managers for soft delete
- **Timestamps come from BaseModel** — do not add `created_at`/`updated_at` on child models
- **Choices format**: always use plain list of tuples assigned to a UPPER_CASE class attribute (e.g., `STATUS = [("active", "active")]`), never `TextChoices` or `IntegerChoices`
- **Default ordering**: `["-created_at"]` unless another field makes more sense
- **`__str__`**: always implement, return the most human-readable identifier
- **`verbose_name`**: always set both singular and plural
- **ForeignKey fields**: always set `on_delete`, `related_name`, and use descriptive field names
- **CharField**: always set `max_length`
- **DecimalField**: always set `max_digits` and `decimal_places`
- **BooleanField**: always set `default`
- **Nullable fields**: use `null=True, blank=True` only when genuinely optional; prefer `blank=True` with a default for CharFields
- **Indexes**: add for fields commonly used in filters or lookups
- **Unique constraints**: use `UniqueConstraint` over `unique=True` when naming is important

## Field Shorthand Reference

When the user uses shorthand, map to Django fields:

| Shorthand | Django Field |
|-----------|-------------|
| `str`, `string`, `char` | `CharField(max_length=255)` |
| `text` | `TextField()` |
| `int`, `integer` | `IntegerField()` |
| `bool`, `boolean` | `BooleanField(default=False)` |
| `decimal`, `money`, `price` | `DecimalField(max_digits=10, decimal_places=2)` |
| `float` | `FloatField()` |
| `date` | `DateField()` |
| `datetime` | `DateTimeField()` |
| `email` | `EmailField()` |
| `url` | `URLField()` |
| `slug` | `SlugField(unique=True)` |
| `uuid` | `UUIDField(default=uuid.uuid4, editable=False)` |
| `file` | `FileField(upload_to="<app>/<model>/")` |
| `image`, `img` | `ImageField(upload_to="<app>/<model>/")` |
| `json` | `JSONField(default=dict)` |
| `ip` | `GenericIPAddressField()` |
| `FK(<Model>)`, `fk(<Model>)` | `ForeignKey(<Model>, on_delete=models.CASCADE, related_name="<plural>")` |
| `O2O(<Model>)`, `o2o(<Model>)` | `OneToOneField(<Model>, on_delete=models.CASCADE, related_name="<singular>")` |
| `M2M(<Model>)`, `m2m(<Model>)` | `ManyToManyField(<Model>, related_name="<plural>")` |

## After Generating

- Remind the user to run `python manage.py makemigrations <app>` and `python manage.py migrate`
- If the model references other models that don't exist yet, note which ones need to be created
