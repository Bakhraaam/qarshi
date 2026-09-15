from django.contrib import admin
from django.db.models import Count, OuterRef, Subquery
from django.utils.html import format_html
from front_api.cache import bump_catalog_version
from .models import Organization, ItemType, Item, ItemImage, ItemPackage, PriceType, PriceList, UserProfile, OrderItem, Order, ItemStock


# Платформа мультифилиальная: почти у каждой таблицы есть организация,
# поэтому фильтр по организации стоит первым в правой панели везде, где поле есть.


@admin.register(Organization)
class OrganizationAdmin(admin.ModelAdmin):
    # Какие колонки показывать в общем списке
    list_display = ('prefix', 'name', 'inn', 'support_phone', 'has_bot',
                    'items_count', 'profiles_count', 'id')
    list_display_links = ('prefix', 'name')
    # По каким полям искать (работает как живой поиск)
    search_fields = ('name', 'inn', 'prefix', 'id')
    ordering = ('prefix',)
    list_per_page = 50

    fieldsets = [
        ('Реквизиты филиала', {
            'fields': ('id', 'prefix', 'name', 'inn')
        }),
        ('Контакты для клиентов', {
            'fields': ('support_phone', 'instagram', 'unregistered_notice')
        }),
        ('Telegram-бот филиала', {
            'fields': ('telegram_bot_token',)
        }),
    ]
    readonly_fields = ('id',)

    def get_queryset(self, request):
        # Счётчики считаем в одном запросе, иначе на каждую строку будет по два SELECT
        return super().get_queryset(request).annotate(
            _items_count=Count('items', distinct=True),
            _profiles_count=Count('profiles', distinct=True),
        )

    @admin.display(description="Товаров", ordering='_items_count')
    def items_count(self, obj):
        return obj._items_count

    @admin.display(description="Контрагентов", ordering='_profiles_count')
    def profiles_count(self, obj):
        return obj._profiles_count

    @admin.display(description="Бот", boolean=True)
    def has_bot(self, obj):
        # Сам токен в списке не показываем — это секрет, достаточно факта «подключён»
        return bool(obj.telegram_bot_token)


# Настройка отображения картинок прямо внутри карточки товара (Inlines)
class ItemImageInline(admin.TabularInline):
    model = ItemImage
    extra = 1  # Количество пустых полей для добавления новых картинок вручную
    readonly_fields = ['preview']
    fields = ['image_path', 'is_main', 'is_invalid', 'preview']

    @admin.display(description="Предпросмотр")
    def preview(self, obj):
        if obj.image_path:
            # image_path — ImageField, ссылку берём через .url (с учётом MEDIA_URL)
            return format_html(
                '<img src="{}" width="60" height="60" style="object-fit: contain;" />',
                obj.image_path.url,
            )
        return "Нет картинки"


# Упаковки товара (блок, коробка) — редактируются прямо внутри карточки товара
class ItemPackageInline(admin.TabularInline):
    model = ItemPackage
    extra = 0
    fields = ['name', 'quantity', 'is_default', 'is_invalid', 'guid_1c']
    readonly_fields = ['guid_1c']


# Настройка отображения цен внутри карточки товара
class PriceListInline(admin.TabularInline):
    model = PriceList
    extra = 0

    # ИСПРАВЛЕНО: Добавили колонку 'organization' и 'period' (дата из 1С)
    fields = ['price_type', 'organization', 'price', 'updated_at']

    # Защищаем данные синхронизации от случайного ручного изменения контент-менеджерами
    readonly_fields = ['price_type', 'organization', 'price', 'updated_at']

    verbose_name = "Цена товара"
    verbose_name_plural = "Цены товара (Прайс-листы)"


@admin.register(ItemType)
class ItemTypeAdmin(admin.ModelAdmin):
    list_display = ('name', 'organization', 'items_count', 'is_invalid', 'id')
    list_display_links = ('name',)
    list_filter = ('organization', 'is_invalid')
    search_fields = ('name', 'id')
    # Галочку «недействителен» можно переключать прямо из списка категорий
    list_editable = ('is_invalid',)
    list_select_related = ('organization',)
    ordering = ('organization', 'name')
    list_per_page = 50

    def get_queryset(self, request):
        return super().get_queryset(request).annotate(_items_count=Count('items'))

    @admin.display(description="Товаров", ordering='_items_count')
    def items_count(self, obj):
        return obj._items_count

    def save_model(self, request, obj, form, change):
        # Скрытая категория убирает с витрины и все свои товары,
        # поэтому кэш каталога надо сбросить сразу.
        super().save_model(request, obj, form, change)
        bump_catalog_version(obj.organization_id)


@admin.register(Item)
class ItemAdmin(admin.ModelAdmin):
    list_display = ('preview', 'articul', 'code', 'name', 'organization', 'item_type',
                    'unit', 'stock_display', 'images_count', 'is_invalid', 'updated_at')
    list_display_links = ('preview', 'name')
    search_fields = ('articul', 'code', 'name', 'id')
    # Фильтры в правой панели админки
    list_filter = ('organization', 'is_invalid', 'item_type', 'unit', 'updated_at')
    # Галочку «недействителен» можно переключать прямо из списка товаров
    list_editable = ('is_invalid',)
    list_select_related = ('organization', 'item_type')
    ordering = ('organization', 'name')
    list_per_page = 50
    readonly_fields = ('id', 'updated_at')
    # Подключаем inline-блоки, чтобы картинки и цены редактировались прямо внутри товара
    inlines = [ItemImageInline, ItemPackageInline, PriceListInline]

    fieldsets = [
        ('Идентификация в 1С', {
            'fields': ('id', 'articul', 'code')
        }),
        ('Карточка товара', {
            'fields': ('name', 'item_type', 'unit', 'organization')
        }),
        ('Публикация на сайте', {
            'fields': ('is_invalid',),
            'description': 'Недействительный товар полностью скрыт из каталога сайта. '
                           'Товар с нулевым остатком скрывается автоматически.'
        }),
        ('Служебное', {
            'fields': ('updated_at',),
            'classes': ('collapse',),
        }),
    ]

    def get_queryset(self, request):
        # Остаток и число картинок — подзапросами, чтобы список не делал по 2 запроса на строку.
        stock_subquery = ItemStock.objects.filter(
            item=OuterRef('pk'), organization=OuterRef('organization')
        ).values('stock')[:1]

        # prefetch картинок — чтобы колонка с фото не делала запрос на каждую строку
        return super().get_queryset(request).prefetch_related('images').annotate(
            _stock=Subquery(stock_subquery),
            _images_count=Count('images'),
        )

    @admin.display(description="Фото")
    def preview(self, obj):
        # Читаем из prefetch: .first() сделал бы отдельный запрос на каждую строку
        images = list(obj.images.all())
        image = next((i for i in images if i.is_main), None) or (images[0] if images else None)
        if image and image.image_path:
            return format_html(
                '<img src="{}" width="46" height="46" style="object-fit: contain;" />',
                image.image_path.url,
            )
        return "—"

    @admin.display(description="Остаток", ordering='_stock')
    def stock_display(self, obj):
        if obj._stock is None:
            return "нет записи"
        # Остаток — Decimal(12,2): «200.00» читается плохо, показываем «200» и «1.5»
        amount = f"{obj._stock:.2f}".rstrip('0').rstrip('.')
        return f"{amount} {obj.unit or ''}".strip()

    @admin.display(description="Фото, шт", ordering='_images_count')
    def images_count(self, obj):
        return obj._images_count

    def save_model(self, request, obj, form, change):
        # Ручная правка товара (в т.ч. галочки «недействителен» прямо в списке)
        # должна сразу отражаться на сайте, а не ждать TTL кэша каталога.
        super().save_model(request, obj, form, change)
        bump_catalog_version(obj.organization_id)


@admin.register(PriceType)
class PriceTypeAdmin(admin.ModelAdmin):
    list_display = ('name', 'code', 'currency', 'organization', 'is_default', 'prices_count', 'id')
    list_display_links = ('name',)
    search_fields = ('name', 'code', 'id')
    list_filter = ('organization', 'currency', 'is_default')
    list_select_related = ('organization',)
    ordering = ('organization', 'name')
    list_per_page = 50

    def get_queryset(self, request):
        return super().get_queryset(request).annotate(_prices_count=Count('prices'))

    @admin.display(description="Позиций в прайсе", ordering='_prices_count')
    def prices_count(self, obj):
        return obj._prices_count


@admin.register(PriceList)
class PriceListAdmin(admin.ModelAdmin):
    # Что отображать в общей таблице всех цен
    list_display = ['item_articul', 'item', 'organization', 'price_type', 'price',
                    'currency', 'updated_at']
    list_display_links = ['item']

    # Мощные фильтры справа: можно в один клик отфильтровать прайсы конкретной фирмы или конкретный тип цен (Опт/Розница)
    list_filter = ['organization', 'price_type', 'updated_at']

    # Быстрый поиск цен по названию товара, артикулу или коду
    # (было item__article — такого поля нет, поиск падал с ошибкой)
    search_fields = ['item__name', 'item__articul', 'item__code']

    list_select_related = ['item', 'price_type', 'organization']
    ordering = ['-updated_at']
    list_per_page = 50

    # Полностью закрываем от греха подальше для ручного редактирования
    readonly_fields = ['item', 'price_type', 'organization', 'price', 'updated_at']

    @admin.display(description="Артикул", ordering='item__articul')
    def item_articul(self, obj):
        return obj.item.articul or obj.item.code or "—"

    @admin.display(description="Валюта")
    def currency(self, obj):
        return obj.price_type.currency


@admin.register(UserProfile)
class UserProfileAdmin(admin.ModelAdmin):
    list_display = ('name', 'user', 'organization', 'price_type', 'inn',
                    'is_linked_to_1c', 'is_blocked', 'id')
    list_display_links = ('name', 'user')
    list_filter = ('organization', 'is_blocked', 'price_type')
    search_fields = ('name', 'inn', 'guid_partner1c', 'user__username')
    list_select_related = ('user', 'organization', 'price_type')
    ordering = ('organization', 'name')
    list_per_page = 50

    @admin.display(description="Привязан к 1С", boolean=True)
    def is_linked_to_1c(self, obj):
        # Пока guid_partner1c пуст, клиент считается незарегистрированным и не может заказывать
        return bool(obj.guid_partner1c and obj.guid_partner1c.strip())


class OrderItemInline(admin.TabularInline):
    model = OrderItem
    # ИСПРАВЛЕНО: Добавили скидку, флаг отмены и причину в список колонок
    fields = ['item', 'quantity', 'package_display', 'price', 'discount', 'total_amount', 'is_canceled', 'cancellation_reason']

    # Все поля делаем только для чтения, чтобы случайно не сломать данные синхронизации
    readonly_fields = ['item', 'quantity', 'package_display', 'price', 'discount', 'total_amount',
                       'is_canceled', 'cancellation_reason']
    extra = 0

    @admin.display(description="Упаковка")
    def package_display(self, obj):
        # quantity выше всегда в базовых единицах — здесь показываем, чем клиент набирал.
        if not obj.package_name:
            return "—"
        return f"{obj.package_count:g} × {obj.package_name} (по {obj.package_ratio:g})"

    def get_queryset(self, request):
        return super().get_queryset(request).select_related('item')


@admin.register(Order)
class OrderAdmin(admin.ModelAdmin):
    # ИСПРАВЛЕНО: Вывели 'order_number_1c' в общий список заказов для удобства
    list_display = ['order_number', 'order_number_1c', 'organization', 'client', 'user',
                    'status', 'positions_count', 'total_amount', 'delivery_date', 'created_at']
    list_display_links = ['order_number', 'order_number_1c']

    list_filter = ['organization', 'status', 'payment_method', 'delivery_date', 'created_at']
    date_hierarchy = 'created_at'

    # ИСПРАВЛЕНО: Теперь искать заказы можно и по номеру из 1С тоже
    search_fields = ['id', 'order_number', 'order_number_1c', 'user__username', 'user__email']
    inlines = [OrderItemInline]
    list_select_related = ['user', 'organization']
    list_per_page = 50

    # Номер 1С делает сам робот, поэтому админу его редактировать вручную нельзя
    readonly_fields = ['id', 'order_number', 'order_number_1c', 'total_amount', 'created_at', 'updated_at']

    fieldsets = [
        ('Системные данные', {
            'fields': ('id',)
        }),
        ('Основная информация', {
            # ИСПРАВЛЕНО: Разместили номер сайта и номер 1С рядом в одном блоке
            'fields': ('order_number', 'order_number_1c', 'organization', 'user', 'status')
        }),
        ('Пожелания клиента', {
            'fields': ('delivery_date', 'payment_method', 'comment')
        }),
        ('Финансовые итоги', {
            'fields': ('total_amount',)
        }),
        ('Временные метки', {
            'fields': ('created_at', 'updated_at')
        }),
    ]

    def get_queryset(self, request):
        # prefetch профилей — колонка «Контрагент» иначе делает запрос на каждую строку
        return super().get_queryset(request) \
            .prefetch_related('user__profile') \
            .annotate(_positions=Count('items'))

    @admin.display(description="Позиций", ordering='_positions')
    def positions_count(self, obj):
        return obj._positions

    @admin.display(description="Контрагент")
    def client(self, obj):
        # Наименование контрагента из профиля этого же филиала — по логину заказ не опознать
        # Читаем из prefetch: .filter() по связи сбросил бы кэш и дал запрос на строку
        profile = next(
            (p for p in obj.user.profile.all() if p.organization_id == obj.organization_id),
            None,
        )
        return profile.name if profile and profile.name else "—"


class ItemStockInline(admin.TabularInline):
    model = ItemStock
    fields = ['organization', 'stock', 'updated_at']

    # Делаем только для чтения, так как данные управляются автоматикой 1С
    readonly_fields = ['organization', 'stock', 'updated_at']
    extra = 0
    verbose_name = "Остаток в организации"
    verbose_name_plural = "Остатки в организациях"


@admin.register(ItemStock)
class ItemStockAdmin(admin.ModelAdmin):
    # Колонки в общем списке
    list_display = ['item_articul', 'item', 'organization', 'stock', 'unit', 'updated_at']
    list_display_links = ['item']

    # Удобные фильтры справа (можно кликнуть на конкретную фирму и увидеть её склад)
    list_filter = ['organization', 'updated_at']

    # Поиск по названию товара, артикулу или коду
    # (было item__article — такого поля нет, поиск падал с ошибкой)
    search_fields = ['item__name', 'item__articul', 'item__code']

    list_select_related = ['item', 'organization']
    ordering = ['-updated_at']
    list_per_page = 50

    readonly_fields = ['item', 'organization', 'stock', 'updated_at']

    @admin.display(description="Артикул", ordering='item__articul')
    def item_articul(self, obj):
        return obj.item.articul or obj.item.code or "—"

    @admin.display(description="Ед. изм.")
    def unit(self, obj):
        return obj.item.unit or "—"


@admin.register(ItemImage)
class ItemImageAdmin(admin.ModelAdmin):
    # Колонки в общем списке
    list_display = ['preview', 'item', 'organization', 'is_main', 'is_invalid', 'image_path', 'created_at']
    list_display_links = ['preview', 'item']
    list_filter = ['item__organization', 'is_main', 'is_invalid', 'created_at']
    search_fields = ['item__name', 'item__articul', 'item__code']
    list_select_related = ['item', 'item__organization']
    ordering = ['-created_at']
    list_per_page = 50
    list_editable = ['is_invalid']
    readonly_fields = ['created_at', 'large_preview']

    @admin.display(description="Фото")
    def preview(self, obj):
        if obj.image_path:
            return format_html(
                '<img src="{}" width="46" height="46" style="object-fit: contain;" />',
                obj.image_path.url,
            )
        return "—"

    @admin.display(description="Предпросмотр")
    def large_preview(self, obj):
        if obj.image_path:
            return format_html(
                '<img src="{}" style="max-width: 260px; max-height: 260px;" />',
                obj.image_path.url,
            )
        return "Нет картинки"

    @admin.display(description="Организация", ordering='item__organization')
    def organization(self, obj):
        return obj.item.organization


@admin.register(ItemPackage)
class ItemPackageAdmin(admin.ModelAdmin):
    list_display = ['name', 'item', 'quantity', 'base_unit', 'is_default', 'is_invalid', 'guid_1c']
    list_display_links = ['name']
    list_filter = ['item__organization', 'is_default', 'is_invalid']
    list_editable = ['is_default', 'is_invalid']
    search_fields = ['name', 'item__name', 'item__articul', 'item__code', 'id', 'guid_1c']
    list_select_related = ['item']
    ordering = ['item__name', 'quantity']
    list_per_page = 50
    readonly_fields = ['id', 'guid_1c']

    @admin.display(description="Базовая единица")
    def base_unit(self, obj):
        return obj.item.unit or "—"
