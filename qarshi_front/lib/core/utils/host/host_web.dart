import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Web-реализация: читает хост из адресной строки браузера.
/// package:web совместим с dart2js И dart2wasm (в отличие от dart:html).
String currentHostname() => web.window.location.hostname;

/// Синтетическое событие resize.
///
/// Flutter web определяет размер вьюпорта по событию `resize` окна. Telegram
/// (особенно десктопный клиент при входе в fullscreen) меняет размер контейнера
/// Mini App, не порождая это событие, — канвас остаётся прежнего размера, и
/// картинка «замирает» в маленьком окне. Событие заставляет Flutter перемерить.
void dispatchWindowResize() {
  web.window.dispatchEvent(web.Event('resize'));
}

/// Отступы safe-area, прочитанные НАПРЯМУЮ из `window.Telegram.WebApp`.
///
/// Пакет `telegram_web_app` описывает эти поля как `int`, а клиенты Telegram
/// присылают дробные значения (27.43 на Android с вырезом) — на таком значении
/// типизированный геттер падает, и отступ молча остаётся нулевым. Здесь читаем
/// их как обычные числа, а если объектов нет — берём CSS-переменные, которые
/// telegram-web-app.js выставляет на `:root`.
({double top, double bottom}) readTelegramInsets() {
  final app = _telegramWebApp();

  double top = 0;
  double bottom = 0;

  if (app != null) {
    // contentSafeAreaInset отсчитывается ВНУТРИ safeAreaInset, поэтому суммируем:
    // первый — вырез/статус-бар, второй — нативные кнопки Telegram.
    final safe = _objectProp(app, 'safeAreaInset');
    final content = _objectProp(app, 'contentSafeAreaInset');
    top = (_numberProp(safe, 'top') ?? 0) + (_numberProp(content, 'top') ?? 0);
    bottom =
        (_numberProp(safe, 'bottom') ?? 0) +
        (_numberProp(content, 'bottom') ?? 0);
  }

  if (top <= 0) {
    top =
        _cssPx('--tg-safe-area-inset-top') +
        _cssPx('--tg-content-safe-area-inset-top');
  }
  if (bottom <= 0) {
    bottom =
        _cssPx('--tg-safe-area-inset-bottom') +
        _cssPx('--tg-content-safe-area-inset-bottom');
  }

  return (top: top, bottom: bottom);
}

/// Развёрнут ли Mini App на весь экран (Bot API 8.0+). Вне Telegram — false.
bool isTelegramFullscreen() {
  final app = _telegramWebApp();
  if (app == null || !app.has('isFullscreen')) return false;
  final value = app['isFullscreen'];
  return value.isA<JSBoolean>() && (value as JSBoolean).toDart;
}

/// `window.Telegram.WebApp` или null — без обращения к несуществующим свойствам.
JSObject? _telegramWebApp() {
  try {
    if (!globalContext.has('Telegram')) return null;
    final telegram = globalContext['Telegram'];
    if (telegram == null || !telegram.isA<JSObject>()) return null;
    final root = telegram as JSObject;
    if (!root.has('WebApp')) return null;
    final app = root['WebApp'];
    return (app != null && app.isA<JSObject>()) ? app as JSObject : null;
  } catch (_) {
    return null;
  }
}

JSObject? _objectProp(JSObject owner, String key) {
  try {
    if (!owner.has(key)) return null;
    final value = owner[key];
    return (value != null && value.isA<JSObject>()) ? value as JSObject : null;
  } catch (_) {
    return null;
  }
}

double? _numberProp(JSObject? owner, String key) {
  if (owner == null) return null;
  try {
    if (!owner.has(key)) return null;
    final value = owner[key];
    if (value == null || !value.isA<JSNumber>()) return null;
    return (value as JSNumber).toDartDouble;
  } catch (_) {
    return null;
  }
}

/// CSS-переменная `:root` в пикселях («27.43px» -> 27.43). Нет/не число -> 0.
double _cssPx(String name) {
  try {
    final root = web.document.documentElement;
    if (root == null) return 0;
    final raw = web.window.getComputedStyle(root).getPropertyValue(name).trim();
    if (raw.isEmpty) return 0;
    return double.tryParse(raw.replaceAll('px', '').trim()) ?? 0;
  } catch (_) {
    return 0;
  }
}

/// Открыть ссылку новой вкладкой. Используется для скачивания готовых файлов.
void openUrl(String url) {
  if (url.isEmpty) return;
  web.window.open(url, '_blank');
}
