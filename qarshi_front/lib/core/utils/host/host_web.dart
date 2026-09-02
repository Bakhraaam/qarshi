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
