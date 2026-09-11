from rest_framework import serializers
# Импортируем наши модели из домена sync_1c
from sync_1c.models import Item, ItemType, ItemImage, ItemPackage, PriceList


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


def _valid_images(item):
    """Картинки, которые можно показывать: 1С могла пометить часть как недействительные
    (файл битый/товар переснят), и такие в каталог не идут. Фильтруем в памяти —
    .filter() по связи сбросил бы prefetch и дал N+1."""
    return [img for img in item.images.all() if not img.is_invalid and img.image_path]


def resolve_item_image_url(item, request=None):
    """URL главной (или первой) картинки. Картинки идут в порядке -is_main, created_at."""
    images = _valid_images(item)
    main_img = next((i for i in images if i.is_main), None) or (images[0] if images else None)
    if main_img:
        if request:
            return request.build_absolute_uri(main_img.image_path.url)
        return main_img.image_path.url
    return None


def resolve_item_image_urls(item, request=None):
    """Все картинки товара в порядке модели (-is_main, created_at) — для галереи в карточке."""
    urls = []
    for img in _valid_images(item):
        url = img.image_path.url
        urls.append(request.build_absolute_uri(url) if request else url)
    return urls


def resolve_item_packages(item):
    """Упаковки товара для фронта: базовой единицы тут нет — она и так в поле `unit`.
    Цена всегда за базовую единицу, `quantity` — множитель («Коробка» = 10 шт)."""
    packages = []
    for pkg in item.packages.all():
        if pkg.is_invalid:
            continue
        packages.append({
            'id': str(pkg.id),
            'name': pkg.name,
            'quantity': float(pkg.quantity),
            'is_default': pkg.is_default,
        })
    return packages


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
        fields = ['id', 'image_path', 'is_main', 'is_invalid']


class FrontendProductListSerializer(serializers.ModelSerializer):
    """ЛЕГКИЙ формат товара для общей сетки каталога и корзины"""
    # Добавляем ID категории (UUID)
    # category_id = serializers.UUIDField(source='item_type.id', read_only=True)
    # category_name = serializers.CharField(source='item_type.name', read_only=True)
    category_id = serializers.SerializerMethodField()
    category_name = serializers.SerializerMethodField()
    image_url = serializers.SerializerMethodField()
    # Полный список картинок: карточка каталога листает их прямо в сетке,
    # экран товара показывает ту же галерею без дополнительного запроса.
    images = serializers.SerializerMethodField()
    price = serializers.SerializerMethodField()
    stock = serializers.SerializerMethodField()
    # Варианты фасовки сверх базовой единицы: блок, коробка и т.п.
    packages = serializers.SerializerMethodField()

    class Meta:
        model = Item
        fields = ['id', 'articul', 'code', 'name', 'unit', 'category_id', 'category_name',
                  'image_url', 'images', 'price', 'stock', 'packages']

    def get_category_id(self, obj):
        # Безопасно проверяем: если связь есть — возвращаем строковый UUID, если нет — null
        return str(obj.item_type.id) if obj.item_type else None

    def get_category_name(self, obj):
        # Безопасно возвращаем имя категории или null
        return obj.item_type.name if obj.item_type else None

    def get_image_url(self, obj):
        return resolve_item_image_url(obj, self.context.get('request'))

    def get_images(self, obj):
        return resolve_item_image_urls(obj, self.context.get('request'))

    def get_price(self, obj):
        # Нужный вид цены (B2B под пользователя или розница филиала) вьюха резолвит ОДИН раз
        # и кладёт в контекст как price_type_id — здесь только выбираем из памяти.
        return resolve_item_price(obj, self.context.get('price_type_id'))

    def get_stock(self, obj):
        return resolve_item_stock(obj)

    def get_packages(self, obj):
        return resolve_item_packages(obj)


class FrontendProductDetailSerializer(FrontendProductListSerializer):
    """Карточка товара (GET products/<id>/): то же, что в сетке, плюс валюта цены."""
    currency = serializers.SerializerMethodField()

    class Meta(FrontendProductListSerializer.Meta):
        fields = FrontendProductListSerializer.Meta.fields + ['currency']

    def get_currency(self, obj):
        price_type_id = self.context.get('price_type_id')
        for p in obj.prices.all():
            if p.price_type and str(p.price_type_id) == str(price_type_id):
                return p.price_type.currency
        return ''


class FrontendItemPackageSerializer(serializers.ModelSerializer):
    """Упаковка товара: `quantity` — сколько базовых единиц в одной упаковке."""
    class Meta:
        model = ItemPackage
        fields = ['id', 'name', 'quantity', 'is_default']
