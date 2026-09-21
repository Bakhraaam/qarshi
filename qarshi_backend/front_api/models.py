import uuid

from django.db import models
from django.contrib.auth.models import User
from sync_1c.models import Item, ItemPackage, Organization
from django.conf import settings


class TelegramAccount(models.Model):
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='telegram_account',
        verbose_name="Пользователь Django"
    )
    phone = models.CharField(max_length=20, blank=True, null=True, verbose_name="Номер телефона")
    telegram_id = models.BigIntegerField(unique=True, verbose_name="Telegram ID")
    telegram_username = models.CharField(max_length=150, null=True, blank=True, verbose_name="Юзернейм в TG")
    tg_first_name = models.CharField(max_length=150, blank=True, null=True, verbose_name="Имя в TG")
    tg_last_name = models.CharField(max_length=150, blank=True, null=True, verbose_name="Фамилия в TG")
    tg_photo_url = models.URLField(max_length=1024, blank=True, null=True, verbose_name="Ссылка на аватарку TG")
    tg_language_code = models.CharField(max_length=10, blank=True, null=True, verbose_name="Язык в TG")

    created_at = models.DateTimeField(auto_now_add=True, verbose_name="Дата регистрации")
    updated_at = models.DateTimeField(auto_now=True, verbose_name="Дата обновления")

    class Meta:
        verbose_name = "Telegram аккаунт"
        verbose_name_plural = "Telegram аккаунты"

    def __str__(self):
        return f"{self.tg_first_name} ({self.telegram_id})"


class CartItem(models.Model):
    # Используем settings.AUTH_USER_MODEL для защиты от круговых импортов
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='cart_items',
        verbose_name="Пользователь"
    )
    item = models.ForeignKey(
        Item,
        null=False,
        on_delete=models.CASCADE,
        related_name='cart_items',
        verbose_name="Товар"
    )

    # НОВОЕ ПОЛЕ: Каждая позиция в корзине жестко привязана к контексту организации
    organization = models.ForeignKey(
        Organization,
        null=False,
        on_delete=models.CASCADE,
        related_name='cart_items',
        verbose_name="Организация"
    )

    # Количество ВСЕГДА в базовых единицах товара (`Item.unit`), даже когда клиент
    # набирает коробками: цена в прайсе за базовую единицу, поэтому `price * quantity`
    # остаётся верным везде. Дробное — потому что упаковка может быть, например, 2.5 л.
    quantity = models.DecimalField(max_digits=12, decimal_places=3, default=1,
                                   verbose_name="Количество (базовых единиц)")
    # Единица, в которой набрана ЭТА строка (null — базовая единица). Один товар может
    # лежать в корзине несколькими строками: «5 коробок» и отдельно «3 шт».
    # SET_NULL: если 1С удалит упаковку, корзина не должна пропасть. Перед удалением
    # синхронизация сливает такие строки со строкой базовой единицы — иначе после
    # SET_NULL получилось бы две базовые строки и нарушилась бы уникальность ниже.
    package = models.ForeignKey(
        ItemPackage,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name='cart_items',
        verbose_name="Упаковка"
    )
    created_at = models.DateTimeField(auto_now_add=True, verbose_name="Добавлено")
    updated_at = models.DateTimeField(auto_now=True, verbose_name="Изменено")

    class Meta:
        verbose_name = "Товар в корзине"
        verbose_name_plural = "Товары в корзинах"

        # Одна строка на пару «товар + единица» у пользователя в филиале.
        # Два условных ограничения вместо одного unique_together: в Postgres NULL не равен
        # NULL, и ограничение с package пропустило бы сколько угодно базовых строк.
        constraints = [
            models.UniqueConstraint(
                fields=['user', 'item', 'organization', 'package'],
                condition=models.Q(package__isnull=False),
                name='cartitem_unique_packaged_line',
            ),
            models.UniqueConstraint(
                fields=['user', 'item', 'organization'],
                condition=models.Q(package__isnull=True),
                name='cartitem_unique_base_line',
            ),
        ]

    def __str__(self):
        unit = self.package.name if self.package_id else (self.item.unit or '')
        return f"{self.user.username} — {self.item.name} ({self.quantity} {unit}) [{self.organization.name}]"

class ActReconciliationRequest(models.Model):
    """Заявка клиента на акт сверки.

    Сайт не ходит в 1С сам: заявка складывается сюда, 1С забирает её через
    `sync_1c/reports/act/pending/`, формирует печатную форму и присылает файл в
    `sync_1c/reports/act/upload/`. После загрузки клиенту уходит сообщение в Telegram.
    """
    STATUS_PENDING = 'pending'
    STATUS_READY = 'ready'
    STATUS_FAILED = 'failed'
    STATUS_CHOICES = [
        (STATUS_PENDING, 'Ожидает 1С'),
        (STATUS_READY, 'Готов'),
        (STATUS_FAILED, 'Ошибка'),
    ]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    organization = models.ForeignKey(
        Organization, on_delete=models.CASCADE, related_name='act_requests',
        verbose_name="Организация"
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='act_requests',
        verbose_name="Клиент"
    )
    # Копия на момент заявки: по нему 1С находит контрагента. Если менеджер позже
    # перепривяжет профиль, уже отданный акт останется по тому, кого запрашивали.
    guid_partner1c = models.CharField(max_length=255, verbose_name="GUID контрагента 1С")

    date_from = models.DateField(verbose_name="Период с")
    date_to = models.DateField(verbose_name="Период по")

    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_PENDING,
                              db_index=True, verbose_name="Статус")
    file = models.FileField(upload_to='acts/', null=True, blank=True, verbose_name="Файл акта")
    filename = models.CharField(max_length=255, blank=True, default="", verbose_name="Имя файла")
    # Текст ошибки от 1С («нет данных за период») — показывается клиенту как есть.
    message = models.CharField(max_length=500, blank=True, default="", verbose_name="Сообщение 1С")

    created_at = models.DateTimeField(auto_now_add=True, db_index=True, verbose_name="Создана")
    updated_at = models.DateTimeField(auto_now=True, verbose_name="Изменена")
    notified_at = models.DateTimeField(null=True, blank=True,
                                       verbose_name="Клиент уведомлён в Telegram")

    class Meta:
        verbose_name = "Заявка на акт сверки"
        verbose_name_plural = "Заявки на акт сверки"
        ordering = ['-created_at']

    def __str__(self):
        return f"Акт {self.date_from}–{self.date_to} ({self.get_status_display()})"
