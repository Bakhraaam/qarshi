import 'package:telegram_web_app/telegram_web_app.dart';

/// Определяет, запущено ли приложение внутри Telegram WebApp.
///
/// Признак — непустая `initData`: в обычном браузере она пустая, а внутри
/// Telegram содержит подписанные данные пользователя (их и проверяет бэкенд
/// в `auth/telegram/`). На всякий случай ловим исключения пакета, чтобы
/// вне веб-платформы редирект не падал.
bool isRunningInTelegram() {
  try {
    return TelegramWebApp.instance.isSupported &&
        TelegramWebApp.instance.initData.raw.isNotEmpty;
  } catch (_) {
    return false;
  }
}
