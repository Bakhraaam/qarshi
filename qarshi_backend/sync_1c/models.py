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
    # Текст-предупреждение для незарегистрированных (у профиля пустой guid_partner1c),
    # показывается при попытке оформить заказ.
    unregistered_notice = models.CharField(
        max_length=250,
        blank=True,
        default="",
        verbose_name="Сообщение незарегистрированному клиенту"
    )
    telegram_bot_token = models.CharField(
        max_length=255,
        blank=True,
        default="",
        verbose_name="Токен Telegram бота"
    )
    # Текст, который бот отправляет после /start. Пустое поле — бот использует
    # свои стандартные приветствия (bot/texts.py: start_ask_phone / start_with_phone).
    start_text = models.TextField(
        blank=True,
        default="",
        verbose_name="Текст бота после /start"
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

    # Пометка «недействителен» (снята с продажи / помечена на удаление в 1С).
    # Такая категория скрыта из каталога сайта вместе со всеми своими товарами,
    # но остаётся в базе ради истории заказов.
    is_invalid = models.BooleanField(
        default=False,
        db_index=True,
        verbose_name="Недействителен (не показывать на сайте)"
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
    # Пометка «недействителен» (снят с продажи / помечен на удаление в 1С).
    # Такой товар полностью скрыт из каталога сайта, но остаётся в базе ради истории заказов.
    is_invalid = models.BooleanField(
        default=False,
        db_index=True,
        verbose_name="Недействителен (не показывать на сайте)"
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
    # Пометка «недействительна»: 1С сообщает, что картинка больше не актуальна.
    # Такая картинка скрыта из каталога, но файл и запись остаются — 1С может
    # вернуть её обратно, прислав is_invalid=false, не перезаливая байты.
    is_invalid = models.BooleanField(
        default=False,
        db_index=True,
        verbose_name="Недействительна (не показывать на сайте)"
    )
    created_at = models.DateTimeField(auto_now_add=True, verbose_name="Дата добавления")

    class Meta:
        verbose_name = "Картинка товара"
        verbose_name_plural = "Картинки товаров"
        ordering = ['-is_main', 'created_at']


# 4.1 Упаковки номенклатуры (блок, коробка, паллет...)
class ItemPackage(models.Model):
    """Вариант фасовки товара сверх базовой единицы измерения (`Item.unit`).

    Цена всегда хранится и считается за БАЗОВУЮ единицу, а упаковка — это только
    множитель: «Коробка = 10 шт» значит, что 2 коробки это 20 шт по цене за штуку.
    Базовая единица отдельной записью не хранится — она и так есть в `Item.unit`.
    """
    # Ключ СИНТЕТИЧЕСКИЙ, а не GUID из 1С. В 1С упаковка — это общая единица измерения
    # («Канистра 4л»), и один и тот же GUID приходит сразу у нескольких товаров. Делать
    # его первичным ключом нельзя: строки разных товаров схлопывались бы в одну.
    # Поэтому ключ детерминированно выводим из пары (товар, GUID) — см. item_package_pk.
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False,
                          verbose_name="Идентификатор упаковки товара")
    # GUID единицы измерения в 1С — тот, что реально прислал обмен. Не уникален:
    # повторяется у всех товаров с такой же фасовкой.
    guid_1c = models.UUIDField(db_index=True, verbose_name="GUID единицы измерения в 1С")
    item = models.ForeignKey(Item, on_delete=models.CASCADE, related_name='packages',
                             verbose_name="Товар")
    name = models.CharField(max_length=100, verbose_name="Наименование упаковки")
    # Сколько базовых единиц в одной упаковке. Дробное допустимо: «Канистра = 2.5 л».
    quantity = models.DecimalField(max_digits=12, decimal_places=3, default=1,
                                   verbose_name="Базовых единиц в упаковке")
    is_default = models.BooleanField(default=False, verbose_name="Выбрана по умолчанию")
    # Как у товаров и категорий: снятую с продажи упаковку прячем, но не удаляем —
    # на неё могут ссылаться корзины и история заказов.
    is_invalid = models.BooleanField(default=False, db_index=True,
                                     verbose_name="Недействительна (не показывать на сайте)")

    class Meta:
        verbose_name = "Упаковка товара"
        verbose_name_plural = "Упаковки товаров"
        ordering = ['quantity', 'name']
        # Ключ уже выведен из этой пары, ограничение делает правило явным в схеме.
        unique_together = ('item', 'guid_1c')

    def __str__(self):
        # Намеренно не трогаем self.item: __str__ зовётся и до сохранения товара
        # (например, при отладочном выводе пакета из 1С), и лишний запрос там падал.
        return f"{self.name} = {self.quantity}"


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
    name = models.CharField(max_length=255, blank=True, default="", verbose_name="Наименование контрагента")
    price_type = models.ForeignKey('PriceType', on_delete=models.CASCADE, null=False, blank=True,
                                   verbose_name="Тип цен")
    inn = models.CharField(max_length=13, null=True, blank=True, verbose_name="ИНН")
    organization = models.ForeignKey('Organization', null=False, on_delete=models.CASCADE, related_name='profiles',
                                     verbose_name="Организация")

    # Код профиля в 1С. 1С присваивает его каждому пользователю при регистрации,
    # ещё до привязки к контрагенту, поэтому пустой код — надёжный признак
    # «1С этот профиль ещё не получала»: именно по нему строится выдача новых
    # профилей (user-profiles/unlinked/), а не по guid_partner1c, который может
    # появиться гораздо позже или не появиться вовсе.
    code_1c = models.CharField(max_length=50, blank=True, default="", db_index=True,
                               verbose_name="Код в 1С")

    # GUID контрагента в 1С. Пусто, пока 1С не привязала профиль к своему контрагенту.
    guid_partner1c = models.CharField(max_length=255, null=True, blank=True, db_index=True,
                                      verbose_name="GUID контрагента 1С")

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

    PAYMENT_METHOD_CHOICES = [
        ('cashless', 'Безналичный расчет'),
        ('cash', 'Наличные'),
        ('transfer', 'Перевод'),
        ('deferred', 'Отсрочка платежа'),
    ]
    # Лимит комментария совпадает с полем ввода в приложении.
    COMMENT_MAX_LENGTH = 300

    order_number_1c = models.CharField(max_length=50, blank=True, null=True, verbose_name="Номер в 1С")

    # --- Пожелания клиента из формы оформления ---
    # Всё необязательно: заказ можно оформить, ничего не заполняя.
    delivery_date = models.DateField(null=True, blank=True,
                                     verbose_name="Желаемая дата отгрузки")
    payment_method = models.CharField(max_length=20, choices=PAYMENT_METHOD_CHOICES, blank=True, default="",
                                      verbose_name="Способ оплаты")
    comment = models.CharField(max_length=COMMENT_MAX_LENGTH, blank=True, default="",
                               verbose_name="Комментарий клиента")
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

    # --- Снимок выбранной упаковки на момент заказа ---
    # Храним копией, а не FK: упаковку в 1С могут переименовать или снять с продажи,
    # а в истории заказа должно остаться то, что клиент реально выбирал.
    # `quantity` выше всегда в БАЗОВЫХ единицах — 1С разбирает заказ как раньше,
    # а поля ниже нужны только чтобы показать «2 коробки по 10 шт».
    # Именно GUID единицы измерения из 1С, а не наш внутренний ключ ItemPackage:
    # заказ уезжает в 1С, и там понимают только свой идентификатор.
    package_id = models.UUIDField(null=True, blank=True, verbose_name="GUID единицы измерения в 1С")
    package_name = models.CharField(max_length=100, blank=True, default="", verbose_name="Упаковка")
    package_ratio = models.DecimalField(max_digits=12, decimal_places=3, default=1,
                                        verbose_name="Базовых единиц в упаковке")
    package_count = models.DecimalField(max_digits=12, decimal_places=3, default=0,
                                        verbose_name="Количество упаковок")

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