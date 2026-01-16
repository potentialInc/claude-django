# pytest Fixtures Guide for Django

Test data and fixture management for Django/DRF with pytest.

## Table of Contents

- [pytest-django Setup](#pytest-django-setup)
- [Authentication Fixtures](#authentication-fixtures)
- [Factory Boy Integration](#factory-boy-integration)
- [Database Fixtures](#database-fixtures)
- [API Client Fixtures](#api-client-fixtures)
- [Best Practices](#best-practices)

---

## pytest-django Setup

### Installation

```bash
pip install pytest pytest-django factory-boy
```

### Configuration

```python
# pytest.ini or pyproject.toml
[tool.pytest.ini_options]
DJANGO_SETTINGS_MODULE = "config.settings.test"
python_files = ["test_*.py", "*_test.py"]
addopts = "-v --tb=short"
```

### conftest.py Structure

```
backend/
├── conftest.py              # Root fixtures
├── app/
│   ├── tests/
│   │   ├── conftest.py      # App-specific fixtures
│   │   ├── factories.py     # Factory Boy factories
│   │   └── test_views.py
```

---

## Authentication Fixtures

### Basic Auth Fixtures

```python
# conftest.py
import pytest
from django.contrib.auth import get_user_model
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

User = get_user_model()

@pytest.fixture
def api_client():
    """Unauthenticated API client."""
    return APIClient()

@pytest.fixture
def user(db):
    """Create a regular user."""
    return User.objects.create_user(
        email='user@example.com',
        password='testpass123',
        name='Test User'
    )

@pytest.fixture
def admin_user(db):
    """Create an admin user."""
    return User.objects.create_superuser(
        email='admin@example.com',
        password='adminpass123',
        name='Admin User'
    )

@pytest.fixture
def auth_client(api_client, user):
    """Authenticated API client with regular user."""
    refresh = RefreshToken.for_user(user)
    api_client.credentials(HTTP_AUTHORIZATION=f'Bearer {refresh.access_token}')
    return api_client

@pytest.fixture
def admin_client(api_client, admin_user):
    """Authenticated API client with admin user."""
    refresh = RefreshToken.for_user(admin_user)
    api_client.credentials(HTTP_AUTHORIZATION=f'Bearer {refresh.access_token}')
    return api_client
```

### Usage in Tests

```python
# test_views.py
import pytest
from django.urls import reverse

@pytest.mark.django_db
class TestUserAPI:
    def test_list_users_unauthenticated(self, api_client):
        """Unauthenticated users cannot list users."""
        url = reverse('user-list')
        response = api_client.get(url)
        assert response.status_code == 401

    def test_list_users_authenticated(self, auth_client):
        """Authenticated users can list users."""
        url = reverse('user-list')
        response = auth_client.get(url)
        assert response.status_code == 200

    def test_admin_can_delete_user(self, admin_client, user):
        """Admin can delete users."""
        url = reverse('user-detail', kwargs={'pk': user.pk})
        response = admin_client.delete(url)
        assert response.status_code == 204
```

---

## Factory Boy Integration

### Basic Factories

```python
# app/tests/factories.py
import factory
from factory.django import DjangoModelFactory
from django.contrib.auth import get_user_model

User = get_user_model()

class UserFactory(DjangoModelFactory):
    class Meta:
        model = User

    email = factory.Sequence(lambda n: f'user{n}@example.com')
    name = factory.Faker('name')
    password = factory.PostGenerationMethodCall('set_password', 'testpass123')
    is_active = True

class AdminFactory(UserFactory):
    is_staff = True
    is_superuser = True
    email = factory.Sequence(lambda n: f'admin{n}@example.com')
```

### Related Model Factories

```python
# factories.py
class ProfileFactory(DjangoModelFactory):
    class Meta:
        model = Profile

    user = factory.SubFactory(UserFactory)
    bio = factory.Faker('paragraph')
    avatar = factory.django.ImageField(color='blue')

class PostFactory(DjangoModelFactory):
    class Meta:
        model = Post

    author = factory.SubFactory(UserFactory)
    title = factory.Faker('sentence')
    content = factory.Faker('paragraphs', nb=3)
    status = 'published'

    @factory.post_generation
    def tags(self, create, extracted, **kwargs):
        if not create:
            return
        if extracted:
            for tag in extracted:
                self.tags.add(tag)
```

### Factory Fixtures

```python
# conftest.py
import pytest
from app.tests.factories import UserFactory, PostFactory

@pytest.fixture
def user_factory():
    """Return UserFactory for creating multiple users."""
    return UserFactory

@pytest.fixture
def post_factory():
    """Return PostFactory for creating posts."""
    return PostFactory

@pytest.fixture
def user_with_posts(user_factory, post_factory):
    """Create user with multiple posts."""
    user = user_factory()
    posts = post_factory.create_batch(5, author=user)
    return user, posts
```

### Usage with Factories

```python
@pytest.mark.django_db
class TestPostAPI:
    def test_list_user_posts(self, auth_client, user, post_factory):
        """User can list their own posts."""
        post_factory.create_batch(3, author=user)

        url = reverse('post-list')
        response = auth_client.get(url)

        assert response.status_code == 200
        assert len(response.data) == 3

    def test_bulk_create_users(self, user_factory):
        """Create multiple users."""
        users = user_factory.create_batch(10)
        assert User.objects.count() == 10
```

---

## Database Fixtures

### Transaction Management

```python
# conftest.py
import pytest

@pytest.fixture
def db_with_data(db):
    """Fixture that sets up common test data."""
    from app.tests.factories import UserFactory, CategoryFactory

    # Create base data
    UserFactory.create_batch(5)
    CategoryFactory.create_batch(3)

    yield

    # Cleanup happens automatically with pytest-django

@pytest.fixture(scope='session')
def django_db_setup(django_db_setup, django_db_blocker):
    """Load initial data once per test session."""
    with django_db_blocker.unblock():
        from django.core.management import call_command
        call_command('loaddata', 'initial_data.json')
```

### Fixture Scopes

```python
# conftest.py

@pytest.fixture(scope='function')  # Default - new for each test
def fresh_user():
    return UserFactory()

@pytest.fixture(scope='class')  # Shared within test class
def shared_user():
    return UserFactory()

@pytest.fixture(scope='module')  # Shared within module
def module_user():
    return UserFactory()

@pytest.fixture(scope='session')  # Shared across all tests
def session_data(django_db_blocker):
    with django_db_blocker.unblock():
        return UserFactory()
```

---

## API Client Fixtures

### Custom API Client

```python
# conftest.py
from rest_framework.test import APIClient

class AuthenticatedAPIClient(APIClient):
    """API client with helper methods."""

    def authenticate_as(self, user):
        """Authenticate as specific user."""
        from rest_framework_simplejwt.tokens import RefreshToken
        refresh = RefreshToken.for_user(user)
        self.credentials(HTTP_AUTHORIZATION=f'Bearer {refresh.access_token}')
        return self

    def logout(self):
        """Clear authentication."""
        self.credentials()
        return self

@pytest.fixture
def client():
    """Enhanced API client."""
    return AuthenticatedAPIClient()
```

### File Upload Fixtures

```python
# conftest.py
import io
from PIL import Image
from django.core.files.uploadedfile import SimpleUploadedFile

@pytest.fixture
def image_file():
    """Create a test image file."""
    file = io.BytesIO()
    image = Image.new('RGB', (100, 100), color='red')
    image.save(file, 'PNG')
    file.seek(0)
    return SimpleUploadedFile(
        name='test.png',
        content=file.read(),
        content_type='image/png'
    )

@pytest.fixture
def csv_file():
    """Create a test CSV file."""
    content = b'name,email\nJohn,john@example.com\nJane,jane@example.com'
    return SimpleUploadedFile(
        name='test.csv',
        content=content,
        content_type='text/csv'
    )
```

---

## Best Practices

### 1. Keep Fixtures Small and Focused

```python
# Good - small, focused fixtures
@pytest.fixture
def user(db):
    return UserFactory()

@pytest.fixture
def active_user(user):
    user.is_active = True
    user.save()
    return user

# Bad - large fixture doing too much
@pytest.fixture
def everything():
    user = UserFactory()
    posts = PostFactory.create_batch(10, author=user)
    comments = CommentFactory.create_batch(50)
    # ... too much setup
```

### 2. Use Parametrized Fixtures

```python
@pytest.fixture(params=['admin', 'staff', 'user'])
def user_type(request, db):
    """Test with different user types."""
    if request.param == 'admin':
        return AdminFactory()
    elif request.param == 'staff':
        return UserFactory(is_staff=True)
    return UserFactory()

def test_access_dashboard(client, user_type):
    """Test dashboard access for different user types."""
    client.authenticate_as(user_type)
    response = client.get('/dashboard/')
    # Assertions based on user type
```

### 3. Cleanup Properly

```python
@pytest.fixture
def temp_file(tmp_path):
    """Create and cleanup temp file."""
    file_path = tmp_path / "test.txt"
    file_path.write_text("test content")
    yield file_path
    # Cleanup happens automatically with tmp_path

@pytest.fixture
def mock_external_service():
    """Mock external API calls."""
    with patch('app.services.external_api.call') as mock:
        mock.return_value = {'status': 'success'}
        yield mock
```

### 4. Document Fixtures

```python
@pytest.fixture
def premium_user(db) -> User:
    """
    Create a premium subscription user.

    Returns:
        User: A user with active premium subscription

    Example:
        def test_premium_feature(premium_user, auth_client):
            auth_client.authenticate_as(premium_user)
            response = auth_client.get('/premium-only/')
            assert response.status_code == 200
    """
    user = UserFactory()
    SubscriptionFactory(user=user, plan='premium', status='active')
    return user
```

---

## Related Files

- [fix-bug.md](../debugging/fix-bug.md) - Django debugging guide
- [backend-dev-guidelines.md](../backend-dev-guidelines.md) - Django best practices
- [pytest Documentation](https://docs.pytest.org/)
- [pytest-django](https://pytest-django.readthedocs.io/)
- [Factory Boy](https://factoryboy.readthedocs.io/)
