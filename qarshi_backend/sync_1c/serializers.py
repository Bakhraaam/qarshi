from rest_framework import serializers
from .models import Organization, ItemType, Item, PriceType, PriceList, Order, OrderItem, UserProfile
from front_api.models import TelegramAccount


# 1. Сериализатор для Организаций
class OrganizationSyncSerializer(serializers.ModelSerializer):
    class Meta:
        model = Organization
        fields = ['id', 'inn', 'name']


# 2. Сериализатор для Видов номенклатуры
class ItemTypeSyncSerializer(serializers.ModelSerializer):
    class Meta:
        model = ItemType
        fields = ['id', 'name']


# 3. Сериализатор для Номенклатуры (Товаров)
class ItemSyncSerializer(serializers.ModelSerializer):
    # Принимаем список путей к картинкам как массив строк,
    # write_only=True означает, что поле нужно только для записи данных
    images = serializers.ListField(
        child=serializers.CharField(max_length=512),
        write_only=True,
        required=False
    )

    class Meta:
        model = Item
        fields = ['id', 'item_type', 'articul', 'code', 'name', 'unit', 'images']

    def validate_item_type(self, value):
        """
        Проверяем, прислала ли 1С существующий Вид Номенклатуры.
        Если 1С присылает GUID, которого ещё нет в базе Django,
        вызываем ошибку валидации.
        """
        if value and not ItemType.objects.filter(id=value.id).exists():
            raise serializers.ValidationError("Указанный вид номенклатуры не найден в базе данных бэкенда.")
        return value


# 4. Сериализатор для Видов цен
class PriceTypeSyncSerializer(serializers.ModelSerializer):
    class Meta:
        model = PriceType
        fields = ['id', 'code', 'name', 'currency']

# 5. Сериализатор для Прайс-листов (Цен)
class PriceListSyncSerializer(serializers.Serializer):
    # Используем базовые поля ID, так как это плоская структура для связи товаров и цен
    item_id = serializers.UUIDField()
    price_type_id = serializers.UUIDField()
    price = serializers.DecimalField(max_digits=15, decimal_places=2)

    def validate(self, data):
        """
        Проверяем, что товар и вид цены реально существуют в системе,
        прежде чем записать цену.
        """
        if not Item.objects.filter(id=data['item_id']).exists():
            raise serializers.ValidationError(f"Товар с ID {data['item_id']} не существует.")
        if not PriceType.objects.filter(id=data['price_type_id']).exists():
            raise serializers.ValidationError(f"Вид цены с ID {data['price_type_id']} не существует.")
        return data


# 6. Сериализатор для Заказ-клиентов
class OrderItem1CSerializer(serializers.ModelSerializer):
    """Позиция заказа для выгрузки в 1С"""
    # Отдаем оригинальный UUID товара из 1С, чтобы база 1С сразу сопоставила номенклатуру
    product_id = serializers.UUIDField(source='item.id', read_only=True)

    class Meta:
        model = OrderItem
        fields = ['product_id', 'quantity', 'price', 'total_amount']


class Order1COutputSerializer(serializers.ModelSerializer):
    """Полная структура нового заказа для парсинга на стороне 1С"""
    # Выделяем клиента в отдельный вложенный параметр (объект)
    client = serializers.SerializerMethodField()
    items = OrderItem1CSerializer(many=True, read_only=True)

    class Meta:
        model = Order
        fields = ['id', 'order_number', 'client', 'total_amount', 'status', 'created_at', 'items']

    def get_client(self, obj):
        user = obj.user

        # Безопасно вытягиваем доп. данные из профиля, если они у вас там есть (например, телефон, компания)
        phone = getattr(user.profile, 'phone', '') if hasattr(user, 'profile') else ''
        company_name = getattr(user.profile, 'company_name', '') if hasattr(user, 'profile') else ''

        # Собираем полную анкету, чтобы 1С могла создать контрагента на своей стороне
        return {
            "id": user.profile.id,  # По этому ID 1С проверяет, есть ли уже такой клиент
            "username": user.username,
            "inn": user.profile.inn,
            "first_name": user.first_name,
            "last_name": user.last_name,
            "phone": phone,  # Нужно для связи в 1С
            "name": user.profile.name  # Название фирмы (критично для B2B в 1С)
        }


class Sync1cDirectTelegramUserSerializer(serializers.ModelSerializer):
    """Сериализатор для выгрузки глобальных аккаунтов Telegram напрямую в 1С"""
    # Форматируем даты в удобный для 1С текстовый вид
    created_at = serializers.DateTimeField(format='iso-8601', read_only=True)
    updated_at = serializers.DateTimeField(format='iso-8601', read_only=True)

    class Meta:
        model = TelegramAccount
        fields = [
            'telegram_id',
            'telegram_username',
            'phone',
            'tg_first_name',
            'tg_last_name',
            'tg_photo_url',
            'tg_language_code',
            'created_at',
            'updated_at'
        ]


class UserProfileSerializer(serializers.ModelSerializer):
    """
    Выходной сериализатор профиля.
    Формирует идеальный JSON для Flutter-приложения.
    """
    price_type = serializers.SerializerMethodField()
    tg_avatar = serializers.URLField(source='tg_photo_url', read_only=True)
    tg_username = serializers.CharField(source='telegram_username', read_only=True)
    is_b2b_prices = serializers.SerializerMethodField()
    # account_status_display = serializers.CharField(source='get_status_display', read_only=True)

    class Meta:
        model = UserProfile
        fields = [
            'id',
            'status',
            # 'account_status_display',
            'is_b2b_prices',
            'name',
            'phone',
            'inn',
            'tg_username',
            'tg_avatar',
            'tg_language_code',
            'price_type',
        ]

    # def get_is_b2b_prices(self, obj):
    #     """Возвращает True только если 1С подтвердил аккаунт (статус linked)"""
    #     return obj.status == UserProfile.Status.LINKED

    def get_price_type(self, obj):
        """
        Динамически подставляет тип цен:
        Если подтвержден -> опт из 1С. Если новый/изменен -> розница организации.
        """
        # Достаем организацию, которую наш BaseFrontendAPIView сохранил в контекст запроса
        request = self.context.get('request')
        view = self.context.get('view')
        current_organization = getattr(view, 'current_organization', None)

        if obj.status == UserProfile.Status.LINKED and obj.price_type:
            price_obj = obj.price_type
        elif current_organization:
            price_obj = current_organization.default_price_type
        else:
            price_obj = None

        if price_obj:
            return PriceTypeSyncSerializer(price_obj).data
        return None