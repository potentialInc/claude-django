# Claude Django

Claude Code configuration for Django REST Framework backend development. This is a framework-specific submodule designed to be used alongside `claude-base` (shared/generic config).

## Contents

### Agents
- **backend-developer.md** - End-to-end Django/DRF development from PRD to API implementation
- **auth-route-debugger.md** - Debug Django authentication and permission issues
- **auth-route-tester.md** - Test Django API routes with JWT authentication

### Skills
- **backend-dev-guidelines/** - Django REST Framework patterns with 7 resource files:
  - Architecture overview (MTV + DRF pattern)
  - Authentication (SimpleJWT setup)
  - Models and ORM (Django ORM patterns, BaseModel)
  - Serializers (DRF serializer patterns)
  - Views and URLs (ViewSet patterns, routing)
  - Testing guide (pytest-django)
  - Complete examples
- **route-tester/** - Django REST API testing patterns

### Hooks
- **mypy-check.sh** - Python type checking
- **django-test.sh** - pytest-django test runner

## Tech Stack

- Django 5.1.2
- Django REST Framework 3.15.2
- PostgreSQL 16+
- Redis 5.1.1
- Django Channels 4.1.0
- SimpleJWT 5.3.1
- drf-spectacular 0.27.2
- pytest-django

## Usage

Add as a git submodule to your project:

```bash
git submodule add https://github.com/potentialInc/claude-django.git .claude/django
```

### Project Structure

```
.claude/
├── base/      # Generic/shared config (git submodule)
├── django/    # This repo (git submodule)
├── react/     # React-specific config (git submodule) - if using React frontend
└── settings.json
```

### Update settings.json for Django hooks

```json
{
  "hooks": {
    "Stop": [
      "$CLAUDE_PROJECT_DIR/.claude/django/hooks/mypy-check.sh",
      "$CLAUDE_PROJECT_DIR/.claude/django/hooks/django-test.sh"
    ]
  }
}
```

## Related Repos

- [claude-base](https://github.com/potentialInc/claude-base) - Shared/generic Claude Code config
- [claude-react](https://github.com/potentialInc/claude-react) - React web-specific Claude Code config
- [claude-nestjs](https://github.com/potentialInc/claude-nestjs) - NestJS-specific Claude Code config
- [claude-react-native](https://github.com/potentialInc/claude-react-native) - React Native-specific Claude Code config
