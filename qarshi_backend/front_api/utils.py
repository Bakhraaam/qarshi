import hashlib
import hmac
import time
import urllib.parse
import json
from django.conf import settings

# Максимальный возраст initData от Telegram (защита от повторного использования старой подписи).
# Можно переопределить в settings.py: TELEGRAM_AUTH_TTL_SECONDS = ...
TELEGRAM_AUTH_TTL_SECONDS = getattr(settings, "TELEGRAM_AUTH_TTL_SECONDS", 24 * 3600)


def normalize_phone(phone_str: str) -> str:
    """Оставляет в строке только цифры. Например: '+998 (90) 123-45-67' -> '998901234567'"""
    if not phone_str:
        return ""
    cleaned = "".join([char for char in str(phone_str) if char.isdigit()])

    return cleaned


def verify_telegram_webapp_data(organization, init_data: str, max_age_seconds: int = None) -> dict | None:
    """
    Проверяет подпись initData от Telegram WebApp (HMAC-SHA256 по токену бота организации)
    и свежесть auth_date (защита от повторного использования старой подписи).
    Подробный вывод в консоль только при settings.DEBUG.
    Возвращает dict пользователя при успехе, иначе None.
    """
    debug = bool(getattr(settings, "DEBUG", False))

    def log(msg):
        if debug:
            print(msg)

    if not init_data:
        log("Telegram verify: init_data пустая или None")
        return None

    try:
        # 1. Надёжный parse_qsl (корректно декодирует ключи/значения)
        parsed_data = dict(urllib.parse.parse_qsl(init_data, keep_blank_values=True))

        if 'hash' not in parsed_data:
            log("Telegram verify: отсутствует параметр 'hash'")
            return None

        tg_hash = parsed_data.pop('hash')
        # ВАЖНО: signature НЕ удаляем. В актуальном формате Telegram WebApp это поле
        # присутствует в initData и ВХОДИТ в data_check_string при расчёте hash —
        # если его убрать, HMAC не сходится (проверено на реальном initData).

        # 2. data_check_string: параметры по алфавиту, соединённые через \n
        data_check_string = "\n".join(f"{k}={v}" for k, v in sorted(parsed_data.items()))

        # 3. Токен бота из организации (чистим от случайных пробелов/переносов)
        raw_bot_token = getattr(organization, 'telegram_bot_token', '')
        if not raw_bot_token:
            log("Telegram verify: у организации пуст telegram_bot_token")
            return None
        bot_token = raw_bot_token.strip()

        # 4. Считаем проверочный хэш
        secret_key = hmac.new(b"WebAppData", bot_token.encode('utf-8'), hashlib.sha256).digest()
        calculated_hash = hmac.new(secret_key, data_check_string.encode('utf-8'), hashlib.sha256).hexdigest()

        # 5. Криптографически безопасное сравнение
        if not hmac.compare_digest(calculated_hash, tg_hash):
            log("Telegram verify: подпись неверна (хэши не совпали)")
            return None

        # 6. Проверяем свежесть auth_date — защита от replay старой подписи
        ttl = TELEGRAM_AUTH_TTL_SECONDS if max_age_seconds is None else max_age_seconds
        if ttl:
            auth_date_raw = parsed_data.get('auth_date')
            if not auth_date_raw:
                log("Telegram verify: нет auth_date для проверки свежести")
                return None
            try:
                age = time.time() - int(auth_date_raw)
            except (ValueError, TypeError):
                log("Telegram verify: некорректный auth_date")
                return None
            # Слишком старая подпись, либо дата из будущего (допускаем 5 мин рассинхрона часов)
            if age > ttl or age < -300:
                log(f"Telegram verify: auth_date вне допустимого окна (age={int(age)}s, ttl={ttl}s)")
                return None

        # 7. Успех — возвращаем распарсенного пользователя
        if 'user' in parsed_data:
            try:
                return json.loads(parsed_data['user'])
            except Exception as json_err:
                log(f"Telegram verify: не удалось распарсить 'user' ({json_err})")
        return parsed_data

    except Exception as e:
        log(f"Telegram verify: критическая ошибка — {e}")
        return None


class DebugURLMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response
        # Логируем запросы только в режиме отладки — в проде это флудит логи на каждый запрос
        self.enabled = bool(getattr(settings, "DEBUG", False))

    def __call__(self, request):
        if self.enabled:
            print("\n" + "="*50)
            print("🚨 ПОЙМАН ВХОДЯЩИЙ ЗАПРОС:")
            print(f"Метод:      {request.method}")
            print(f"ПОЛНЫЙ URL: {request.build_absolute_uri()}")
            print(f"Хост (Host): {request.get_host()}")
            print(f"Путь (Path): {request.path}")
            print("="*50 + "\n")

        return self.get_response(request)