"""
Тонкий клиент Telegram Bot API + клавиатуры бота.

Намеренно на stdlib (urllib), чтобы не тащить новую зависимость в requirements.txt.
Токен бота берётся из Organization.telegram_bot_token — у каждого филиала свой бот.
"""
import hashlib
import hmac
import json
import urllib.error
import urllib.request

from django.conf import settings

from . import texts

API_URL = "https://api.telegram.org/bot{token}/{method}"
REQUEST_TIMEOUT = 10


def webhook_secret(org_prefix: str) -> str:
    """
    Секрет для заголовка X-Telegram-Bot-Api-Secret-Token.
    Считается детерминированно от SECRET_KEY, поэтому не нужно хранить его в БД
    и синхронизировать с 1С: команда set_telegram_webhook и вьюха считают одно и то же.
    """
    key = (settings.SECRET_KEY or "").encode("utf-8")
    return hmac.new(key, f"tg-webhook:{org_prefix}".encode("utf-8"), hashlib.sha256).hexdigest()


def webapp_base_url(organization) -> str:
    """Базовый URL филиала: домен его WebApp, он же адрес для вебхука по умолчанию."""
    template = getattr(settings, "TELEGRAM_WEBAPP_URL_TEMPLATE", "https://{prefix}.qarshi1s.uz")
    return template.format(prefix=organization.prefix or "").rstrip("/")


def call(token: str, method: str, payload: dict | None = None, timeout: int | None = None) -> dict:
    """
    Синхронный вызов метода Bot API. Никогда не бросает исключение:
    при ошибке возвращает {"ok": False, "description": ...} — вебхук должен
    ответить Telegram 200 даже если отправка сообщения не удалась.
    timeout переопределяется для long polling (getUpdates держит соединение открытым).
    """
    url = API_URL.format(token=token, method=method)
    data = json.dumps(payload or {}, ensure_ascii=False).encode("utf-8")
    request = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=timeout or REQUEST_TIMEOUT) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as http_err:
        # Telegram отдаёт причину в теле ответа (например: chat not found, bot was blocked)
        body = http_err.read().decode("utf-8", errors="replace")
        try:
            return json.loads(body)
        except ValueError:
            return {"ok": False, "description": f"HTTP {http_err.code}: {body[:200]}"}
    except Exception as err:
        return {"ok": False, "description": f"{type(err).__name__}: {err}"}


def send_message(token: str, chat_id: int, text: str, reply_markup: dict | None = None) -> dict:
    payload = {
        "chat_id": chat_id,
        "text": text,
        "disable_web_page_preview": True,
    }
    if reply_markup is not None:
        payload["reply_markup"] = reply_markup
    result = call(token, "sendMessage", payload)
    if not result.get("ok"):
        # Молчащий бот при живом вебхуке — почти всегда именно эта строка:
        # нет исходящего доступа к api.telegram.org, неверный токен или бот заблокирован
        print(f"Telegram sendMessage FAILED (chat_id={chat_id}): {result.get('description')}")
    return result


# --- Клавиатуры ---
# Бот не дублирует навигацию приложения: единственная кнопка — запрос телефона,
# после его получения клавиатура убирается. WebApp открывается штатными
# средствами Telegram (menu-кнопка / кнопка «Открыть» у бота).

def keyboard_ask_phone(organization) -> dict:
    return {
        "keyboard": [[{"text": texts.BTN_SHARE_PHONE, "request_contact": True}]],
        "resize_keyboard": True,
        "is_persistent": True,
    }


def keyboard_remove() -> dict:
    return {"remove_keyboard": True}
