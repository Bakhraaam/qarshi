from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('sync_1c', '0030_organization_unregistered_notice'),
    ]

    operations = [
        migrations.AddField(
            model_name='item',
            name='is_invalid',
            field=models.BooleanField(db_index=True, default=False,
                                      verbose_name='Недействителен (не показывать на сайте)'),
        ),
    ]
