# Page Objects Pattern for Python E2E Tests

Page Object pattern templates for Python E2E tests using Playwright or Selenium.

## Table of Contents

- [Setup](#setup)
- [Base Page Pattern](#base-page-pattern)
- [Playwright Python Examples](#playwright-python-examples)
- [Selenium Python Examples](#selenium-python-examples)
- [Best Practices](#best-practices)

---

## Setup

### Playwright Python

```bash
pip install pytest-playwright
playwright install
```

### Selenium

```bash
pip install selenium pytest webdriver-manager
```

### Project Structure

```
backend/
├── tests/
│   ├── e2e/
│   │   ├── conftest.py       # E2E fixtures
│   │   ├── pages/
│   │   │   ├── __init__.py
│   │   │   ├── base.py       # BasePage class
│   │   │   ├── login.py      # LoginPage
│   │   │   └── dashboard.py  # DashboardPage
│   │   └── test_login.py
```

---

## Base Page Pattern

### Base Page Class

```python
# tests/e2e/pages/base.py
from abc import ABC, abstractmethod
from playwright.sync_api import Page, expect

class BasePage(ABC):
    """Base page object that all pages inherit from."""

    def __init__(self, page: Page):
        self.page = page

    @property
    @abstractmethod
    def url(self) -> str:
        """Page URL path."""
        pass

    def navigate(self) -> None:
        """Navigate to this page."""
        self.page.goto(self.url)

    def wait_for_load(self) -> None:
        """Wait for page to fully load."""
        self.page.wait_for_load_state('networkidle')

    def get_title(self) -> str:
        """Get page title."""
        return self.page.title()

    def take_screenshot(self, name: str) -> None:
        """Take screenshot for debugging."""
        self.page.screenshot(path=f'screenshots/{name}.png')

    def expect_url(self, url_pattern: str) -> None:
        """Assert current URL matches pattern."""
        expect(self.page).to_have_url(url_pattern)

    def expect_title(self, title: str) -> None:
        """Assert page title."""
        expect(self.page).to_have_title(title)
```

---

## Playwright Python Examples

### Login Page

```python
# tests/e2e/pages/login.py
from playwright.sync_api import Page, expect
from .base import BasePage

class LoginPage(BasePage):
    """Login page object."""

    url = '/login'

    def __init__(self, page: Page):
        super().__init__(page)
        # Locators
        self.email_input = page.get_by_placeholder('Email')
        self.password_input = page.get_by_placeholder('Password')
        self.submit_button = page.get_by_role('button', name='Sign In')
        self.error_message = page.locator('[data-testid="error-message"]')
        self.forgot_password_link = page.get_by_role('link', name='Forgot password')

    def login(self, email: str, password: str) -> None:
        """Perform login action."""
        self.email_input.fill(email)
        self.password_input.fill(password)
        self.submit_button.click()

    def login_and_wait(self, email: str, password: str) -> None:
        """Login and wait for redirect."""
        self.login(email, password)
        self.page.wait_for_url('**/dashboard**')

    def expect_error(self, message: str) -> None:
        """Assert error message is displayed."""
        expect(self.error_message).to_be_visible()
        expect(self.error_message).to_contain_text(message)

    def expect_login_success(self) -> None:
        """Assert successful login redirect."""
        expect(self.page).to_have_url('/dashboard')

    def click_forgot_password(self) -> None:
        """Navigate to forgot password page."""
        self.forgot_password_link.click()
        self.page.wait_for_url('**/forgot-password**')
```

### Dashboard Page

```python
# tests/e2e/pages/dashboard.py
from playwright.sync_api import Page, expect, Locator
from .base import BasePage

class DashboardPage(BasePage):
    """Dashboard page object."""

    url = '/dashboard'

    def __init__(self, page: Page):
        super().__init__(page)
        # Locators
        self.welcome_message = page.locator('h1')
        self.user_menu = page.get_by_role('button', name='User menu')
        self.logout_button = page.get_by_role('menuitem', name='Logout')
        self.stats_cards = page.locator('[data-testid="stat-card"]')
        self.sidebar = page.locator('[data-testid="sidebar"]')

    def get_welcome_text(self) -> str:
        """Get welcome message text."""
        return self.welcome_message.text_content()

    def logout(self) -> None:
        """Perform logout action."""
        self.user_menu.click()
        self.logout_button.click()
        self.page.wait_for_url('**/login**')

    def get_stat_count(self) -> int:
        """Get number of stat cards."""
        return self.stats_cards.count()

    def click_sidebar_link(self, name: str) -> None:
        """Click a sidebar navigation link."""
        self.sidebar.get_by_role('link', name=name).click()

    def expect_welcome_message(self, name: str) -> None:
        """Assert welcome message contains user name."""
        expect(self.welcome_message).to_contain_text(f'Welcome, {name}')

    def expect_stats_loaded(self) -> None:
        """Assert stats cards are visible."""
        expect(self.stats_cards.first).to_be_visible()
```

### List Page Pattern

```python
# tests/e2e/pages/users_list.py
from playwright.sync_api import Page, expect, Locator
from .base import BasePage

class UsersListPage(BasePage):
    """Users list page object."""

    url = '/users'

    def __init__(self, page: Page):
        super().__init__(page)
        self.search_input = page.get_by_placeholder('Search users...')
        self.user_rows = page.locator('table tbody tr')
        self.empty_state = page.get_by_text('No users found')
        self.add_user_button = page.get_by_role('button', name='Add User')
        self.loading_spinner = page.locator('[data-testid="loading"]')

    def search(self, query: str) -> None:
        """Search for users."""
        self.search_input.fill(query)
        self.page.wait_for_load_state('networkidle')

    def get_user_count(self) -> int:
        """Get number of users in list."""
        return self.user_rows.count()

    def get_user_row(self, email: str) -> Locator:
        """Get row for specific user."""
        return self.user_rows.filter(has_text=email)

    def click_user(self, email: str) -> None:
        """Click on a user row."""
        self.get_user_row(email).click()

    def delete_user(self, email: str) -> None:
        """Delete a user."""
        row = self.get_user_row(email)
        row.get_by_role('button', name='Delete').click()
        self.page.get_by_role('button', name='Confirm').click()

    def expect_user_visible(self, email: str) -> None:
        """Assert user is in list."""
        expect(self.get_user_row(email)).to_be_visible()

    def expect_empty_state(self) -> None:
        """Assert empty state is shown."""
        expect(self.empty_state).to_be_visible()

    def wait_for_load(self) -> None:
        """Wait for users to load."""
        expect(self.loading_spinner).not_to_be_visible()
```

### Test Examples with Playwright

```python
# tests/e2e/test_login.py
import pytest
from playwright.sync_api import Page
from .pages.login import LoginPage
from .pages.dashboard import DashboardPage

class TestLogin:
    @pytest.fixture(autouse=True)
    def setup(self, page: Page):
        self.page = page
        self.login_page = LoginPage(page)
        self.dashboard_page = DashboardPage(page)

    def test_successful_login(self):
        """Test successful login flow."""
        self.login_page.navigate()
        self.login_page.login_and_wait('user@example.com', 'password123')
        self.dashboard_page.expect_welcome_message('User')

    def test_invalid_credentials(self):
        """Test login with invalid credentials."""
        self.login_page.navigate()
        self.login_page.login('wrong@email.com', 'wrongpassword')
        self.login_page.expect_error('Invalid credentials')

    def test_logout(self):
        """Test logout flow."""
        # Login first
        self.login_page.navigate()
        self.login_page.login_and_wait('user@example.com', 'password123')

        # Then logout
        self.dashboard_page.logout()
        self.login_page.expect_url('/login')
```

---

## Selenium Python Examples

### Base Page for Selenium

```python
# tests/e2e/pages/base_selenium.py
from abc import ABC, abstractmethod
from selenium.webdriver.remote.webdriver import WebDriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC

class BasePageSelenium(ABC):
    """Base page object for Selenium."""

    def __init__(self, driver: WebDriver, base_url: str = 'http://localhost:8000'):
        self.driver = driver
        self.base_url = base_url
        self.wait = WebDriverWait(driver, 10)

    @property
    @abstractmethod
    def url_path(self) -> str:
        pass

    @property
    def url(self) -> str:
        return f'{self.base_url}{self.url_path}'

    def navigate(self) -> None:
        self.driver.get(self.url)

    def find_element(self, by: By, value: str):
        return self.wait.until(EC.presence_of_element_located((by, value)))

    def click_element(self, by: By, value: str) -> None:
        element = self.wait.until(EC.element_to_be_clickable((by, value)))
        element.click()

    def fill_input(self, by: By, value: str, text: str) -> None:
        element = self.find_element(by, value)
        element.clear()
        element.send_keys(text)

    def get_text(self, by: By, value: str) -> str:
        return self.find_element(by, value).text

    def wait_for_url(self, url_contains: str) -> None:
        self.wait.until(EC.url_contains(url_contains))

    def is_element_visible(self, by: By, value: str) -> bool:
        try:
            self.wait.until(EC.visibility_of_element_located((by, value)))
            return True
        except:
            return False
```

### Login Page Selenium

```python
# tests/e2e/pages/login_selenium.py
from selenium.webdriver.common.by import By
from .base_selenium import BasePageSelenium

class LoginPageSelenium(BasePageSelenium):
    """Login page for Selenium tests."""

    url_path = '/login'

    # Locators
    EMAIL_INPUT = (By.CSS_SELECTOR, 'input[type="email"]')
    PASSWORD_INPUT = (By.CSS_SELECTOR, 'input[type="password"]')
    SUBMIT_BUTTON = (By.CSS_SELECTOR, 'button[type="submit"]')
    ERROR_MESSAGE = (By.CSS_SELECTOR, '[data-testid="error-message"]')

    def login(self, email: str, password: str) -> None:
        self.fill_input(*self.EMAIL_INPUT, email)
        self.fill_input(*self.PASSWORD_INPUT, password)
        self.click_element(*self.SUBMIT_BUTTON)

    def login_and_wait(self, email: str, password: str) -> None:
        self.login(email, password)
        self.wait_for_url('/dashboard')

    def get_error_message(self) -> str:
        return self.get_text(*self.ERROR_MESSAGE)

    def is_error_visible(self) -> bool:
        return self.is_element_visible(*self.ERROR_MESSAGE)
```

---

## Best Practices

### 1. Locator Strategy Priority

```python
# Preferred (most stable)
page.get_by_role('button', name='Submit')
page.get_by_label('Email')
page.get_by_placeholder('Enter email')
page.get_by_test_id('submit-button')

# Avoid (fragile)
page.locator('.btn-primary')
page.locator('#email-input')
page.locator('div > span > button')
```

### 2. Keep Pages Focused

```python
# Good - one page per file, focused methods
class LoginPage(BasePage):
    def login(self, email, password): ...
    def expect_error(self, message): ...

# Bad - mixing multiple pages
class AuthPages(BasePage):
    def login(self, ...): ...
    def register(self, ...): ...
    def reset_password(self, ...): ...
```

### 3. Use Fixtures for Common Flows

```python
# conftest.py
@pytest.fixture
def authenticated_page(page: Page) -> Page:
    """Return a page with logged in user."""
    login_page = LoginPage(page)
    login_page.navigate()
    login_page.login_and_wait('test@example.com', 'password')
    return page

# test file
def test_dashboard(authenticated_page):
    dashboard = DashboardPage(authenticated_page)
    dashboard.expect_welcome_message('Test')
```

### 4. Handle Async Operations

```python
# Wait for network to settle
self.page.wait_for_load_state('networkidle')

# Wait for specific element
expect(self.loading_spinner).not_to_be_visible()

# Wait for API response
with self.page.expect_response('**/api/users**') as response:
    self.search('john')
assert response.value.ok
```

---

## Related Files

- [pytest-fixtures.md](pytest-fixtures.md) - pytest fixtures guide
- [fix-bug.md](../debugging/fix-bug.md) - Debugging guide
- [Playwright Python Docs](https://playwright.dev/python/)
- [Selenium Python Docs](https://selenium-python.readthedocs.io/)
