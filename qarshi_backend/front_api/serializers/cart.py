from rest_framework import serializers
from sync_1c.models import Item
from front_api.models import CartItem
from front_api.serializers.catalog import FrontendProductListSerializer, resolve_item_price

class CartItemOutputSerializer(serializers.ModelSerializer):
    """Окончательный формат позиции корзины с вложенным готовым сериализатором товара"""
    product = FrontendProductListSerializer(source='item', read_only=True)
    # Оставляем имя поля quantity, чтобы оно строго совпадало с Meta.fields и вашей View
    quantity = serializers.IntegerField(read_only=True)
    price = serializers.SerializerMethodField()
    total = serializers.SerializerMethodField()

    class Meta:
        model = CartItem
        fields = ['product', 'quantity', 'price', 'total']

    def get_price(self, obj):
        # Считаем цену напрямую из подгруженных данных, без повторной сериализации товара.
        return resolve_item_price(obj.item, self.context.get('price_type_id'))

    def get_total(self, obj):
        # Персональная цена товара * количество из корзины
        return self.get_price(obj) * obj.quantity