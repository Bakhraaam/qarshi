import uuid

from django.db import migrations, models


def drop_broken_packages(apps, schema_editor):
    """Чистим упаковки, созданные прошлой схемой.

    В 0033 первичным ключом был GUID из 1С, а он у единицы измерения общий для всех
    товаров с такой же фасовкой. Из-за этого строки разных товаров схлопывались в одну,
    и обмен падал на INSERT ... ON CONFLICT. Уцелевшие строки указывают на случайный
    товар, доверять им нельзя — проще удалить: упаковки целиком приходят из 1С и
    восстановятся первой же выгрузкой items/. Корзины при этом живы (CartItem.package
    это SET_NULL), а в заказах упаковка лежит отдельной копией.
    """
    apps.get_model('sync_1c', 'ItemPackage').objects.all().delete()


class Migration(migrations.Migration):

    dependencies = [
        ('sync_1c', '0033_itemimage_is_invalid_orderitem_package_count_and_more'),
    ]

    operations = [
        migrations.RunPython(drop_broken_packages, migrations.RunPython.noop),
        migrations.AddField(
            model_name='itempackage',
            name='guid_1c',
            field=models.UUIDField(db_index=True, default=uuid.uuid4,
                                   verbose_name='GUID единицы измерения в 1С'),
            preserve_default=False,
        ),
        migrations.AlterField(
            model_name='itempackage',
            name='id',
            field=models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True,
                                   serialize=False,
                                   verbose_name='Идентификатор упаковки товара'),
        ),
        migrations.AlterField(
            model_name='orderitem',
            name='package_id',
            field=models.UUIDField(blank=True, null=True,
                                   verbose_name='GUID единицы измерения в 1С'),
        ),
        migrations.AlterUniqueTogether(
            name='itempackage',
            unique_together={('item', 'guid_1c')},
        ),
    ]
