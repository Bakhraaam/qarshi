"""
Обработка апдейтов Telegram-бота филиала.

Сценарии (см. тексты в texts.py):
  /start без телефона      -> приветствие + кнопка «Отправить номер телефона»
  /start с телефоном       -> приветствие, клавиатура убирается
  (если у филиала заполнен start_text — вместо приветствия шлётся он,
   клавиатура при этом та же)
  прислали свой контакт    -> сохраняем номер; ответ зависит от того, привязан ли
                              профиль к контрагенту 1С (guid_partner1c)
  прислали чужой контакт   -> просим свой
  любой другой текст       -> отправляем в приложение
  доступ закрыт менеджером -> сообщение с телефоном поддержки

Единственная кнопка бота — запрос контакта; навигацию приложения он не дублирует,
Mini App открывают штатные входы Telegram. Пока номера нет, кнопка показывается,
после получения номера уходит remove_keyboard.
"""
from front_api.models import TelegramAccount
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
        _handle_contact(organization, chat_id, account, profile, message, contact)
        return

    text = (message.get('text') or '').strip()
    if text.startswith('/start'):
        _handle_start(organization, chat_id, account)
        return

    # Любое другое сообщение: бот не ведёт переписку, всё общение — в приложении
    if account.phone:
        api.send_message(token, chat_id, texts.open_app(organization), api.keyboard_remove())
    else:
        api.send_message(token, chat_id, texts.phone_still_needed(), api.keyboard_ask_phone())


def _handle_start(organization, chat_id, account) -> None:
    token = organization.telegram_bot_token
    # Филиал может задать свой текст после /start (Organization.start_text,
    # приходит из 1С в organizations/). Пустое поле — стандартные приветствия.
    custom = texts.custom_start(organization)
    if account.phone:
        text = custom or texts.start_with_phone(organization, account.tg_first_name)
        keyboard = api.keyboard_remove()
    else:
        text = custom or texts.start_ask_phone(organization, account.tg_first_name)
        keyboard = api.keyboard_ask_phone()
    api.send_message(token, chat_id, text, keyboard)


def _handle_contact(organization, chat_id, account, profile, message, contact: dict) -> None:
    """Принимаем ТОЛЬКО номер самого отправителя, полученный кнопкой запроса контакта.

    Чем пытаются подменить номер и что этому мешает:
      * прислать карточку другого пользователя из адресной книги — в contact лежит
        его user_id, он не совпадает с автором сообщения;
      * создать контакт вручную с любым номером — у такого контакта user_id вообще
        нет, Telegram подставляет его только для настоящих аккаунтов;
      * переслать чужое сообщение с контактом — у сообщения есть признак пересылки,
        такие не принимаем совсем;
      * занять номер, уже привязанный к другому Telegram-аккаунту, — отказываем и
        отправляем к менеджеру, иначе двое могли бы претендовать на одного контрагента.
    """
    token = organization.telegram_bot_token
    tg_user = message.get('from') or {}

    # Пересланное сообщение — не собственный контакт «здесь и сейчас».
    is_forwarded = any(
        key in message
        for key in ('forward_origin', 'forward_from', 'forward_from_chat', 'forward_sender_name')
    )
    if is_forwarded:
        api.send_message(token, chat_id, texts.foreign_contact(), api.keyboard_ask_phone())
        return

    # Контакт без user_id — созданный вручную, с произвольным номером.
    if contact.get('user_id') != tg_user.get('id'):
        api.send_message(token, chat_id, texts.foreign_contact(), api.keyboard_ask_phone())
        return

    phone = normalize_phone(contact.get('phone_number'))
    if not phone:
        api.send_message(token, chat_id, texts.foreign_contact(), api.keyboard_ask_phone())
        return

    taken_by_other = (TelegramAccount.objects
                      .filter(phone=phone)
                      .exclude(pk=account.pk)
                      .exists())
    if taken_by_other:
        api.send_message(token, chat_id, texts.phone_taken(organization), api.keyboard_remove())
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
