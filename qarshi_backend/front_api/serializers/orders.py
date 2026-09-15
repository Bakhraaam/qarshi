from rest_framework import serializers
from sync_1c.models import Order, OrderItem
from front_api.serializers.catalog import FrontendProductListSerializer


class OrderItemOutputSerializer(serializers.ModelSerializer):
    """Отображение товара внутри конкретного заказа (исторические данные)"""
    product = FrontendProductListSerializer(source='item', read_only=True)

    class Meta:
        model = OrderItem
        # package_* — снимок упаковки на момент заказа: quantity всё так же в базовых
        # единицах, а эти поля позволяют показать «2 коробки по 10 шт».
        fields = ['product', 'quantity', 'price', 'discount', 'total_amount',
                  'package_id', 'package_name', 'package_ratio', 'package_count']


class OrderListSerializer(serializers.ModelSerializer):
    """Формат для общего списка заказов в личном кабинете Flutter"""
    items_count = serializers.SerializerMethodField()

    class Meta:
        model = Order
        fields = ['id', 'order_number', 'status', 'total_amount', 'items_count', 'created_at']

    def get_items_count(self, obj):
        # Считаем общее количество штук товаров в заказе
        return sum(item.quantity for item in obj.items.all())


class OrderDetailSerializer(serializers.ModelSerializer):
    """Полный формат заказа со всеми вложенными позициями"""
    items = OrderItemOutputSerializer(many=True, read_only=True)
    status_display = serializers.CharField(source='get_status_display', read_only=True)

    payment_method_display = serializers.CharField(source='get_payment_method_display', read_only=True)

    class Meta:
        model = Order
        fields = ['id', 'order_number', 'status', 'status_display', 'total_amount', 'items',
                  'delivery_date', 'payment_method', 'payment_method_display', 'comment',
                  'created_at', 'updated_at']