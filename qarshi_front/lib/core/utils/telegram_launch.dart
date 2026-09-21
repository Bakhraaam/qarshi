import 'package:telegram_web_app/telegram_web_app.dart';

// Условный импорт: на web — package:web, на остальных платформах заглушка.
import 'host/host_stub.dart' if (dart.library.js_interop) 'host/host_web.dart';

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

/// Мобильные клиенты Telegram, где полноэкранный режим (Bot API 8.0) уместен.
/// Остальные значения `platform` — 'tdesktop', 'macos', 'linux', 'weba', 'webk',
/// 'unknown': там окно Mini App и так крупное, а запрос fullscreen лишь меняет
/// размер контейнера на лету и роняет отрисовку Flutter.
const Set<String> _mobilePlatforms = {'android', 'ios'};

/// Стоит ли просить полноэкранный режим на текущем клиенте.
bool shouldRequestFullscreen() {
  try {
    return _mobilePlatforms.contains(TelegramWebApp.instance.platform);
  } catch (_) {
    return false;
  }
}

/// Открывает внешнюю ссылку (готовый акт сверки и т.п.).
///
/// Внутри Telegram обычный window.open блокируется вебвью, поэтому там просим
/// открыть ссылку сам Telegram. В браузере — новой вкладкой.
void openExternalLink(String url) {
  if (url.isEmpty) return;
  try {
    if (isRunningInTelegram()) {
      TelegramWebApp.instance.openLink(url);
      return;
    }
  } catch (_) {
    // Старый клиент Telegram — падаем в обычное открытие вкладки.
  }
  openUrl(url);
}
