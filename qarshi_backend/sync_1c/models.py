import uuid
import random
from django.db import models
from django.conf import settings
from django.contrib.auth.models import User
from django.contrib.auth import get_user_model
from django.utils import timezone


# 1. Организации
class Organization(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False, verbose_name="Уникальный Идентификатор 1С")
    inn = models.CharField(max_length=12, verbose_name="ИНН")
    name = models.CharField(max_length=255, verbose_name="Наименование")
    prefix = models.CharField(max_length=50, unique=True, null=True, blank=True,
                              verbose_name="Уникальный префикс (slug)")

    support_phone = models.CharField(max_length=15, default="", verbose_name="Телефон служба поддержки")
    instagram = models.CharField(
        max_length=255,
        blank=True,
        default="",
        verbose_name="Instagram (ссылка или @username)"
    )
    telegram_bot_token = models.CharField(
        max_length=255,
        blank=True,
        default="",
        verbose_name="Токен Telegram бота"
    )

    class Meta:
        verbose_name = "Организация"
        verbose_name_plural = "Организации"

    def __str__(self):
        return f"{self.name} (Префикс: {self.prefix})"

    @property
    def default_price_type(self):
        """Вид цены по умолчанию для филиала (is_default=True).
        Используется как розничный fallback для гостей/пользователей без своего price_type.
        Возвращает None, если у организации не настроен ни один тип цен."""
        return self.price_types.filter(is_default=True).first()


# 2. Виды номенклатуры
class ItemType(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False, verbose_name="Уникальный Идентификатор 1С")
    name = models.CharField(max_length=255, verbose_name="Наименование")

    organization = models.ForeignKey(
        Organization,
        null=False,
        on_delete=models.CASCADE,
        related_name='item_types',
        verbose_name="Организация"
    )

    class Meta:
        verbose_name = "Вид номенклатуры"
        verbose_name_plural = "Виды номенклатуры"

    def __str__(self):
        return f"{self.name}"


# 3. Номенклатура (Товары)
class Item(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False, verbose_name="Уникальный Идентификатор 1С")
    item_type = models.ForeignKey(ItemType, on_delete=models.CASCADE, null=False, blank=True, related_name='items', verbose_name="Вид номенклатуры")
    articul = models.CharField(max_length=100, null=True, blank=True, verbose_name="Артикул")
    code = models.CharField(max_length=50, null=True, blank=True, verbose_name="Код")
    name = models.CharField(max_length=255, verbose_name="Наименование")
    unit = models.CharField(max_length=50, null=True, blank=True, verbose_name="Единица измерения")
    organization = models.ForeignKey(
        Organization,
        null=False,
        on_delete=models.CASCADE,
        related_name='items',
        verbose_name="Организация"
    )
    updated_at = models.DateTimeField(auto_now=True, db_index=True, verbose_name="Дата последней синхронизации")

    class Meta:
        verbose_name = "Номенклатура (Товар)"
        verbose_name_plural = "Номенклатура (Товары)"
        indexes = [
            # Поиск/сортировка каталога идёт по name в рамках организации
            models.Index(fields=['organization', 'name']),
        ]

    def __str__(self):
        return f"[{self.articul or self.code}] {self.name}"


# 4. Картинки номенклатуры (Позволяет привязать несколько картинок к одному товару)
class ItemImage(models.Model):
    id = models.UUIDField(primary_key=True, editable=False, verbose_name="Уникальный Идентификатор 1С")
    item = models.ForeignKey(Item, on_delete=models.CASCADE, related_name='images', verbose_name="Товар")
    # Используем CharField/URLField, так как 1С будет передавать нам готовые пути/ссылки к файлам
    image_path = models.ImageField(upload_to='products/', max_length=512, verbose_name="Файл картинки")
    is_main = models.BooleanField(default=False, verbose_name="Главная картинка")
    created_at = models.DateTimeField(auto_now_add=True, verbose_name="Дата добавления")

    class Meta:
        verbose_name = "Картинка товара"
        verbose_name_plural = "Картинки товаров"
        ordering = ['-is_main', 'created_at']


# 5. Виды цен
class PriceType(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False, verbose_name="Уникальный Идентификатор 1С")
    code = models.CharField(max_length=50, null=True, blank=True, verbose_name="Код")
    name = models.CharField(max_length=255, verbose_name="Наименование")
    currency = models.CharField(max_length=10, default="UZS", verbose_name="Валюта")
    organization = models.ForeignKey(
        Organization,
        null=False,
        on_delete=models.CASCADE,
        related_name='price_types',
        verbose_name="Организация"
    )

    is_default = models.BooleanField(default = False,
        verbose_name="По умолчанию")

    class Meta:
        verbose_name = "Вид цены"
        verbose_name_plural = "Виды цен"

    def __str__(self):
        return f"{self.name} ({self.currency}) {' (По умолчанию)' if self.is_default else ''}"


# 6. Прайс-листы (Цены товаров)
class PriceList(models.Model):
    item = models.ForeignKey(Item, on_delete=models.CASCADE, related_name='prices', verbose_name="Товар")
    price_type = models.ForeignKey(PriceType, on_delete=models.CASCADE, related_name='prices', verbose_name="Вид цены")
    price = models.DecimalField(max_digits=15, decimal_places=2, default=0.00, verbose_name="Цена")
    updated_at = models.DateTimeField(auto_now=True, verbose_name="Дата обновления цены")

    organization = models.ForeignKey(
        Organization,
        on_delete=models.CASCADE,
        related_name='prices',
        null=False,
        verbose_name="Организация"
    )

    class Meta:
        verbose_name = "Цена из прайс-листа"
        verbose_name_plural = "Прайс-листы (Цены)"

        # ИСПРАВЛЕНО: Теперь уникальность проверяется по связке Товар + Тип цены + Организация
        unique_together = ('item', 'price_type', 'organization')

    def __str__(self):
        # ИСПРАВЛЕНО: Добавили отображение организации в название для удобства в админке
        org_name = f" [{self.organization.name}]" if self.organization else " [Общая]"
        return f"{self.item.name} - {self.price} {self.price_type.currency}{org_name}"


class UserProfile(models.Model):
    # STATUS_CHOICES = [
    #     ('new', 'Новый'),
    #     ('accepted', 'Подтвержден'),
    #     ('changed', 'Изменен'),
    #     ('blocked', 'Отменен'),
    # ]

    # Первичный ключ — UUID. Если создает 1С, она присылает свой. Если фронтенд — генерируется автоматически.
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)

    # status = models.CharField(
    #     max_length=20,
    #     choices=STATUS_CHOICES,
    #     default='new',
    #     verbose_name="Статус аккаунта"
    # )

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='profile',
        verbose_name="Пользователь"
    )
    name = models.CharField(max_length=255, verbose_name="Наименование контрагента")
    price_type = models.ForeignKey('PriceType', on_delete=models.CASCADE, null=False, blank=True,
                                   verbose_name="Тип цен")
    inn = models.CharField(max_length=13, null=True, blank=True, verbose_name="ИНН")
    organization = models.ForeignKey('Organization', null=False, on_delete=models.CASCADE, related_name='profiles',
                                     verbose_name="Организация")

    is_blocked = models.BooleanField(default=False, null=False, verbose_name="Заблокирован")

    class Meta:
        verbose_name = "Профиль контрагента"
        verbose_name_plural = "Профили контрагентов"

    def __str__(self):
        return self.name


# User = get_user_model()


class Order(models.Model):
    STATUS_CHOICES = [
        ('new', 'Новый'),
        ('processing', 'В обработке'),
        ('completed', 'Завершен'),
        ('canceled', 'Отменен'),
    ]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False, verbose_name="ID Заказа 1С")
    order_number = models.CharField(max_length=50, unique=True, blank=True, verbose_name="Номер заказа")
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='orders', verbose_name="Клиент")
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='new', verbose_name="Статус")
    total_amount = models.DecimalField(max_digits=12, decimal_places=2, default=0.00, verbose_name="Итоговая сумма")
    created_at = models.DateTimeField(auto_now_add=True, verbose_name="Дата создания")
    updated_at = models.DateTimeField(auto_now=True, verbose_name="Дата изменения")

    order_number_1c = models.CharField(max_length=50, blank=True, null=True, verbose_name="Номер в 1С")
    organization = models.ForeignKey('Organization', on_delete=models.CASCADE, related_name='orders',
                                     verbose_name="Организация", null=False,)

    class Meta:
        verbose_name = "Заказ"
        verbose_name_plural = "Заказы"
        ordering = ['-created_at']

    def __str__(self):
        return f"Заказ {self.order_number} [{self.order_number_1c}]({self.get_status_display()})"

    def save(self, *args, **kwargs):
        # Автоматически генерируем красивый читаемый номер заказа: ORD-ГГГГММДД-РАНДОМ
        if not self.order_number:
            self.order_number = self.generate_unique_order_number()
        super().save(*args, **kwargs)

    def generate_unique_order_number(self):
        """Метод генерации красивого и уникального номера заказа"""
        # 1. Получаем текущую дату в формате YYYYMMDD (например: 20260531)
        current_date = timezone.now().strftime('%Y%m%d')

        while True:
            # 2. Генерируем случайный 4-значный хвост от 1000 до 9999
            random_tail = random.randint(1000, 9999)

            # 3. Собираем номер целиком
            potential_number = f"ORD-{current_date}-{random_tail}"

            # 4. Проверяем, нет ли уже в базе заказа с точно таким же номером
            # (вероятность совпадения в одну секунду крайне мала, но защита нужна)
            if not Order.objects.filter(order_number=potential_number).exists():
                return potential_number


class OrderItem(models.Model):
    order = models.ForeignKey(Order, on_delete=models.CASCADE, related_name='items', verbose_name="Заказ")
    item = models.ForeignKey(Item, on_delete=models.PROTECT, related_name='order_items', verbose_name="Товар")
    quantity = models.DecimalField(max_digits=12, decimal_places=2, verbose_name="Количество")
    price = models.DecimalField(max_digits=12, decimal_places=2, verbose_name="Цена при покупке")
    discount = models.DecimalField(max_digits=12, decimal_places=2, default=0.00, verbose_name="Скидка")
    total_amount = models.DecimalField(max_digits=12, decimal_places=2, verbose_name="Сумма позиции")

    is_canceled = models.BooleanField(default=False, verbose_name="Отменено")
    cancellation_reason = models.CharField(max_length=255, blank=True, null=True, verbose_name="Причина отмены")

    class Meta:
        verbose_name = "Позиция заказа"
        verbose_name_plural = "Позиции заказа"

    def __str__(self):
        status_text = " [ОТМЕНЕНО]" if self.is_canceled else ""
        return f"{self.item.name} x {self.quantity} ({self.price}) = {self.total_amount}{status_text}"


class ItemStock(models.Model):
    item = models.ForeignKey(
        'Item',
        on_delete=models.CASCADE,
        related_name='stocks',
        verbose_name="Товар"
    )
    organization = models.ForeignKey(
        Organization,
        null=False,
        on_delete=models.CASCADE,
        related_name='item_stocks',
        verbose_name="Организация"
    )
    stock = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        default=0.00,
        verbose_name="Остаток"
    )
    updated_at = models.DateTimeField(auto_now=True, db_index=True, verbose_name="Дата последней синхронизации")

    class Meta:
        verbose_name = "Остаток товара"
        verbose_name_plural = "Остатки товаров"
        # Защита от дублей: у одной организации может быть только одна запись остатка для конкретного товара
        unique_together = ('item', 'organization')

    def __str__(self):
        return f"{self.item.name} ({self.organization.name}) = {self.stock}"