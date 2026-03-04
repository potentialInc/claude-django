---
name: app-skill
description: Create a Django app with layered directory structure (models, views, serializers, services, filters, signals, docs) and feature tracking
argument-hint: [app-name]
disable-model-invocation: true
---

# Django App Creator

Create a Django app with a layered, module-based directory structure: **$ARGUMENTS**

## Workflow — FOLLOW THIS ORDER STRICTLY

### Phase 1: Understand Context

1. **Determine the app name:**
   - If `$ARGUMENTS` is provided, use it as the app name (must be `snake_case`)
   - If not provided, ask the user via `AskUserQuestion`:
     - What is the app/module name? (snake_case, e.g., `order_management`, `product_management`)
### Phase 2: Plan

1. **Enter plan mode** using `EnterPlanMode`
2. Present the full directory tree that will be created:

```
<app_name>/
├── models/
│   └── __init__.py
├── serializers/
│   └── __init__.py
├── views/
│   └── __init__.py
├── services/
│   └── __init__.py
├── filters/
│   └── __init__.py
├── signals/
│   └── __init__.py
├── docs/
│   ├── CONTEXT.md
│   ├── FEATURES.md
│   ├── MODELS.md
│   └── API.md
├── urls.py
├── admin.py
├── apps.py
└── migrations/
    └── __init__.py
```

3. Present via `ExitPlanMode` for approval

### Phase 3: Build

**Only after user approves the plan**, execute the following steps:

#### Step 1: Create the Django app
```bash
python manage.py startapp <app_name>
```

#### Step 2: Remove default files replaced by directories
Delete these files created by `startapp` (they'll be replaced by directories).
Keep `admin.py` and `apps.py` as-is:
- `<app_name>/models.py`
- `<app_name>/views.py`
- `<app_name>/tests.py`

#### Step 3: Create layered directories with `__init__.py`
Create each directory with an empty `__init__.py`:
- `<app_name>/models/__init__.py`
- `<app_name>/serializers/__init__.py`
- `<app_name>/views/__init__.py`
- `<app_name>/services/__init__.py`
- `<app_name>/filters/__init__.py`
- `<app_name>/signals/__init__.py`

#### Step 4: Create docs directory with placeholder files
- `<app_name>/docs/CONTEXT.md` — placeholder for module context (agents will populate)
```markdown
# <App Display Name>

<!-- Use the Plan Developer agent to populate this file -->
```
- `<app_name>/docs/FEATURES.md` — placeholder for feature tracking (agents will populate)
```markdown
# <App Display Name> — Features

<!-- Use the Plan Developer agent to populate this file -->
```
- `<app_name>/docs/MODELS.md` — placeholder for entity specifications (agents will populate)
```markdown
# <App Display Name> — Models

<!-- Use the Plan Developer agent to populate this file -->
```
- `<app_name>/docs/API.md` — placeholder for endpoint specifications (agents will populate)
```markdown
# <App Display Name> — API Endpoints

<!-- Use the Plan Developer agent to populate this file -->
```

#### Step 5: Create urls.py
```python
from django.urls import path
from rest_framework.routers import DefaultRouter

router = DefaultRouter()

urlpatterns = [
    
] + router.urls
```

#### Step 6: Add app to INSTALLED_APPS
- Search the codebase for `INSTALLED_APPS` to find the settings file
- Add `"<app_name>"` to the `INSTALLED_APPS` list

#### Step 7: Include app URLs in root urls.py
- Search the codebase for the root `urls.py` (the one with `api/v1/` patterns)
- Add `path("api/v1/<app_url_prefix>/", include("<app_name>.urls"))` to `urlpatterns`

---

## Rules

- App name **must** be `snake_case` (e.g., `order_management`, not `OrderManagement`)
- Every **Python** subdirectory gets an `__init__.py` (`docs/` is excluded — it's not a Python package)
- Do NOT create any model, serializer, view, or service files — only the directory structure
- Do NOT run migrations — just remind the user

## After Creating

- Inform the user the app is ready at `<app_name>/`
- Remind them to:
  1. Use the **Plan Developer agent** (Phase 3) to populate `<app_name>/docs/` with CONTEXT, FEATURES, MODELS, and API specs
  2. Use `/drf-models`, `/drf-serializers`, `/drf-views` skills to build the app code
