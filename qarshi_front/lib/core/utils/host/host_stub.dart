/// Заглушка для не-web платформ (mobile/desktop): хоста в адресной строке нет.
/// Реальная реализация — в host_web.dart (подключается по dart.library.js_interop).
String currentHostname() => '';

/// На не-web платформах пересчитывать нечего.
void dispatchWindowResize() {}

/// Отступы Telegram на не-web платформах не существуют.
({double top, double bottom}) readTelegramInsets() => (top: 0, bottom: 0);

/// Вне веба полноэкранного режима Mini App нет.
bool isTelegramFullscreen() => false;

/// Вне веба ссылки открывать нечем.
void openUrl(String url) {}
