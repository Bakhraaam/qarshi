"""
Общая работа с Telegram-аккаунтами: используется и вебхуком бота, и входом
через WebApp (front_api/views/auth.py) — логика создания/синхронизации одна.
"""
import secrets

from django.contrib.auth.models import User
from django.db import transaction

from front_api.models import TelegramAccount
from sync_1c.models import UserProfile


def upsert_telegram_account(tg_user: dict, phone: str | None = None) -> TelegramAccount:
    """
    Находит глобальный TelegramAccount по telegram_id, при отсутствии — создаёт
    вместе с системным пользователем Django (username = tg_<telegram_id>).
    Технические данные (имя, аватар, язык, юзернейм) обновляются всегда,
    телефон — только если он передан (Telegram отдаёт его не в каждом апдейте).
    """
    tg_id = tg_user.get('id')
    tg_username = tg_user.get('username', '')
    tg_first_name = tg_user.get('first_name', '')
    tg_last_name = tg_user.get('last_name', '')
    tg_photo_url = tg_user.get('photo_url', '')
    tg_language_code = tg_user.get('language_code', 'ru')

    account = TelegramAccount.objects.filter(telegram_id=tg_id).select_related('user').first()

    if not account:
        with transaction.atomic():
            user = User.objects.create_user(
                username=f"tg_{tg_id}",
                password=secrets.token_urlsafe(16),
                first_name=tg_first_name,
                last_name=tg_last_name,
            )
            account = TelegramAccount.objects.create(
                user=user,
                phone=phone,
                telegram_id=tg_id,
                telegram_username=tg_username,
                tg_first_name=tg_first_name,
                tg_last_name=tg_last_name,
                tg_photo_url=tg_photo_url,
                tg_language_code=tg_language_code,
            )
        return account

    account.telegram_username = tg_username
    if phone and account.phone != phone:
        account.phone = phone
    account.tg_first_name = tg_first_name
    account.tg_last_name = tg_last_name
    account.tg_photo_url = tg_photo_url
    account.tg_language_code = tg_language_code
    account.save()
    return account


def ensure_profile(user, organization) -> UserProfile | None:
    """
    Профиль контрагента для конкретного филиала. При первом контакте создаём его
    с видом цены по умолчанию; если у филиала не настроен default_price_type —
    профиля не будет (цены упадут в гостевой fallback), это не ошибка бота.
    """
    profile = UserProfile.objects.filter(user=user, organization=organization).first()
    if profile:
        return profile

    default_pt = organization.default_price_type
    if not default_pt:
        return None

    return UserProfile.objects.create(
        user=user,
        organization=organization,
        price_type=default_pt,
        name='',
        is_blocked=False,
    )


def is_access_blocked(user, profile) -> bool:
    """Глобальная блокировка учётной записи или блокировка профиля в этом филиале."""
    return (not user.is_active) or bool(profile and profile.is_blocked)
