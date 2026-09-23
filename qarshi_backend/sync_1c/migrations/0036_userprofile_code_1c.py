from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('sync_1c', '0035_order_checkout_details'),
    ]

    operations = [
        migrations.AddField(
            model_name='userprofile',
            name='code_1c',
            field=models.CharField(blank=True, db_index=True, default='', max_length=50, verbose_name='Код в 1С'),
        ),
    ]
