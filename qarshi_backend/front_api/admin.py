from django.contrib import admin
from .models import CartItem, TelegramAccount
from django.utils.html import format_html


@admin.register(CartItem)
class CartItemAdmin(admin.ModelAdmin):
    # Колонки, которые будут видны в общей таблице списка корзин
    list_display = ['id', 'user', 'item', 'organization', 'quantity', 'updated_at']

    # Удобные фильтры справа (можно сразу посмотреть корзины конкретного филиала)
    list_filter = ['organization', 'created_at', 'updated_at']

    # Быстрый поиск по имени/логину юзера, названию товара или его артикулу
    search_fields = ['user__username', 'user__first_name', 'item__name', 'item__articul']

    # Поля, доступные только для чтения (чтобы админы случайно не меняли корзины юзеров вручную)
    readonly_fields = ['created_at', 'updated_at']

    # Оптимизация SQL-запросов, чтобы админка не тормозила при тысячах товаров
    raw_id_fields = ['user', 'item']


@admin.register(TelegramAccount)
class TelegramAccountAdmin(admin.ModelAdmin):
    # 📋 Поля, которые будут видны в общей таблице списка аккаунтов
    list_display = (
        'avatar_preview',
        'telegram_id',
        'telegram_username',
        'phone',
        'tg_first_name',
        'tg_last_name',
        'tg_language_code',
        'created_at'
    )

    # 🔗 Поля, при клике на которые открывается карточка редактирования
    list_display_links = ('avatar_preview', 'telegram_id', 'telegram_username')

    # 🔍 Живой поиск по основным текстовым и числовым полям
    search_fields = ('telegram_id', 'telegram_username', 'phone', 'tg_first_name', 'tg_last_name')

    # ⏳ Правый блок фильтрации данных
    list_filter = ('tg_language_code', 'created_at')

    # 🔒 Поля, которые нельзя редактировать вручную (Django управляет ими сам)
    readonly_fields = ('created_at', 'updated_at', 'avatar_large_preview')

    # 🗂️ Красивая блочная группировка полей внутри карточки аккаунта
    fieldsets = (
        ('Системные данные сайта', {
            'fields': ('user', 'telegram_id')
        }),
        ('Контактные данные', {
            'fields': ('phone', 'telegram_username')
        }),
        ('Информация профиля Telegram', {
            'fields': ('tg_first_name', 'tg_last_name', 'tg_language_code')
        }),
        ('Визуальное оформление', {
            'fields': ('tg_photo_url', 'avatar_large_preview')
        }),
        ('Служебные временные метки', {
            'fields': ('created_at', 'updated_at'),
            'classes': ('collapse',),  # Блок скрыт по умолчанию, разворачивается по клику
        }),
    )

    def avatar_preview(self, obj):
        """Создает круглую мини-аватарку в общем списке пользователей"""
        if obj.tg_photo_url:
            return format_html(
                '<img src="{}" style="width: 35px; height: 35px; border-radius: 50%; object-fit: cover; border: 1px solid #ccc;" />',
                obj.tg_photo_url
            )
        return format_html(
            '<div style="width: 35px; height: 35px; border-radius: 50%; background: #e0e0e0; display: inline-block;"></div>')

    avatar_preview.short_description = "Фото"

    def avatar_large_preview(self, obj):
        """Показывает крупное изображение аватарки внутри карточки пользователя"""
        if obj.tg_photo_url:
            return format_html(
                '<img src="{}" style="max-width: 150px; max-height: 150px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.15);" />',
                obj.tg_photo_url
            )
        return "Аватарка отсутствует"

    avatar_large_preview.short_description = "Превью аватара"