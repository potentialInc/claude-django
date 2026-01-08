# Models and ORM

## Model Definition

### Base Model

```python
# apps/core/models.py
import uuid
from django.db import models
from django.utils import timezone

class BaseManager(models.Manager):
    """Manager that excludes soft-deleted records."""

    def get_queryset(self):
        return super().get_queryset().filter(deleted_at__isnull=True)

class BaseModel(models.Model):
    """Abstract base model with common fields."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)
    deleted_at = models.DateTimeField(null=True, blank=True, db_index=True)

    objects = BaseManager()
    all_objects = models.Manager()

    class Meta:
        abstract = True
        ordering = ['-created_at']

    def soft_delete(self):
        """Soft delete the record."""
        self.deleted_at = timezone.now()
        self.save(update_fields=['deleted_at', 'updated_at'])

    def restore(self):
        """Restore soft-deleted record."""
        self.deleted_at = None
        self.save(update_fields=['deleted_at', 'updated_at'])
```

### Feature Model Example

```python
# apps/feature/models.py
from django.db import models
from django.contrib.auth import get_user_model
from apps.core.models import BaseModel

User = get_user_model()

class FeatureManager(models.Manager):
    """Custom manager for Feature model."""

    def get_queryset(self):
        return super().get_queryset().filter(deleted_at__isnull=True)

    def active(self):
        """Get active features."""
        return self.get_queryset().filter(status='active')

    def for_user(self, user):
        """Get features for a specific user."""
        return self.get_queryset().filter(user=user)

    def with_related(self):
        """Get features with related objects."""
        return self.get_queryset().select_related('user', 'category').prefetch_related('tags')

class Feature(BaseModel):
    """Feature model."""

    STATUS_CHOICES = [
        ('draft', 'Draft'),
        ('active', 'Active'),
        ('archived', 'Archived'),
    ]

    name = models.CharField(max_length=100, db_index=True)
    description = models.TextField(blank=True)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='draft')
    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='features'
    )
    category = models.ForeignKey(
        'Category',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='features'
    )
    tags = models.ManyToManyField('Tag', blank=True, related_name='features')
    priority = models.IntegerField(default=0)
    is_featured = models.BooleanField(default=False)

    objects = FeatureManager()

    class Meta:
        db_table = 'features'
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['status', 'user']),
            models.Index(fields=['created_at']),
        ]
        constraints = [
            models.UniqueConstraint(
                fields=['user', 'name'],
                condition=models.Q(deleted_at__isnull=True),
                name='unique_feature_name_per_user'
            ),
        ]

    def __str__(self):
        return self.name

    def activate(self):
        """Activate the feature."""
        self.status = 'active'
        self.save(update_fields=['status', 'updated_at'])

    def archive(self):
        """Archive the feature."""
        self.status = 'archived'
        self.save(update_fields=['status', 'updated_at'])
```

---

## Relationships

### One-to-Many (ForeignKey)

```python
class Comment(BaseModel):
    feature = models.ForeignKey(
        Feature,
        on_delete=models.CASCADE,  # Delete comments when feature deleted
        related_name='comments'     # feature.comments.all()
    )
    author = models.ForeignKey(
        User,
        on_delete=models.SET_NULL,  # Keep comment, remove author reference
        null=True,
        related_name='comments'
    )
    content = models.TextField()
```

### Many-to-Many

```python
class Tag(BaseModel):
    name = models.CharField(max_length=50, unique=True)

class Feature(BaseModel):
    tags = models.ManyToManyField(Tag, blank=True, related_name='features')

# Usage
feature.tags.add(tag)
feature.tags.remove(tag)
feature.tags.set([tag1, tag2])
feature.tags.clear()
```

### Many-to-Many with Through Model

```python
class FeatureTag(models.Model):
    """Through model for Feature-Tag relationship."""
    feature = models.ForeignKey(Feature, on_delete=models.CASCADE)
    tag = models.ForeignKey(Tag, on_delete=models.CASCADE)
    added_by = models.ForeignKey(User, on_delete=models.SET_NULL, null=True)
    added_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ['feature', 'tag']

class Feature(BaseModel):
    tags = models.ManyToManyField(Tag, through='FeatureTag', related_name='features')
```

### One-to-One

```python
class UserProfile(BaseModel):
    user = models.OneToOneField(
        User,
        on_delete=models.CASCADE,
        related_name='profile'
    )
    bio = models.TextField(blank=True)
    avatar = models.ImageField(upload_to='avatars/', blank=True)
```

---

## QuerySet Operations

### Basic Queries

```python
# Get all
features = Feature.objects.all()

# Filter
active_features = Feature.objects.filter(status='active')
user_features = Feature.objects.filter(user=user)

# Exclude
non_draft = Feature.objects.exclude(status='draft')

# Get single object
feature = Feature.objects.get(pk=uuid)  # Raises DoesNotExist if not found
feature = Feature.objects.filter(pk=uuid).first()  # Returns None if not found

# Get or create
feature, created = Feature.objects.get_or_create(
    name='Default Feature',
    defaults={'description': 'Default description', 'user': user}
)

# Update or create
feature, created = Feature.objects.update_or_create(
    name='Feature Name',
    user=user,
    defaults={'description': 'Updated description'}
)
```

### Chaining Queries

```python
features = (
    Feature.objects
    .filter(status='active')
    .filter(user=user)
    .exclude(is_featured=False)
    .order_by('-priority', '-created_at')
)
```

### Q Objects (Complex Queries)

```python
from django.db.models import Q

# OR condition
features = Feature.objects.filter(
    Q(status='active') | Q(status='draft')
)

# AND with OR
features = Feature.objects.filter(
    Q(user=user) & (Q(status='active') | Q(is_featured=True))
)

# NOT condition
features = Feature.objects.filter(~Q(status='archived'))
```

### F Expressions (Field References)

```python
from django.db.models import F

# Compare fields
features = Feature.objects.filter(priority__gt=F('default_priority'))

# Update with F expression (atomic)
Feature.objects.filter(pk=pk).update(priority=F('priority') + 1)

# Annotate with F expression
features = Feature.objects.annotate(score=F('priority') * F('weight'))
```

---

## Aggregation and Annotation

### Basic Aggregation

```python
from django.db.models import Count, Sum, Avg, Max, Min

# Single aggregation
total = Feature.objects.aggregate(total=Count('id'))
# {'total': 42}

# Multiple aggregations
stats = Feature.objects.aggregate(
    total=Count('id'),
    avg_priority=Avg('priority'),
    max_priority=Max('priority'),
)
```

### Annotation (Per-Object Aggregation)

```python
# Count related objects
features = Feature.objects.annotate(
    comment_count=Count('comments')
)
for feature in features:
    print(feature.comment_count)

# Filter by annotation
popular_features = Feature.objects.annotate(
    comment_count=Count('comments')
).filter(comment_count__gt=10)
```

### Group By (Values + Annotate)

```python
# Count features by status
status_counts = (
    Feature.objects
    .values('status')
    .annotate(count=Count('id'))
    .order_by('-count')
)
# [{'status': 'active', 'count': 25}, {'status': 'draft', 'count': 10}]

# Count by user with user name
user_counts = (
    Feature.objects
    .values('user__name')
    .annotate(count=Count('id'))
)
```

---

## Optimization

### Select Related (ForeignKey/OneToOne)

```python
# Without optimization (N+1 queries)
for feature in Feature.objects.all():
    print(feature.user.name)  # Each access = new query

# With select_related (1 query with JOIN)
for feature in Feature.objects.select_related('user'):
    print(feature.user.name)  # No additional query

# Multiple relations
features = Feature.objects.select_related('user', 'category')
```

### Prefetch Related (ManyToMany/Reverse FK)

```python
# Without optimization (N+1 queries)
for feature in Feature.objects.all():
    for tag in feature.tags.all():  # Each access = new query
        print(tag.name)

# With prefetch_related (2 queries total)
for feature in Feature.objects.prefetch_related('tags'):
    for tag in feature.tags.all():  # No additional query
        print(tag.name)

# Custom prefetch
from django.db.models import Prefetch

features = Feature.objects.prefetch_related(
    Prefetch(
        'comments',
        queryset=Comment.objects.filter(is_approved=True).select_related('author'),
        to_attr='approved_comments'
    )
)
```

### Only/Defer (Partial Fetching)

```python
# Only fetch specific fields
features = Feature.objects.only('id', 'name', 'status')

# Defer specific fields
features = Feature.objects.defer('description', 'content')
```

### Bulk Operations

```python
# Bulk create
features = [Feature(name=f'Feature {i}', user=user) for i in range(100)]
Feature.objects.bulk_create(features, batch_size=50)

# Bulk update
Feature.objects.filter(status='draft').update(status='active')

# Bulk update with objects
for feature in features:
    feature.status = 'active'
Feature.objects.bulk_update(features, ['status'], batch_size=50)
```

---

## Migrations

### Creating Migrations

```bash
# Generate migrations for all apps
python manage.py makemigrations

# Generate migrations for specific app
python manage.py makemigrations feature

# Show migration SQL
python manage.py sqlmigrate feature 0001

# Check for issues
python manage.py check
```

### Applying Migrations

```bash
# Apply all migrations
python manage.py migrate

# Apply specific app migrations
python manage.py migrate feature

# Rollback to specific migration
python manage.py migrate feature 0001

# Show migration status
python manage.py showmigrations
```

### Data Migrations

```python
# feature/migrations/0002_populate_data.py
from django.db import migrations

def populate_categories(apps, schema_editor):
    Category = apps.get_model('feature', 'Category')
    Category.objects.bulk_create([
        Category(name='Technology'),
        Category(name='Science'),
        Category(name='Arts'),
    ])

def reverse_populate_categories(apps, schema_editor):
    Category = apps.get_model('feature', 'Category')
    Category.objects.filter(name__in=['Technology', 'Science', 'Arts']).delete()

class Migration(migrations.Migration):
    dependencies = [
        ('feature', '0001_initial'),
    ]

    operations = [
        migrations.RunPython(populate_categories, reverse_populate_categories),
    ]
```

---

## Best Practices

1. **Use model managers** - Encapsulate query logic
2. **Add indexes** - For frequently filtered/ordered fields
3. **Use select_related/prefetch_related** - Prevent N+1 queries
4. **Use F() expressions** - For atomic updates
5. **Use bulk operations** - For batch inserts/updates
6. **Add constraints** - For data integrity
7. **Use choices for status fields** - For type safety
8. **Soft delete by default** - Preserve data history
