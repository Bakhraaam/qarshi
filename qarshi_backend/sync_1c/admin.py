from django.contrib import admin
from django.utils.safestring import mark_safe
from .models import Organization, ItemType, Item, ItemImage, PriceType, PriceList, UserProfile, OrderItem, Order, ItemStock


@admin.register(Organization)
class OrganizationAdmin(admin.ModelAdmin):
    # Какие колонки показывать в общем списке
    list_display = ('prefix', 'name', 'inn', 'id')
    # По каким полям искать (работает как живой поиск)
    search_fields = ('name', 'inn', 'id')


# Настройка отображения картинок прямо внутри карточки товара (Inlines)
class ItemImageInline(admin.TabularInline):
    model = ItemImage
    extra = 1  # Количество пустых полей для добавления новых картинок вручную
    readonly_fields = ['preview']
    fields = ['image_path', 'is_main', 'preview']

    def preview(self, obj):
        if obj.image_path:
            # Если 1С передает относительный путь или URL, показываем превью в админке
            return mark_safe(f'<img src="{obj.image_path}" width="50" height="50" style="object-fit: contain;" />')
        return "Нет картинки"
    preview.short_description = "Предпросмотр"


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
    list_display = ('name', 'id')
    search_fields = ('name', 'id')


@admin.register(Item)
class ItemAdmin(admin.ModelAdmin):
    list_display = ('articul', 'code', 'name', 'item_type', 'unit', 'id')
    search_fields = ('articul', 'code', 'name', 'id')
    # Фильтры в правой панели админки
    list_filter = ('item_type', 'unit')
    # Подключаем inline-блоки, чтобы картинки и цены редактировались прямо внутри товара
    inlines = [ItemImageInline, PriceListInline]


@admin.register(PriceType)
class PriceTypeAdmin(admin.ModelAdmin):
    list_display = ('name', 'code', 'currency', 'id', 'is_default')
    search_fields = ('name', 'code', 'id')
    list_filter = ('currency',)


@admin.register(PriceList)
class PriceListAdmin(admin.ModelAdmin):
    # Что отображать в общей таблице всех цен
    list_display = ['item', 'price_type', 'organization', 'price', 'updated_at']

    # Мощные фильтры справа: можно в один клик отфильтровать прайсы конкретной фирмы или конкретный тип цен (Опт/Розница)
    list_filter = ['price_type', 'organization', 'updated_at']

    # Быстрый поиск цен по названию запчасти или её артикулу
    search_fields = ['item__name', 'item__article']

    # Полностью закрываем от греха подальше для ручного редактирования
    readonly_fields = ['item', 'price_type', 'organization', 'price', 'updated_at']


@admin.register(UserProfile)
class UserProfileAdmin(admin.ModelAdmin):
    list_display = ('name', 'user', 'organization', 'price_type', 'guid_partner1c', 'is_blocked', 'id')
    list_filter = ('organization', 'is_blocked')
    search_fields = ('name', 'inn', 'guid_partner1c', 'user__username')


class OrderItemInline(admin.TabularInline):
    model = OrderItem
    # ИСПРАВЛЕНО: Добавили скидку, флаг отмены и причину в список колонок
    fields = ['item', 'quantity', 'price', 'discount', 'total_amount', 'is_canceled', 'cancellation_reason']

    # Все поля делаем только для чтения, чтобы случайно не сломать данные синхронизации
    readonly_fields = ['item', 'quantity', 'price', 'discount', 'total_amount', 'is_canceled', 'cancellation_reason']
    extra = 0


@admin.register(Order)
class OrderAdmin(admin.ModelAdmin):
    # ИСПРАВЛЕНО: Вывели 'order_number_1c' в общий список заказов для удобства
    list_display = ['id', 'order_number', 'order_number_1c', 'user', 'status', 'total_amount', 'created_at']

    list_filter = ['status', 'created_at']

    # ИСПРАВЛЕНО: Теперь искать заказы можно и по номеру из 1С тоже
    search_fields = ['id', 'order_number', 'order_number_1c', 'user__username', 'user__email']
    inlines = [OrderItemInline]

    # Номер 1С делает сам робот, поэтому админу его редактировать вручную нельзя
    readonly_fields = ['id', 'order_number', 'order_number_1c', 'total_amount', 'created_at', 'updated_at']

    fieldsets = [
        ('Системные данные', {
            'fields': ('id',)
        }),
        ('Основная информация', {
            # ИСПРАВЛЕНО: Разместили номер сайта и номер 1С рядом в одном блоке
            'fields': ('order_number', 'order_number_1c', 'user', 'status')
        }),
        ('Финансовые итоги', {
            'fields': ('total_amount',)
        }),
        ('Временные метки', {
            'fields': ('created_at', 'updated_at')
        }),
    ]


class ItemStockInline(admin.TabularInline):
    model = ItemStock
    fields = ['organization', 'stock']

    # Делаем только для чтения, так как данные управляются автоматикой 1С
    readonly_fields = ['organization', 'stock']
    extra = 0
    verbose_name = "Остаток в организации"
    verbose_name_plural = "Остатки в организациях"


@admin.register(ItemStock)
class ItemStockAdmin(admin.ModelAdmin):
    # Колонки в общем списке
    list_display = ['item', 'organization', 'stock']

    # Удобные фильтры справа (можно кликнуть на конкретную фирму и увидеть её склад)
    list_filter = ['organization']

    # Поиск по названию товара или его артикулу/коду
    search_fields = ['item__name', 'item__article']

    readonly_fields = ['item', 'organization', 'stock']


@admin.register(ItemImage)
class ItemImageAdmin(admin.ModelAdmin):
    # Колонки в общем списке
    list_display = ['item', 'image_path']