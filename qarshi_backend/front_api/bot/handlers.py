"""
Обработка апдейтов Telegram-бота филиала.

Сценарии (см. тексты в texts.py):
  /start без телефона      -> приветствие + кнопка «Отправить номер телефона»
  /start с телефоном       -> короткое приветствие + кнопки каталога/заказов
  прислали свой контакт    -> сохраняем номер; ответ зависит от того, привязан ли
                              профиль к контрагенту 1С (guid_partner1c)
  прислали чужой контакт   -> просим свой
  любой другой текст       -> напоминание про кнопку
  доступ закрыт менеджером -> сообщение с телефоном поддержки
"""
from front_api.utils import normalize_phone

from . import api, texts
from .accounts import ensure_profile, is_access_blocked, upsert_telegram_account


def handle_update(organization, update: dict) -> None:
    """Точка входа вебхука. Молча игнорирует всё, что не является сообщением в личке."""
    message = update.get('message') or update.get('edited_message')
    if not isinstance(message, dict):
        return

    chat = message.get('chat') or {}
    if chat.get('type') != 'private':
        return

    tg_user = message.get('from') or {}
    if not tg_user.get('id') or tg_user.get('is_bot'):
        return

    token = organization.telegram_bot_token
    chat_id = chat.get('id')

    account = upsert_telegram_account(tg_user)
    profile = ensure_profile(account.user, organization)

    if is_access_blocked(account.user, profile):
        api.send_message(token, chat_id, texts.blocked(organization), api.keyboard_remove())
        return

    contact = message.get('contact')
    if contact:
        _handle_contact(organization, chat_id, account, profile, tg_user, contact)
        return

    text = (message.get('text') or '').strip()
    if text.startswith('/start'):
        _handle_start(organization, chat_id, account)
        return

    # Любое другое сообщение: бот не ведёт переписку, всё общение — в приложении
    if account.phone:
        api.send_message(token, chat_id, texts.hint_use_buttons(), api.keyboard_remove())
    else:
        api.send_message(token, chat_id, texts.text_instead_of_button(), api.keyboard_ask_phone(organization))


def _handle_start(organization, chat_id, account) -> None:
    token = organization.telegram_bot_token
    if account.phone:
        api.send_message(
            token, chat_id,
            texts.start_with_phone(organization, account.tg_first_name),
            api.keyboard_remove(),
        )
    else:
        api.send_message(
            token, chat_id,
            texts.start_no_phone(organization),
            api.keyboard_ask_phone(organization),
        )


def _handle_contact(organization, chat_id, account, profile, tg_user, contact: dict) -> None:
    token = organization.telegram_bot_token

    # Контакт можно переслать из адресной книги — принимаем только свой номер
    if contact.get('user_id') != tg_user.get('id'):
        api.send_message(token, chat_id, texts.foreign_contact(), api.keyboard_ask_phone(organization))
        return

    phone = normalize_phone(contact.get('phone_number'))
    if not phone:
        api.send_message(token, chat_id, texts.foreign_contact(), api.keyboard_ask_phone(organization))
        return

    if account.phone != phone:
        account.phone = phone
        account.save(update_fields=['phone', 'updated_at'])

    # guid_partner1c заполняет 1С, когда менеджер привязал профиль к контрагенту.
    # Пока он пуст — клиент видит каталог, но оформить заказ не сможет.
    if profile and (profile.guid_partner1c or '').strip():
        message_text = texts.contact_linked(phone, profile.name)
    else:
        message_text = texts.contact_unlinked(organization, phone)

    api.send_message(token, chat_id, message_text, api.keyboard_remove())
