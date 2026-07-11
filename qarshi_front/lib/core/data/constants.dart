import 'package:flutter/foundation.dart';
import 'package:qarshi/core/data/models.dart';

/// Единый источник истины по количествам товаров в корзине: productId -> quantity.
/// Каталог и корзина пишут сюда при любом изменении, а бейджи/карточки слушают
/// через ValueListenableBuilder — так количество синхронно на всех экранах.
final ValueNotifier<Map<String, num>> cartNotifier =
    ValueNotifier<Map<String, num>>(<String, num>{});

/// Помощник: обновить одну позицию в глобальной корзине (0/меньше — удалить).
void setCartQuantityLocal(String productId, num quantity) {
  final next = Map<String, num>.from(cartNotifier.value);
  if (quantity <= 0) {
    next.remove(productId);
  } else {
    next[productId] = quantity;
  }
  cartNotifier.value = next;
}

String AppName = 'Qarshi app';
String tokenAccess = '';
UserModel? currentUser;

// Хост API. По умолчанию пусто → относительный same-origin base
// (Django раздаёт собранный web на том же origin, работает и через ngrok).
// Для dev-запуска (flutter run) можно передать реальный хост бэкенда:
//   flutter run --dart-define=API_DOMAIN=http://localhost:8001
String domain = const String.fromEnvironment('API_DOMAIN', defaultValue: '');
//String domain = '127.0.0.1:8000';
