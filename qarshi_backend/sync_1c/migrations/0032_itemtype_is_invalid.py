from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('sync_1c', '0031_item_is_invalid'),
    ]

    operations = [
        migrations.AddField(
            model_name='itemtype',
            name='is_invalid',
            field=models.BooleanField(db_index=True, default=False,
                                      verbose_name='Недействителен (не показывать на сайте)'),
        ),
    ]
