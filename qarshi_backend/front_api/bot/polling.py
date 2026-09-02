"""
Long polling: бот сам забирает апдейты через getUpdates.

Нужен там, где Telegram не может достучаться до сервера вебхуком (закрытый
входящий трафик), но исходящие соединения работают. Логика обработки сообщений
общая с вебхуком — handlers.handle_update.

Смещение (offset) храним в кэше: после перезапуска процесс не переобрабатывает
уже прочитанные апдейты. Redis переживает рестарт, LocMemCache — нет, тогда
Telegram просто отдаст неподтверждённую часть очереди заново.
"""
import time

from django.core.cache import cache
from django.db import close_old_connections

from . import api
from .handlers import handle_update

OFFSET_CACHE_KEY = "telegram:polling:offset:{prefix}"
OFFSET_CACHE_TTL = 7 * 24 * 3600
LONG_POLL_TIMEOUT = 25
ERROR_PAUSE_SECONDS = 5


def get_offset(organization) -> int | None:
    return cache.get(OFFSET_CACHE_KEY.format(prefix=organization.prefix))


def set_offset(organization, offset: int) -> None:
    cache.set(OFFSET_CACHE_KEY.format(prefix=organization.prefix), offset, OFFSET_CACHE_TTL)


def fetch_updates(organization, offset: int | None, timeout: int = LONG_POLL_TIMEOUT) -> dict:
    payload = {"timeout": timeout, "allowed_updates": ["message"]}
    if offset is not None:
        payload["offset"] = offset
    # Соединение висит до timeout секунд, поэтому клиенту даём запас
    return api.call(organization.telegram_bot_token, "getUpdates", payload, timeout=timeout + 10)


def poll_once(organization, offset: int | None, timeout: int = LONG_POLL_TIMEOUT,
              log=print) -> tuple[int | None, int]:
    """
    Один цикл: забрать пачку апдейтов, обработать, вернуть (новый offset, сколько обработано).
    Ошибку сети не бросает — возвращает прежний offset, вызывающий сделает паузу.
    """
    result = fetch_updates(organization, offset, timeout)

    if not result.get("ok"):
        description = str(result.get("description", ""))
        # 409: у бота ещё активен вебхук — getUpdates и вебхук взаимоисключающи
        if "terminated by other getUpdates" in description or "webhook is active" in description:
            log(f"[{organization.prefix}] конфликт с вебхуком, снимаю его: {description}")
            api.call(organization.telegram_bot_token, "deleteWebhook", {"drop_pending_updates": False})
        else:
            log(f"[{organization.prefix}] getUpdates FAILED: {description}")
        return offset, 0

    updates = result.get("result") or []
    processed = 0
    for update in updates:
        update_id = update.get("update_id")
        if update_id is not None:
            # Подтверждаем апдейт СРАЗУ: иначе сообщение, роняющее обработчик,
            # будет приходить снова и снова и заблокирует очередь
            offset = update_id + 1
            set_offset(organization, offset)
        try:
            handle_update(organization, update)
        except Exception as err:
            log(f"[{organization.prefix}] ошибка обработки апдейта {update_id}: "
                f"{type(err).__name__}: {err}")
        processed += 1

    return offset, processed


def run_forever(organization, timeout: int = LONG_POLL_TIMEOUT, log=print) -> None:
    """Бесконечный цикл опроса для одного филиала. Прерывается KeyboardInterrupt."""
    # Вебхук и getUpdates несовместимы — снимаем вебхук, но НЕ сбрасываем очередь:
    # накопившиеся апдейты придут первой же пачкой
    api.call(organization.telegram_bot_token, "deleteWebhook", {"drop_pending_updates": False})

    offset = get_offset(organization)
    log(f"[{organization.prefix}] опрос запущен (offset={offset})")

    while True:
        try:
            offset, processed = poll_once(organization, offset, timeout, log=log)
            if processed:
                log(f"[{organization.prefix}] обработано апдейтов: {processed}")
        except KeyboardInterrupt:
            raise
        except Exception as err:
            log(f"[{organization.prefix}] сбой цикла: {type(err).__name__}: {err}")
            time.sleep(ERROR_PAUSE_SECONDS)
        finally:
            # Долгие паузы между запросами рвут соединения к БД — закрываем протухшие
            close_old_connections()
