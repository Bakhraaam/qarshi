import 'package:flutter/foundation.dart';
import 'package:qarshi/core/data/models.dart';

/// Единый источник истины по строкам корзины: cartLineKey(товар, единица) -> количество.
/// Количество в базовых единицах. Один товар может занимать несколько строк —
/// «5 коробок» и «3 шт» лежат под разными ключами.
/// Каталог и корзина пишут сюда при любом изменении, а бейджи/карточки слушают
/// через ValueListenableBuilder — так количество синхронно на всех экранах.
final ValueNotifier<Map<String, num>> cartNotifier =
    ValueNotifier<Map<String, num>>(<String, num>{});

/// Помощник: обновить одну строку в глобальной корзине (0/меньше — удалить).
void setCartQuantityLocal(String productId, String? packageId, num quantity) {
  final key = cartLineKey(productId, packageId);
  final next = Map<String, num>.from(cartNotifier.value);
  if (quantity <= 0) {
    next.remove(key);
  } else {
    next[key] = quantity;
  }
  cartNotifier.value = next;
}

/// Сколько базовых единиц товара лежит в строке этой единицы (0 — строки нет).
num cartQuantityOf(
  Map<String, num> cart,
  String productId,
  String? packageId,
) => cart[cartLineKey(productId, packageId)] ?? 0;

/// Единицы, в которых товар уже лежит в корзине (null — базовая единица).
Iterable<String?> cartUnitsOf(Map<String, num> cart, String productId) sync* {
  final prefix = '$productId|';
  for (final key in cart.keys) {
    if (!key.startsWith(prefix)) continue;
    final packageId = key.substring(prefix.length);
    yield packageId.isEmpty ? null : packageId;
  }
}

/// Единица, выбранная в карточке товара: productId -> packageId ('' — базовая).
/// Это только выбор на экране, в корзину он ничего не пишет: переключив единицу,
/// клиент видит количество строки ЭТОЙ единицы или кнопку «В корзину».
final ValueNotifier<Map<String, String>> selectedUnitNotifier =
    ValueNotifier<Map<String, String>>(<String, String>{});

/// Запомнить выбранную в карточке единицу (null — базовая).
void selectUnitLocal(String productId, String? packageId) {
  selectedUnitNotifier.value = {
    ...selectedUnitNotifier.value,
    productId: packageId ?? '',
  };
}

/// Какую единицу показывать в карточке товара.
///
/// Порядок: явный выбор клиента, затем единица, которой товар уже лежит в корзине,
/// затем упаковка по умолчанию из 1С, иначе базовая единица.
ItemPackage? resolveSelectedUnit(
  Product product,
  Map<String, String> selected,
  Map<String, num> cart,
) {
  final chosen = selected[product.id];
  if (chosen != null) {
    return chosen.isEmpty ? null : product.packageById(chosen);
  }
  for (final packageId in cartUnitsOf(cart, product.id)) {
    if (packageId == null) return null;
    final package = product.packageById(packageId);
    if (package != null) return package;
  }
  return product.defaultPackage;
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
