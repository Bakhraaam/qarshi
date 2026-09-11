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

/// Выбранная клиентом единица набора по товарам: productId -> packageId.
/// null/отсутствует — товар набирается базовой единицей. Живёт отдельно от
/// количеств, потому что выбор единицы не меняет ни цену, ни сумму корзины.
final ValueNotifier<Map<String, String>> cartPackageNotifier =
    ValueNotifier<Map<String, String>>(<String, String>{});

/// Помощник: запомнить выбранную упаковку товара (null — базовая единица).
void setCartPackageLocal(String productId, String? packageId) {
  final next = Map<String, String>.from(cartPackageNotifier.value);
  if (packageId == null || packageId.isEmpty) {
    next.remove(productId);
  } else {
    next[productId] = packageId;
  }
  cartPackageNotifier.value = next;
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
