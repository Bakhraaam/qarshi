from rest_framework import serializers
from front_api.models import CartItem
from front_api.serializers.catalog import FrontendProductListSerializer, resolve_item_price


class CartItemOutputSerializer(serializers.ModelSerializer):
    """Строка корзины. Один товар может быть в корзине несколькими строками —
    по одной на каждую единицу, в которой его набрали («5 коробок» и «3 шт»)."""
    product = FrontendProductListSerializer(source='item', read_only=True)
    # quantity всегда в БАЗОВЫХ единицах товара. Отдаём числом, а не строкой:
    # DecimalField в DRF по умолчанию сериализуется в "5.000", и Flutter парсил бы текст.
    quantity = serializers.SerializerMethodField()
    # Цена за базовую единицу — как в прайсе.
    price = serializers.SerializerMethodField()
    total = serializers.SerializerMethodField()
    # Единица строки (null = базовая единица).
    package_id = serializers.SerializerMethodField()
    # Упаковка строки целиком. Отдаём её здесь, а не заставляем фронт искать в
    # product.packages: там нет недействительных упаковок, а строка с ней в корзине
    # остаётся и должна показываться своей единицей.
    package = serializers.SerializerMethodField()

    class Meta:
        model = CartItem
        fields = ['product', 'quantity', 'price', 'total', 'package_id', 'package']

    def get_quantity(self, obj):
        return float(obj.quantity)

    def get_price(self, obj):
        # Считаем цену напрямую из подгруженных данных, без повторной сериализации товара.
        return resolve_item_price(obj.item, self.context.get('price_type_id'))

    def get_total(self, obj):
        # Персональная цена за базовую единицу * количество базовых единиц
        return self.get_price(obj) * float(obj.quantity)

    def get_package_id(self, obj):
        return str(obj.package_id) if obj.package_id else None

    def get_package(self, obj):
        if not obj.package_id:
            return None
        return {
            'id': str(obj.package_id),
            'name': obj.package.name,
            'quantity': float(obj.package.quantity),
        }
