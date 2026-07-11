import 'package:web/web.dart' as web;

/// Web-реализация: читает хост из адресной строки браузера.
/// package:web совместим с dart2js И dart2wasm (в отличие от dart:html).
String currentHostname() => web.window.location.hostname;
