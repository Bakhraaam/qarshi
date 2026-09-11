from rest_framework import serializers
from sync_1c.models import Item
from front_api.models import CartItem
from front_api.serializers.catalog import FrontendProductListSerializer, resolve_item_price


class CartItemOutputSerializer(serializers.ModelSerializer):
    """Окончательный формат позиции корзины с вложенным готовым сериализатором товара"""
    product = FrontendProductListSerializer(source='item', read_only=True)
    # quantity всегда в БАЗОВЫХ единицах товара. Отдаём числом, а не строкой:
    # DecimalField в DRF по умолчанию сериализуется в "5.000", и Flutter парсил бы текст.
    quantity = serializers.SerializerMethodField()
    price = serializers.SerializerMethodField()
    total = serializers.SerializerMethodField()
    # Упаковка, которой клиент набирал позицию (null = базовая единица).
    package_id = serializers.SerializerMethodField()

    class Meta:
        model = CartItem
        fields = ['product', 'quantity', 'price', 'total', 'package_id']

    def get_quantity(self, obj):
        return float(obj.quantity)

    def get_price(self, obj):
        # Считаем цену напрямую из подгруженных данных, без повторной сериализации товара.
        return resolve_item_price(obj.item, self.context.get('price_type_id'))

    def get_total(self, obj):
        # Персональная цена за базовую единицу * количество базовых единиц
        return self.get_price(obj) * float(obj.quantity)

    def get_package_id(self, obj):
        # Упаковку могли удалить синхронизацией — тогда позиция просто вернётся к базовой единице.
        if obj.package_id and obj.package and not obj.package.is_invalid:
            return str(obj.package_id)
        return None
