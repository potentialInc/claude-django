# Testing Guide

## Setup

### Installation

```bash
pip install pytest pytest-django pytest-cov factory-boy
```

### Configuration

```python
# pytest.ini or pyproject.toml
[tool.pytest.ini_options]
DJANGO_SETTINGS_MODULE = "config.settings.test"
python_files = ["test_*.py", "*_test.py"]
python_classes = ["Test*"]
python_functions = ["test_*"]
addopts = "-v --tb=short --strict-markers"
markers = [
    "slow: marks tests as slow",
    "integration: marks tests as integration tests",
]
```

```python
# config/settings/test.py
from .base import *

DEBUG = False

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': 'test_db',
        'USER': 'postgres',
        'PASSWORD': 'postgres',
        'HOST': 'localhost',
        'PORT': '5432',
    }
}

# Faster password hashing for tests
PASSWORD_HASHERS = [
    'django.contrib.auth.hashers.MD5PasswordHasher',
]

# Disable logging during tests
LOGGING = {}
```

---

## Fixtures

### Global Fixtures

```python
# tests/conftest.py
import pytest
from rest_framework.test import APIClient
from apps.users.tests.factories import UserFactory

@pytest.fixture
def api_client():
    """Return an API client."""
    return APIClient()

@pytest.fixture
def user(db):
    """Create a test user."""
    return UserFactory()

@pytest.fixture
def authenticated_client(api_client, user):
    """Return an authenticated API client."""
    api_client.force_authenticate(user=user)
    api_client.user = user
    return api_client

@pytest.fixture
def admin_user(db):
    """Create an admin user."""
    return UserFactory(is_staff=True, is_superuser=True)

@pytest.fixture
def admin_client(api_client, admin_user):
    """Return an admin authenticated API client."""
    api_client.force_authenticate(user=admin_user)
    api_client.user = admin_user
    return api_client
```

### App-Specific Fixtures

```python
# apps/feature/tests/conftest.py
import pytest
from .factories import FeatureFactory, CategoryFactory

@pytest.fixture
def category(db):
    """Create a test category."""
    return CategoryFactory()

@pytest.fixture
def feature(db, user):
    """Create a test feature for the user."""
    return FeatureFactory(user=user)

@pytest.fixture
def feature_factory(db):
    """Return FeatureFactory for creating multiple features."""
    return FeatureFactory
```

---

## Factory Boy

### User Factory

```python
# apps/users/tests/factories.py
import factory
from django.contrib.auth import get_user_model

User = get_user_model()

class UserFactory(factory.django.DjangoModelFactory):
    """Factory for creating test users."""

    class Meta:
        model = User

    email = factory.Sequence(lambda n: f'user{n}@example.com')
    name = factory.Faker('name')
    is_active = True
    is_staff = False

    @factory.post_generation
    def password(self, create, extracted, **kwargs):
        password = extracted or 'password123'
        self.set_password(password)
        if create:
            self.save()
```

### Feature Factory

```python
# apps/feature/tests/factories.py
import factory
from apps.feature.models import Feature, Category
from apps.users.tests.factories import UserFactory

class CategoryFactory(factory.django.DjangoModelFactory):
    """Factory for creating test categories."""

    class Meta:
        model = Category

    name = factory.Sequence(lambda n: f'Category {n}')

class FeatureFactory(factory.django.DjangoModelFactory):
    """Factory for creating test features."""

    class Meta:
        model = Feature

    name = factory.Sequence(lambda n: f'Feature {n}')
    description = factory.Faker('paragraph')
    status = 'draft'
    user = factory.SubFactory(UserFactory)
    category = factory.SubFactory(CategoryFactory)

    @factory.post_generation
    def tags(self, create, extracted, **kwargs):
        if not create or not extracted:
            return
        self.tags.add(*extracted)
```

---

## API Tests

### ViewSet Tests

```python
# apps/feature/tests/test_views.py
import pytest
from django.urls import reverse
from rest_framework import status
from .factories import FeatureFactory

@pytest.mark.django_db
class TestFeatureViewSet:
    """Tests for FeatureViewSet."""

    # ========================================
    # LIST Tests
    # ========================================

    def test_list_unauthenticated(self, api_client):
        """Test listing features without authentication."""
        url = reverse('feature-list')
        response = api_client.get(url)
        assert response.status_code == status.HTTP_401_UNAUTHORIZED

    def test_list_success(self, authenticated_client, feature):
        """Test listing features."""
        url = reverse('feature-list')
        response = authenticated_client.get(url)
        assert response.status_code == status.HTTP_200_OK
        assert len(response.data) == 1

    def test_list_only_own_features(self, authenticated_client, feature_factory):
        """Test that users only see their own features."""
        # Create features for different users
        feature_factory(user=authenticated_client.user)
        feature_factory()  # Different user

        url = reverse('feature-list')
        response = authenticated_client.get(url)
        assert response.status_code == status.HTTP_200_OK
        assert len(response.data) == 1

    # ========================================
    # CREATE Tests
    # ========================================

    def test_create_success(self, authenticated_client, category):
        """Test creating a feature."""
        url = reverse('feature-list')
        data = {
            'name': 'New Feature',
            'description': 'Test description',
            'category': str(category.id),
        }
        response = authenticated_client.post(url, data)
        assert response.status_code == status.HTTP_201_CREATED
        assert response.data['name'] == 'New Feature'
        assert response.data['user'] == str(authenticated_client.user.id)

    def test_create_invalid_data(self, authenticated_client):
        """Test creating a feature with invalid data."""
        url = reverse('feature-list')
        data = {}  # Missing required fields
        response = authenticated_client.post(url, data)
        assert response.status_code == status.HTTP_400_BAD_REQUEST
        assert 'name' in response.data

    def test_create_duplicate_name(self, authenticated_client, feature):
        """Test creating a feature with duplicate name."""
        url = reverse('feature-list')
        data = {'name': feature.name}
        response = authenticated_client.post(url, data)
        assert response.status_code == status.HTTP_400_BAD_REQUEST

    # ========================================
    # RETRIEVE Tests
    # ========================================

    def test_retrieve_success(self, authenticated_client, feature):
        """Test retrieving a feature."""
        url = reverse('feature-detail', kwargs={'pk': feature.id})
        response = authenticated_client.get(url)
        assert response.status_code == status.HTTP_200_OK
        assert response.data['id'] == str(feature.id)

    def test_retrieve_not_found(self, authenticated_client):
        """Test retrieving non-existent feature."""
        url = reverse('feature-detail', kwargs={'pk': 'nonexistent-uuid'})
        response = authenticated_client.get(url)
        assert response.status_code == status.HTTP_404_NOT_FOUND

    def test_retrieve_other_user_feature(self, authenticated_client, feature_factory):
        """Test retrieving another user's feature."""
        other_feature = feature_factory()
        url = reverse('feature-detail', kwargs={'pk': other_feature.id})
        response = authenticated_client.get(url)
        assert response.status_code == status.HTTP_404_NOT_FOUND

    # ========================================
    # UPDATE Tests
    # ========================================

    def test_update_success(self, authenticated_client, feature):
        """Test updating a feature."""
        url = reverse('feature-detail', kwargs={'pk': feature.id})
        data = {'name': 'Updated Name'}
        response = authenticated_client.patch(url, data)
        assert response.status_code == status.HTTP_200_OK
        assert response.data['name'] == 'Updated Name'

    def test_update_other_user_feature(self, authenticated_client, feature_factory):
        """Test updating another user's feature."""
        other_feature = feature_factory()
        url = reverse('feature-detail', kwargs={'pk': other_feature.id})
        response = authenticated_client.patch(url, {'name': 'Hacked'})
        assert response.status_code == status.HTTP_404_NOT_FOUND

    # ========================================
    # DELETE Tests
    # ========================================

    def test_delete_success(self, authenticated_client, feature):
        """Test deleting a feature."""
        url = reverse('feature-detail', kwargs={'pk': feature.id})
        response = authenticated_client.delete(url)
        assert response.status_code == status.HTTP_204_NO_CONTENT

    def test_delete_soft_delete(self, authenticated_client, feature):
        """Test that delete is a soft delete."""
        from apps.feature.models import Feature

        url = reverse('feature-detail', kwargs={'pk': feature.id})
        authenticated_client.delete(url)

        # Should not exist in default queryset
        assert not Feature.objects.filter(pk=feature.id).exists()

        # Should exist in all_objects
        assert Feature.all_objects.filter(pk=feature.id).exists()
```

---

## Model Tests

```python
# apps/feature/tests/test_models.py
import pytest
from django.utils import timezone
from .factories import FeatureFactory

@pytest.mark.django_db
class TestFeatureModel:
    """Tests for Feature model."""

    def test_create_feature(self, user):
        """Test creating a feature."""
        from apps.feature.models import Feature

        feature = Feature.objects.create(
            name='Test Feature',
            description='Test description',
            user=user
        )
        assert feature.id is not None
        assert feature.name == 'Test Feature'
        assert feature.status == 'draft'

    def test_str_representation(self, feature):
        """Test string representation."""
        assert str(feature) == feature.name

    def test_soft_delete(self, feature):
        """Test soft delete functionality."""
        from apps.feature.models import Feature

        feature.soft_delete()
        feature.refresh_from_db()

        assert feature.deleted_at is not None
        assert not Feature.objects.filter(pk=feature.id).exists()
        assert Feature.all_objects.filter(pk=feature.id).exists()

    def test_restore(self, feature):
        """Test restore functionality."""
        from apps.feature.models import Feature

        feature.soft_delete()
        feature.restore()
        feature.refresh_from_db()

        assert feature.deleted_at is None
        assert Feature.objects.filter(pk=feature.id).exists()

    def test_manager_for_user(self, user, feature_factory):
        """Test manager for_user method."""
        from apps.feature.models import Feature

        feature_factory(user=user)
        feature_factory(user=user)
        feature_factory()  # Different user

        assert Feature.objects.for_user(user).count() == 2
```

---

## Serializer Tests

```python
# apps/feature/tests/test_serializers.py
import pytest
from apps.feature.serializers import CreateFeatureSerializer
from .factories import FeatureFactory

@pytest.mark.django_db
class TestCreateFeatureSerializer:
    """Tests for CreateFeatureSerializer."""

    def test_valid_data(self, user, category):
        """Test serializer with valid data."""
        data = {
            'name': 'Test Feature',
            'description': 'Test description',
        }
        serializer = CreateFeatureSerializer(
            data=data,
            context={'request': type('Request', (), {'user': user})()}
        )
        assert serializer.is_valid()

    def test_missing_required_field(self):
        """Test serializer with missing required field."""
        data = {'description': 'Test'}
        serializer = CreateFeatureSerializer(data=data)
        assert not serializer.is_valid()
        assert 'name' in serializer.errors

    def test_duplicate_name_validation(self, user, feature):
        """Test duplicate name validation."""
        data = {'name': feature.name}
        serializer = CreateFeatureSerializer(
            data=data,
            context={'request': type('Request', (), {'user': user})()}
        )
        assert not serializer.is_valid()
        assert 'name' in serializer.errors
```

---

## Running Tests

```bash
# Run all tests
pytest

# Run with verbose output
pytest -v

# Run specific test file
pytest apps/feature/tests/test_views.py

# Run specific test class
pytest apps/feature/tests/test_views.py::TestFeatureViewSet

# Run specific test method
pytest apps/feature/tests/test_views.py::TestFeatureViewSet::test_list_success

# Run tests matching pattern
pytest -k "create"

# Run with coverage
pytest --cov=apps --cov-report=html

# Run only failed tests from last run
pytest --lf

# Run tests in parallel (requires pytest-xdist)
pytest -n auto
```

---

## Best Practices

1. **Use pytest-django** - More Pythonic than unittest
2. **Use Factory Boy** - Clean test data creation
3. **Use fixtures** - Share setup between tests
4. **Test all actions** - list, create, retrieve, update, delete
5. **Test permissions** - Authenticated, unauthenticated, other users
6. **Test validation** - Valid data, invalid data, edge cases
7. **Test soft delete** - Verify soft delete behavior
8. **Keep tests isolated** - Each test should be independent
9. **Use meaningful names** - test_<action>_<scenario>
