# Serializers

## ModelSerializer

### Basic ModelSerializer

```python
from rest_framework import serializers
from .models import Feature

class FeatureSerializer(serializers.ModelSerializer):
    class Meta:
        model = Feature
        fields = ['id', 'name', 'description', 'status', 'user', 'created_at', 'updated_at']
        read_only_fields = ['id', 'user', 'created_at', 'updated_at']
```

### Separate Create/Update Serializers

```python
class CreateFeatureSerializer(serializers.ModelSerializer):
    """Serializer for creating features."""

    class Meta:
        model = Feature
        fields = ['name', 'description']

    def validate_name(self, value):
        if Feature.objects.filter(name=value).exists():
            raise serializers.ValidationError("Name already exists")
        return value

    def create(self, validated_data):
        validated_data['user'] = self.context['request'].user
        return super().create(validated_data)


class UpdateFeatureSerializer(serializers.ModelSerializer):
    """Serializer for updating features."""

    class Meta:
        model = Feature
        fields = ['name', 'description', 'status']

    def validate_name(self, value):
        instance = self.instance
        if Feature.objects.filter(name=value).exclude(pk=instance.pk).exists():
            raise serializers.ValidationError("Name already exists")
        return value
```

---

## Validation

### Field-Level Validation

```python
class CreateUserSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, min_length=8)
    password_confirm = serializers.CharField(write_only=True)

    class Meta:
        model = User
        fields = ['email', 'name', 'password', 'password_confirm']

    def validate_email(self, value):
        """Validate email format and uniqueness."""
        if User.objects.filter(email=value).exists():
            raise serializers.ValidationError("Email already registered")
        return value.lower()

    def validate_password(self, value):
        """Validate password strength."""
        if not any(c.isupper() for c in value):
            raise serializers.ValidationError("Must contain uppercase letter")
        if not any(c.isdigit() for c in value):
            raise serializers.ValidationError("Must contain a digit")
        return value
```

### Object-Level Validation

```python
class CreateUserSerializer(serializers.ModelSerializer):
    def validate(self, attrs):
        """Cross-field validation."""
        if attrs.get('password') != attrs.get('password_confirm'):
            raise serializers.ValidationError({
                'password_confirm': "Passwords don't match"
            })

        # Remove password_confirm from validated data
        attrs.pop('password_confirm', None)
        return attrs

    def create(self, validated_data):
        password = validated_data.pop('password')
        user = User.objects.create(**validated_data)
        user.set_password(password)
        user.save()
        return user
```

### Custom Validators

```python
from rest_framework import serializers

def validate_future_date(value):
    """Validator to ensure date is in the future."""
    from django.utils import timezone
    if value <= timezone.now().date():
        raise serializers.ValidationError("Date must be in the future")
    return value

class EventSerializer(serializers.ModelSerializer):
    event_date = serializers.DateField(validators=[validate_future_date])

    class Meta:
        model = Event
        fields = ['name', 'event_date']
```

---

## Nested Serializers

### Read-Only Nested

```python
class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ['id', 'name', 'email']

class FeatureSerializer(serializers.ModelSerializer):
    user = UserSerializer(read_only=True)

    class Meta:
        model = Feature
        fields = ['id', 'name', 'description', 'user']
```

### Writable Nested

```python
class AddressSerializer(serializers.ModelSerializer):
    class Meta:
        model = Address
        fields = ['street', 'city', 'country']

class UserSerializer(serializers.ModelSerializer):
    address = AddressSerializer()

    class Meta:
        model = User
        fields = ['id', 'name', 'email', 'address']

    def create(self, validated_data):
        address_data = validated_data.pop('address')
        user = User.objects.create(**validated_data)
        Address.objects.create(user=user, **address_data)
        return user

    def update(self, instance, validated_data):
        address_data = validated_data.pop('address', None)
        instance = super().update(instance, validated_data)

        if address_data:
            Address.objects.update_or_create(
                user=instance,
                defaults=address_data
            )
        return instance
```

---

## Serializer Fields

### Custom Fields

```python
class Base64ImageField(serializers.ImageField):
    """Field for handling base64 encoded images."""

    def to_internal_value(self, data):
        if isinstance(data, str) and data.startswith('data:image'):
            # Base64 encoded image
            import base64
            from django.core.files.base import ContentFile

            format, imgstr = data.split(';base64,')
            ext = format.split('/')[-1]
            data = ContentFile(
                base64.b64decode(imgstr),
                name=f'image.{ext}'
            )
        return super().to_internal_value(data)

class UserSerializer(serializers.ModelSerializer):
    avatar = Base64ImageField(required=False)

    class Meta:
        model = User
        fields = ['id', 'name', 'avatar']
```

### SerializerMethodField

```python
class FeatureSerializer(serializers.ModelSerializer):
    user_name = serializers.SerializerMethodField()
    is_owner = serializers.SerializerMethodField()
    days_since_created = serializers.SerializerMethodField()

    class Meta:
        model = Feature
        fields = ['id', 'name', 'user_name', 'is_owner', 'days_since_created']

    def get_user_name(self, obj):
        return obj.user.name

    def get_is_owner(self, obj):
        request = self.context.get('request')
        return request and request.user == obj.user

    def get_days_since_created(self, obj):
        from django.utils import timezone
        delta = timezone.now() - obj.created_at
        return delta.days
```

### SlugRelatedField

```python
class FeatureSerializer(serializers.ModelSerializer):
    # Display category name instead of ID
    category = serializers.SlugRelatedField(
        slug_field='name',
        queryset=Category.objects.all()
    )

    class Meta:
        model = Feature
        fields = ['id', 'name', 'category']
```

### PrimaryKeyRelatedField

```python
class FeatureSerializer(serializers.ModelSerializer):
    # Accept category ID for write, return ID for read
    category_id = serializers.PrimaryKeyRelatedField(
        source='category',
        queryset=Category.objects.all(),
        write_only=True
    )
    category = CategorySerializer(read_only=True)

    class Meta:
        model = Feature
        fields = ['id', 'name', 'category', 'category_id']
```

---

## Serializer Context

### Passing Context to Serializer

```python
# In ViewSet
class FeatureViewSet(viewsets.ModelViewSet):
    def get_serializer_context(self):
        context = super().get_serializer_context()
        context['extra_data'] = 'some value'
        return context

# In Serializer
class FeatureSerializer(serializers.ModelSerializer):
    def validate(self, attrs):
        extra_data = self.context.get('extra_data')
        request = self.context.get('request')
        # Use context data
        return attrs
```

---

## List Serializers

### Custom ListSerializer

```python
class BulkCreateFeatureSerializer(serializers.ListSerializer):
    def create(self, validated_data):
        features = [Feature(**item) for item in validated_data]
        return Feature.objects.bulk_create(features)

class FeatureSerializer(serializers.ModelSerializer):
    class Meta:
        model = Feature
        fields = ['name', 'description']
        list_serializer_class = BulkCreateFeatureSerializer
```

---

## Response Serializers (for documentation)

```python
from drf_spectacular.utils import extend_schema, OpenApiExample

class ErrorResponseSerializer(serializers.Serializer):
    """Serializer for error responses."""
    detail = serializers.CharField()
    code = serializers.CharField(required=False)

class SuccessResponseSerializer(serializers.Serializer):
    """Serializer for success responses."""
    message = serializers.CharField()

# Usage in view
@extend_schema(
    responses={
        200: FeatureSerializer,
        400: ErrorResponseSerializer,
        404: ErrorResponseSerializer,
    }
)
def retrieve(self, request, pk=None):
    pass
```

---

## Best Practices

1. **Separate serializers for create/update/read** - Different fields needed
2. **Use field-level validation** - `validate_<field_name>` methods
3. **Use object-level validation** - `validate` method for cross-field
4. **Pass context when needed** - Request, view, extra data
5. **Use SerializerMethodField** - For computed fields
6. **Avoid N+1 in nested serializers** - Use select_related/prefetch_related
7. **Document with OpenAPI** - Type hints and examples
