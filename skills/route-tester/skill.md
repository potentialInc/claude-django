---
name: route-tester
description: API route testing utilities for Django REST Framework. Use when testing API endpoints, debugging route issues, or verifying authentication flows. Provides patterns for pytest-django testing with authenticated requests.
---

# Route Tester Skill - Django REST Framework

## Purpose

Provide utilities and patterns for testing Django REST Framework API routes. Includes authentication helpers, request builders, and response verification utilities.

## Quick Start

### Basic Route Test

```python
import pytest
from django.urls import reverse
from rest_framework import status

@pytest.mark.django_db
def test_route(authenticated_client):
    url = reverse('feature-list')
    response = authenticated_client.get(url)
    assert response.status_code == status.HTTP_200_OK
```

### Test with Authentication

```python
@pytest.mark.django_db
def test_authenticated_route(api_client, user):
    # Get JWT tokens
    login_url = reverse('token_obtain_pair')
    response = api_client.post(login_url, {
        'email': user.email,
        'password': 'password123'
    })
    token = response.data['access']

    # Make authenticated request
    api_client.credentials(HTTP_AUTHORIZATION=f'Bearer {token}')
    url = reverse('feature-list')
    response = api_client.get(url)
    assert response.status_code == status.HTTP_200_OK
```

---

## Common Fixtures

```python
# conftest.py
import pytest
from rest_framework.test import APIClient
from apps.users.tests.factories import UserFactory

@pytest.fixture
def api_client():
    return APIClient()

@pytest.fixture
def user(db):
    return UserFactory()

@pytest.fixture
def authenticated_client(api_client, user):
    api_client.force_authenticate(user=user)
    api_client.user = user
    return api_client
```

---

## Test Patterns

### CRUD Operations

```python
@pytest.mark.django_db
class TestFeatureCRUD:
    def test_create(self, authenticated_client):
        url = reverse('feature-list')
        data = {'name': 'Test', 'description': 'Test'}
        response = authenticated_client.post(url, data)
        assert response.status_code == status.HTTP_201_CREATED

    def test_read(self, authenticated_client, feature):
        url = reverse('feature-detail', kwargs={'pk': feature.id})
        response = authenticated_client.get(url)
        assert response.status_code == status.HTTP_200_OK

    def test_update(self, authenticated_client, feature):
        url = reverse('feature-detail', kwargs={'pk': feature.id})
        response = authenticated_client.patch(url, {'name': 'Updated'})
        assert response.status_code == status.HTTP_200_OK

    def test_delete(self, authenticated_client, feature):
        url = reverse('feature-detail', kwargs={'pk': feature.id})
        response = authenticated_client.delete(url)
        assert response.status_code == status.HTTP_204_NO_CONTENT
```

### Permission Testing

```python
@pytest.mark.django_db
class TestPermissions:
    def test_unauthenticated_blocked(self, api_client):
        url = reverse('feature-list')
        response = api_client.get(url)
        assert response.status_code == status.HTTP_401_UNAUTHORIZED

    def test_other_user_blocked(self, authenticated_client, feature_factory):
        other_feature = feature_factory()  # Different user
        url = reverse('feature-detail', kwargs={'pk': other_feature.id})
        response = authenticated_client.get(url)
        assert response.status_code == status.HTTP_404_NOT_FOUND

    def test_admin_allowed(self, admin_client, feature):
        url = reverse('admin-feature-detail', kwargs={'pk': feature.id})
        response = admin_client.get(url)
        assert response.status_code == status.HTTP_200_OK
```

### Error Response Testing

```python
@pytest.mark.django_db
class TestErrorResponses:
    def test_not_found(self, authenticated_client):
        url = reverse('feature-detail', kwargs={'pk': 'invalid-uuid'})
        response = authenticated_client.get(url)
        assert response.status_code == status.HTTP_404_NOT_FOUND

    def test_validation_error(self, authenticated_client):
        url = reverse('feature-list')
        response = authenticated_client.post(url, {})  # Missing fields
        assert response.status_code == status.HTTP_400_BAD_REQUEST
        assert 'name' in response.data
```

---

## Command-Line Testing

### Using curl

```bash
# Get token
TOKEN=$(curl -s -X POST http://localhost:8000/api/auth/login/ \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"password123"}' \
  | jq -r '.access')

# List features
curl -X GET http://localhost:8000/api/features/ \
  -H "Authorization: Bearer $TOKEN"

# Create feature
curl -X POST http://localhost:8000/api/features/ \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"New Feature","description":"Test"}'
```

### Using httpie

```bash
# Get token
http POST http://localhost:8000/api/auth/login/ \
  email=user@example.com password=password123

# Authenticated request
http GET http://localhost:8000/api/features/ \
  "Authorization: Bearer $TOKEN"
```

---

## Running Tests

```bash
# All tests
pytest

# Specific app
pytest apps/feature/tests/

# With verbosity
pytest -v

# With coverage
pytest --cov=apps --cov-report=html

# Filter by name
pytest -k "create"
```
