#!/bin/bash
# django-test.sh - Run Django/pytest tests
# Can be triggered manually or added to Stop hooks

set -e

# Navigate to backend directory if it exists
if [ -d "backend" ]; then
    cd backend

    # Check if pytest is available (preferred)
    if command -v pytest &> /dev/null; then
        echo "Running pytest..."
        pytest --tb=short -q 2>&1 || true
    # Fall back to Django test runner
    elif [ -f "manage.py" ]; then
        echo "Running Django tests..."
        python manage.py test --verbosity=1 2>&1 || true
    else
        echo "No test runner found. Install pytest: pip install pytest pytest-django"
    fi
elif [ -f "manage.py" ]; then
    # We're already in the Django project directory
    if command -v pytest &> /dev/null; then
        echo "Running pytest..."
        pytest --tb=short -q 2>&1 || true
    else
        echo "Running Django tests..."
        python manage.py test --verbosity=1 2>&1 || true
    fi
else
    echo "No Django backend directory found"
fi
