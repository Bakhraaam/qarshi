"""Сообщения клиенту от имени бота филиала вне диалога.

Отдельно от handlers.py: там реакция на апдейты Telegram, здесь — инициатива сайта
(«акт сверки готов»). Ни одна ошибка отправки не должна ронять бизнес-операцию,
поэтому функции ничего не бросают и возвращают bool.
"""
from django.utils import timezone

from . import api, texts


def _chat_id(user) -> int | None:
    account = getattr(user, 'telegram_account', None)
    return account.telegram_id if account else None


def notify_act_ready(act_request) -> bool:
    """Отдаёт клиенту готовый акт сверки прямо в чат.

    Файл грузим сами, ссылку в сообщение не кладём: ссылка была бы пропуском к
    документу для любого, кому её переслали. Посмотреть и скачать акт можно и в
    приложении — там доступ закрыт входом.
    """
    token = act_request.organization.telegram_bot_token
    chat_id = _chat_id(act_request.user)
    # Вход по логину и паролю: Telegram у клиента может не быть вовсе.
    if not token or not chat_id:
        return False

    if act_request.status != act_request.STATUS_READY:
        text = texts.act_failed(act_request.date_from, act_request.date_to,
                                act_request.message)
        return _mark_notified(act_request, api.send_message(token, chat_id, text,
                                                            api.keyboard_remove()))

    act_request.file.open('rb')
    try:
        content = act_request.file.read()
    finally:
        act_request.file.close()

    filename = act_request.filename or f"act_{act_request.date_from}_{act_request.date_to}.pdf"
    result = api.send_document(
        token, chat_id, filename, content,
        caption=texts.act_ready_caption(act_request.date_from, act_request.date_to),
    )
    if result.get('ok'):
        return _mark_notified(act_request, result)

    # Файл не ушёл (слишком большой, сбой сети) — хотя бы сообщаем, что акт готов.
    fallback = api.send_message(
        token, chat_id,
        texts.act_ready_without_file(act_request.date_from, act_request.date_to),
        api.keyboard_remove(),
    )
    return _mark_notified(act_request, fallback)


def _mark_notified(act_request, result: dict) -> bool:
    if not result.get('ok'):
        return False
    act_request.notified_at = timezone.now()
    act_request.save(update_fields=['notified_at', 'updated_at'])
    return True
