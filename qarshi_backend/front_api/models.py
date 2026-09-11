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
    # Упаковка, которой клиент набирал позицию — нужна только чтобы показать её
    # обратно тем же способом («2 коробки», а не «20 шт») и перенести в заказ.
    # SET_NULL: если 1С удалит упаковку, корзина не должна пропасть.
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

        # ИСПРАВЛЕНО: У одного юзера конкретный товар может быть в корзине только один раз
        # в рамках одной конкретной организации
        unique_together = ('user', 'item', 'organization')

    def __str__(self):
        return f"{self.user.username} — {self.item.name} ({self.quantity}) [{self.organization.name}]"