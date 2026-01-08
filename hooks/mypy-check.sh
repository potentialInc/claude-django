#!/bin/bash
# mypy-check.sh - Run Python type checking with mypy
# Triggered on Stop to verify type safety

set -e

# Navigate to backend directory if it exists
if [ -d "backend" ]; then
    cd backend

    # Check if mypy is installed
    if command -v mypy &> /dev/null; then
        echo "Running mypy type checking..."
        mypy . --ignore-missing-imports --no-error-summary 2>&1 || true
    else
        echo "mypy not found. Install with: pip install mypy django-stubs djangorestframework-stubs"
    fi
elif [ -f "manage.py" ]; then
    # We're already in the Django project directory
    if command -v mypy &> /dev/null; then
        echo "Running mypy type checking..."
        mypy . --ignore-missing-imports --no-error-summary 2>&1 || true
    else
        echo "mypy not found. Install with: pip install mypy django-stubs djangorestframework-stubs"
    fi
else
    echo "No Django backend directory found"
fi
