/// Заглушка для не-web платформ (mobile/desktop): хоста в адресной строке нет.
/// Реальная реализация — в host_web.dart (подключается по dart.library.js_interop).
String currentHostname() => '';
