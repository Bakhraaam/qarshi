import 'package:flutter/foundation.dart';
import 'package:qarshi/core/data/constants.dart';
// Условный импорт: на web — package:web (совместим с --wasm), на остальных
// платформах — заглушка, чтобы сборка под мобилки/десктоп не падала.
import 'host/host_stub.dart' if (dart.library.js_interop) 'host/host_web.dart';

class DomainResolver {
  /// Получает имя субдомена из адресной строки браузера
  static String? getSubdomain() {
    if (!kIsWeb) {
      // Если приложение запущено как мобильное (в будущем), субдомен можно b2b-хранить в настройках,
      // а для Web — читаем адресную строку
      return null;
    }

    try {
      String hostname = currentHostname();
      if (hostname.startsWith('http://')) {
        hostname = hostname.replaceFirst('http://', '');
      } else if (hostname.startsWith('https://')) {
        hostname = hostname.replaceFirst('https://', '');
      }

      final parts = hostname.split('.');
      if (hostname.contains('localhost') && parts.length == 2) {
        return parts.first;
      }

      if (parts.length >= 3) {
        if (parts.first == 'www') return parts[1];
        return parts.first;
      }
    } catch (e) {
      print('Ошибка определения субдомена: $e');
    }
    return null;
  }

  /// Генерирует динамический базовый URL для API в зависимости от субдомена
  static String getBaseApiUrl() {
    final String? subdomain = getSubdomain();
    // На продакшн-сервере отправляем запросы на тот же субдомен бэкенда
    // return 'l';
    if (subdomain == null) {
      String r = '$domain/api/v1/';
      print(r);
      return r;
    } else {
      String r = '$domain/api/v1/$subdomain/';
      print(r);
      return r;
    }
  }
}
