from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('sync_1c', '0036_userprofile_code_1c'),
    ]

    operations = [
        migrations.AddField(
            model_name='organization',
            name='start_text',
            field=models.TextField(blank=True, default='', verbose_name='Текст бота после /start'),
        ),
    ]
