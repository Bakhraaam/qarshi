from rest_framework import serializers
# Импортируем наши модели из домена sync_1c
from sync_1c.models import Item, ItemType, ItemImage, PriceList


# --- Единые помощники: читают из УЖЕ подгруженных (prefetch_related) связей в памяти ---
# Никаких .filter() по связи — он сбрасывает кэш prefetch и делает лишний запрос на КАЖДЫЙ товар.
# Чтобы это работало без N+1, во вьюхе нужен prefetch_related('images', 'prices__price_type', 'stocks').

def resolve_item_price(item, price_type_id=None):
    """Цена товара: сначала под нужный вид цены, иначе розница RETAIL, иначе первая доступная."""
    prices = list(item.prices.all())
    if not prices:
        return 0.0
    if price_type_id:
        for p in prices:
            if str(p.price_type_id) == str(price_type_id):
                return float(p.price)
    for p in prices:
        if p.price_type and p.price_type.code == 'RETAIL':
            return float(p.price)
    return float(prices[0].price)


def resolve_item_image_url(item, request=None):
    """URL главной (или первой) картинки. Картинки идут в порядке -is_main, created_at."""
    images = list(item.images.all())
    main_img = next((i for i in images if i.is_main), None) or (images[0] if images else None)
    if main_img and main_img.image_path:
        if request:
            return request.build_absolute_uri(main_img.image_path.url)
        return main_img.image_path.url
    return None


def resolve_item_stock(item):
    """Остаток строго для организации товара (из подгруженных stocks, без новых запросов)."""
    for stock_record in item.stocks.all():
        if stock_record.organization_id == item.organization_id:
            return float(stock_record.stock)
    return 0.0


class FrontendCategorySerializer(serializers.ModelSerializer):
    """Сериализатор категорий (видов номенклатуры) для Flutter"""
    class Meta:
        model = ItemType
        fields = ['id', 'name']


class FrontendPriceSerializer(serializers.ModelSerializer):
    """Сериализатор актуальных цен товара"""
    price_type_name = serializers.CharField(source='price_type.name', read_only=True)
    currency = serializers.CharField(source='price_type.currency', read_only=True)

    class Meta:
        model = PriceList
        fields = ['price', 'currency', 'price_type_name']


class FrontendProductImageSerializer(serializers.ModelSerializer):
    """Сериализатор всех картинок для галереи в карточке товара"""
    class Meta:
        model = ItemImage
        fields = ['id', 'image_path', 'is_main']


class FrontendProductListSerializer(serializers.ModelSerializer):
    """ЛЕГКИЙ формат товара для общей сетки каталога и корзины"""
    # Добавляем ID категории (UUID)
    # category_id = serializers.UUIDField(source='item_type.id', read_only=True)
    # category_name = serializers.CharField(source='item_type.name', read_only=True)
    category_id = serializers.SerializerMethodField()
    category_name = serializers.SerializerMethodField()
    image_url = serializers.SerializerMethodField()
    price = serializers.SerializerMethodField()
    stock = serializers.SerializerMethodField()

    class Meta:
        model = Item
        fields = ['id', 'articul', 'code', 'name', 'unit', 'category_id', 'category_name',
                  'image_url', 'price', 'stock']

    def get_category_id(self, obj):
        # Безопасно проверяем: если связь есть — возвращаем строковый UUID, если нет — null
        return str(obj.item_type.id) if obj.item_type else None

    def get_category_name(self, obj):
        # Безопасно возвращаем имя категории или null
        return obj.item_type.name if obj.item_type else None

    def get_image_url(self, obj):
        return resolve_item_image_url(obj, self.context.get('request'))

    def get_price(self, obj):
        # Нужный вид цены (B2B под пользователя или розница филиала) вьюха резолвит ОДИН раз
        # и кладёт в контекст как price_type_id — здесь только выбираем из памяти.
        return resolve_item_price(obj, self.context.get('price_type_id'))

    def get_stock(self, obj):
        return resolve_item_stock(obj)