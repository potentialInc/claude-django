# S3 File Uploads with Pre-signed URLs

## Overview

Upload files to AWS S3, generate time-limited pre-signed URLs, and persist the signed URL to a database field. This pattern uses `django-storages` with S3Boto3Storage and CloudFront for secure, expiring access links.

```
Upload Flow:
┌─────────────────────────────────────────────────────────────────┐
│                       Client (File Upload)                       │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                      DRF APIView / ViewSet                       │
│  • Validate file via serializer                                  │
│  • Call S3UploadService                                          │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                      S3UploadService                             │
│  • Generate UUID filename                                        │
│  • Upload to S3 via boto3                                        │
│  • Generate pre-signed URL (1 hour expiry)                       │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                       Database Update                            │
│  • Save pre-signed URL to record's file_url field                │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                       JSON Response                              │
│  • Return file_url to client                                     │
└─────────────────────────────────────────────────────────────────┘
```

---

## Installation & Setup

### Dependencies

```bash
pip install boto3 django-storages
```

```txt
# requirements/base.txt
boto3>=1.28.0
django-storages>=1.14.0
```

### Environment Variables

These are already configured in `.env.dummy`:

```bash
# .env.dummy (AWS S3 section)
USE_S3=True
AWS_ACCESS_KEY_ID=your-access-key
AWS_SECRET_ACCESS_KEY=your-secret-key
AWS_STORAGE_BUCKET_NAME=your-bucket-name
AWS_S3_REGION_NAME=ap-northeast-2
AWS_LOCATION=your_project_folder
AWS_QUERYSTRING_EXPIRE=3600
CUSTOM_DOMAIN=your-cloudfront-domain.cloudfront.net
CLOUDFRONT_KEY_ID=your-key-id
AWS_CLOUDFRONT_KEY=-----BEGIN RSA PRIVATE KEY-----\n...\n-----END RSA PRIVATE KEY-----
```

---

## Configuration

### Storage Settings

```python
# core/settings/storage_settings.py
from .base_settings import env

USE_S3 = env.bool("USE_S3", True)

if USE_S3:
    AWS_ACCESS_KEY_ID = env("AWS_ACCESS_KEY_ID")
    AWS_SECRET_ACCESS_KEY = env("AWS_SECRET_ACCESS_KEY")
    AWS_STORAGE_BUCKET_NAME = env("AWS_STORAGE_BUCKET_NAME")
    AWS_S3_REGION_NAME = env("AWS_S3_REGION_NAME")
    AWS_S3_CUSTOM_DOMAIN = env("CUSTOM_DOMAIN")
    AWS_S3_OBJECT_PARAMETERS = {"CacheControl": "max-age=86400"}
    AWS_QUERYSTRING_EXPIRE = int(env("AWS_QUERYSTRING_EXPIRE"))
    AWS_LOCATION = f"{env('AWS_LOCATION')}"

    CLOUDFRONT_KEY_ID = env("CLOUDFRONT_KEY_ID")
    AWS_CLOUDFRONT_KEY = env("AWS_CLOUDFRONT_KEY").replace("\\n", "\n")

    STORAGES = {
        "default": {
            "BACKEND": "core.storages.s3.PrivateMediaStorage",
        },
        "staticfiles": {
            "BACKEND": "core.storages.s3.StaticFilesStorage",
        },
    }
```

### Storage Backends

```python
# core/storages/s3.py
from django.conf import settings
from storages.backends.s3boto3 import S3Boto3Storage


class PrivateMediaStorage(S3Boto3Storage):
    """Private media files served via CloudFront signed URLs."""
    custom_domain = settings.AWS_S3_CUSTOM_DOMAIN
    cloudfront_key_id = settings.CLOUDFRONT_KEY_ID
    cloudfront_key = settings.AWS_CLOUDFRONT_KEY
    querystring_expire = settings.AWS_QUERYSTRING_EXPIRE
    location = f"{settings.AWS_LOCATION}/private"
    default_acl = "private"
    file_overwrite = False
    signature_version = "s3v4"
    addressing_style = "virtual"


class PublicMediaStorage(S3Boto3Storage):
    """Public media files with signed URLs."""
    custom_domain = settings.AWS_S3_CUSTOM_DOMAIN
    location = f"{settings.AWS_LOCATION}/media"
    file_overwrite = False
    default_acl = "public-read"
    querystring_expire = settings.AWS_QUERYSTRING_EXPIRE
```

---

## Service Layer

```python
# apps/core/services/s3_upload.py
import os
import uuid
import logging

import boto3
from botocore.exceptions import ClientError
from django.conf import settings

logger = logging.getLogger(__name__)


class S3UploadService:
    """Handles file uploads to AWS S3 and pre-signed URL generation."""

    def __init__(self):
        self.s3_client = boto3.client(
            's3',
            aws_access_key_id=settings.AWS_ACCESS_KEY_ID,
            aws_secret_access_key=settings.AWS_SECRET_ACCESS_KEY,
            region_name=settings.AWS_S3_REGION_NAME,
        )
        self.bucket_name = settings.AWS_STORAGE_BUCKET_NAME
        self.location = settings.AWS_LOCATION

    def _generate_key(self, file_name):
        """Generate a unique S3 key: {location}/uploads/{uuid}.{ext}."""
        ext = os.path.splitext(file_name)[1].lower()
        unique_name = f"{uuid.uuid4()}{ext}"
        return f"{self.location}/uploads/{unique_name}"

    def upload_file(self, file):
        """
        Upload a file object to S3.

        Args:
            file: Django UploadedFile or file-like object with a .name attribute.

        Returns:
            str: The S3 object key.

        Raises:
            ClientError: If the upload fails.
        """
        key = self._generate_key(file.name)
        try:
            self.s3_client.upload_fileobj(
                file,
                self.bucket_name,
                key,
                ExtraArgs={
                    'ContentType': getattr(file, 'content_type', 'application/octet-stream'),
                },
            )
            logger.info("Uploaded %s to s3://%s/%s", file.name, self.bucket_name, key)
            return key
        except ClientError:
            logger.exception("Failed to upload %s to S3", file.name)
            raise

    def generate_presigned_url(self, key, expiry=None):
        """
        Generate a pre-signed URL for an S3 object.

        Args:
            key: The S3 object key.
            expiry: URL expiry in seconds (default: AWS_QUERYSTRING_EXPIRE from settings).

        Returns:
            str: The pre-signed URL.

        Raises:
            ClientError: If URL generation fails.
        """
        if expiry is None:
            expiry = settings.AWS_QUERYSTRING_EXPIRE
        try:
            url = self.s3_client.generate_presigned_url(
                'get_object',
                Params={'Bucket': self.bucket_name, 'Key': key},
                ExpiresIn=expiry,
            )
            return url
        except ClientError:
            logger.exception("Failed to generate pre-signed URL for %s", key)
            raise

    def upload_and_get_url(self, file, expiry=None):
        """
        Upload a file and return a pre-signed URL in one step.

        Args:
            file: Django UploadedFile or file-like object.
            expiry: URL expiry in seconds.

        Returns:
            str: The pre-signed URL for the uploaded file.
        """
        key = self.upload_file(file)
        url = self.generate_presigned_url(key, expiry)
        return url
```

---

## Model Integration

```python
# apps/feature/models.py
from django.db import models
from apps.core.models import BaseModel


class Document(BaseModel):
    """Example model with an S3 file URL field."""

    title = models.CharField(max_length=255)
    file_url = models.URLField(max_length=2000, blank=True, default='')

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return self.title

    def update_file_url(self, url):
        """Save the pre-signed URL to this record."""
        self.file_url = url
        self.save(update_fields=['file_url', 'updated_at'])
```

---

## Serializer

```python
# apps/feature/serializers.py
from rest_framework import serializers
from .models import Document


class FileUploadSerializer(serializers.Serializer):
    """Validates the uploaded file."""

    file = serializers.FileField()

    def validate_file(self, value):
        max_size = 10 * 1024 * 1024  # 10 MB
        if value.size > max_size:
            raise serializers.ValidationError("File size must not exceed 10 MB.")
        return value


class DocumentSerializer(serializers.ModelSerializer):
    """Read serializer for Document."""

    class Meta:
        model = Document
        fields = ['id', 'title', 'file_url', 'created_at', 'updated_at']
        read_only_fields = ['id', 'file_url', 'created_at', 'updated_at']
```

---

## View

```python
# apps/feature/views.py
import logging

from botocore.exceptions import ClientError
from rest_framework import status
from rest_framework.generics import get_object_or_404
from rest_framework.parsers import MultiPartParser
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.core.services.s3_upload import S3UploadService
from .models import Document
from .serializers import DocumentSerializer, FileUploadSerializer

logger = logging.getLogger(__name__)


class DocumentFileUploadView(APIView):
    """Upload a file to S3 and save the pre-signed URL to a Document record."""

    parser_classes = [MultiPartParser]
    permission_classes = [IsAuthenticated]

    def post(self, request, pk):
        document = get_object_or_404(Document, pk=pk)

        serializer = FileUploadSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        file = serializer.validated_data['file']
        service = S3UploadService()

        try:
            url = service.upload_and_get_url(file)
        except ClientError:
            return Response(
                {'error': 'File upload failed. Please try again.'},
                status=status.HTTP_502_BAD_GATEWAY,
            )

        document.update_file_url(url)

        return Response(
            DocumentSerializer(document).data,
            status=status.HTTP_200_OK,
        )
```

---

## URL Configuration

```python
# apps/feature/urls.py
from django.urls import path
from .views import DocumentFileUploadView

urlpatterns = [
    path('<uuid:pk>/upload/', DocumentFileUploadView.as_view(), name='document-upload'),
]
```

```python
# config/urls.py (or core/urls.py)
urlpatterns = [
    # ...
    path('api/documents/', include('apps.feature.urls')),
]
```

---

## Testing

```python
# apps/feature/tests/test_s3_upload.py
from unittest.mock import MagicMock, patch

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase

from apps.core.services.s3_upload import S3UploadService


class S3UploadServiceTest(TestCase):
    """Tests for S3UploadService."""

    @patch('apps.core.services.s3_upload.boto3.client')
    def test_upload_file_returns_key(self, mock_boto_client):
        """upload_file returns an S3 key in {location}/uploads/{uuid}.{ext} format."""
        mock_s3 = MagicMock()
        mock_boto_client.return_value = mock_s3

        service = S3UploadService()
        file = SimpleUploadedFile('report.pdf', b'content', content_type='application/pdf')
        key = service.upload_file(file)

        self.assertTrue(key.endswith('.pdf'))
        self.assertIn('/uploads/', key)
        mock_s3.upload_fileobj.assert_called_once()

    @patch('apps.core.services.s3_upload.boto3.client')
    def test_generate_presigned_url(self, mock_boto_client):
        """generate_presigned_url returns a URL string."""
        mock_s3 = MagicMock()
        mock_s3.generate_presigned_url.return_value = 'https://s3.example.com/signed'
        mock_boto_client.return_value = mock_s3

        service = S3UploadService()
        url = service.generate_presigned_url('uploads/test.pdf')

        self.assertEqual(url, 'https://s3.example.com/signed')
        mock_s3.generate_presigned_url.assert_called_once()

    @patch('apps.core.services.s3_upload.boto3.client')
    def test_upload_and_get_url(self, mock_boto_client):
        """upload_and_get_url returns a pre-signed URL."""
        mock_s3 = MagicMock()
        mock_s3.generate_presigned_url.return_value = 'https://s3.example.com/signed'
        mock_boto_client.return_value = mock_s3

        service = S3UploadService()
        file = SimpleUploadedFile('photo.jpg', b'image', content_type='image/jpeg')
        url = service.upload_and_get_url(file)

        self.assertEqual(url, 'https://s3.example.com/signed')
```

---

## Best Practices Summary

1. **Never hardcode AWS credentials** - Always use environment variables via `env()`
2. **Use UUID filenames** - Prevents collisions and hides original filenames
3. **Set appropriate expiry** - `AWS_QUERYSTRING_EXPIRE` controls URL lifetime (default 3600s / 1 hour)
4. **Validate uploads in serializers** - Check file size and type before uploading
5. **Handle S3 errors gracefully** - Catch `ClientError` and return clear API errors
6. **Use `upload_fileobj` over `upload_file`** - Works directly with Django's in-memory files
7. **Set ContentType on upload** - Ensures correct MIME type when file is accessed via URL
8. **Use `MultiPartParser`** - Required for file upload endpoints in DRF
9. **Log upload operations** - Aids debugging without exposing sensitive data
10. **Use `PrivateMediaStorage` for sensitive files** - Leverages CloudFront signed URLs for extra security
