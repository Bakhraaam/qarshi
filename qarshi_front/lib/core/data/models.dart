import 'package:qarshi/core/utils/formatters.dart';

import 'package:flutter/material.dart';

// user_data: {'id': 8,
// 'profile': {'id': None, 'name': 'Новый аккаунт (Ожидает подтверждения 1С)', 'inn': None, 'status': 'new', 'is_blocked': False, 'price_type': {'id': '1ec7aec3-0ab3-11ef-9dfb-00155db35c07', 'name': 'Розничная UZS', 'currency': 'UZS'}},
// 'support': {'phone': '+998937748884', 'telegram_username': ''},
// 'telegram_account': {'telegram_id': 642933939, 'telegram_username': 'terasoft_b', 'phone': None, 'tg_first_name': 'TERASOFT', 'tg_last_name': '', 'tg_photo_url': 'https://t.me/i/userpic/320/q3xzu1dGMkuezkViTbD4pJUZNDulu7-CnNKmViAqdjc.svg', 'tg_language_code': 'ru'}}

class UserModel {
  final int id;
  final TelegramAccountModel? telegramAccount;
  final UserProfileModel userProfile;
  final SupportModel support;

  UserModel({
    required this.id,
    this.telegramAccount,
    required this.userProfile,
    required this.support,
  });

  /// Возвращает имя пользователя на основе заполненных данных
  String getName() {
    // 1. Проверяем, заполнено ли имя в профиле пользователя
    if (userProfile.name.trim().isNotEmpty) {
      return userProfile.name.trim();
    }

    // 2. Если в профиле пусто, проверяем, привязан ли Telegram
    if (telegramAccount != null) {
      final firstName = telegramAccount!.firstName.trim();
      final lastName = telegramAccount!.lastName.trim();

      // Собираем полное имя из Telegram, убирая лишние пробелы
      final telegramName = '$firstName $lastName'.trim();

      if (telegramName.isNotEmpty) {
        return telegramName;
      }

      // Если имя/фамилия в TG пустые, но есть юзернейм
      if (telegramAccount!.username.trim().isNotEmpty) {
        return '@${telegramAccount!.username.trim()}';
      }
    }

    // 3. Резервный вариант, если вообще ничего не заполнено
    return '$id';
  }

  // 1. Из JSON (для парсинга ответа от Django)
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? 0,
      userProfile: UserProfileModel.fromJson(json['profile']),
      // telegram_account может отсутствовать (вход по паролю) — тогда null.
      telegramAccount: json['telegram_account'] == null
          ? null
          : TelegramAccountModel.fromJson(json['telegram_account']),
      support: SupportModel.fromJson(json['support']),
    );
  }

  // 2. В JSON (чтобы сохранить объект как строку в SharedPreferences)
  Map<String, dynamic> toJson() {
    return {'id': id};
  }
}

class UserProfileModel {
  final String id;
  final String name;
  final PriceType priceType;
  final String inn;
  final bool isBlocked;
  final String guidPartner1c; // пусто = не зарегистрирован в 1С

  UserProfileModel({
    required this.id,
    required this.name,
    required this.priceType,
    required this.inn,
    required this.isBlocked,
    this.guidPartner1c = '',
  });

  bool get isRegistered => guidPartner1c.trim().isNotEmpty;

  // 1. Из JSON (для парсинга ответа от Django)
  factory UserProfileModel.fromJson(Map<String, dynamic>? json) {
    json ??= const {};
    return UserProfileModel(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      priceType: PriceType.fromJson(json['price_type']),
      inn: json['inn']?.toString() ?? '',
      isBlocked: json['is_blocked'] ?? false,
      guidPartner1c: json['guid_partner1c']?.toString() ?? '',
    );
  }
}

class SupportModel {
  final String phone;
  final String? tgUsername;
  final String instagram;
  final String unregisteredNotice;

  SupportModel({
    required this.phone,
    this.tgUsername,
    this.instagram = '',
    this.unregisteredNotice = '',
  });

  // 1. Из JSON (для парсинга ответа от Django)
  factory SupportModel.fromJson(Map<String, dynamic>? json) {
    json ??= const {};
    return SupportModel(
      phone: json['phone'] ?? '',
      tgUsername: json['telegram_username'] ?? '',
      instagram: json['instagram'] ?? '',
      unregisteredNotice: json['unregistered_notice'] ?? '',
    );
  }
}

class TelegramAccountModel {
  final int id;
  final String username;
  final String phone;
  final String firstName;
  final String lastName;
  final String photoUrl;
  final String languageCode;

  TelegramAccountModel({
    required this.id,
    required this.username,
    required this.firstName,
    required this.lastName,
    required this.languageCode,
    required this.phone,
    required this.photoUrl,
  });

  // 1. Из JSON (для парсинга ответа от Django)
  factory TelegramAccountModel.fromJson(Map<String, dynamic>? json) {
    json ??= const {};
    return TelegramAccountModel(
      id: json['id'] ?? 0,
      firstName: json['first_name'] ?? '',
      lastName: json['last_name'] ?? '',
      username: json['username'] ?? '',
      phone: json['phone']?.toString() ?? '',
      photoUrl: json['photo_url'] ?? '',
      languageCode: json['language_code'] ?? '',
    );
  }
}

class PriceType {
  final String id;
  final String name;
  final String currency;

  PriceType({required this.id, required this.name, required this.currency});

  factory PriceType.fromJson(Map<String, dynamic>? json) {
    json ??= const {};
    return PriceType(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      currency: json['currency'] ?? 'UZS',
    );
  }
}

class ProductCategory {
  final String id;
  final String name;

  ProductCategory({required this.id, required this.name});

  factory ProductCategory.fromJson(Map<String, dynamic> json) {
    return ProductCategory(id: json['id'].toString(), name: json['name'] ?? '');
  }
}

/// Ключ строки корзины: товар + единица. Базовая единица кодируется пустой строкой,
/// поэтому «5 коробок» и «3 шт» одного товара — две разные строки.
String cartLineKey(String productId, String? packageId) =>
    '$productId|${packageId ?? ''}';

/// Упаковка товара: блок, коробка, канистра.
///
/// Цена в каталоге ВСЕГДА за базовую единицу (`Product.unit`), а упаковка — только
/// множитель: «Коробка» с quantity = 10 значит, что 2 коробки это 20 базовых единиц.
class ItemPackage {
  final String id;
  final String name;

  /// Сколько базовых единиц товара в одной упаковке.
  final num quantity;
  final bool isDefault;

  const ItemPackage({
    required this.id,
    required this.name,
    required this.quantity,
    this.isDefault = false,
  });

  factory ItemPackage.fromJson(Map<String, dynamic> json) {
    final raw = num.tryParse(json['quantity'].toString()) ?? 1;
    return ItemPackage(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? '',
      // Нулевой или отрицательный множитель сделал бы деление бессмысленным.
      quantity: raw > 0 ? raw : 1,
      isDefault: json['is_default'] == true,
    );
  }
}

class Product {
  final String id;
  final String name;
  final num price;

  final String articul;
  final String imageUrl;

  /// Все картинки товара с бэкенда (первая — главная). Пустой список = картинок нет.
  final List<String> images;
  final String categoryId;
  final String categoryName;

  final String unit;
  final num stock; // Остаток

  /// Варианты фасовки сверх базовой единицы. Пусто — товар продаётся только `unit`.
  final List<ItemPackage> packages;

  Product({
    required this.id,
    required this.name,
    required this.price,

    required this.articul,
    required this.imageUrl,
    required this.categoryId,
    required this.categoryName,
    required this.unit,
    required this.stock,
    this.images = const [],
    this.packages = const [],
  });

  /// Упаковка по её id; null — базовая единица (или упаковку уже удалили из 1С).
  ItemPackage? packageById(String? packageId) {
    if (packageId == null || packageId.isEmpty) return null;
    for (final package in packages) {
      if (package.id == packageId) return package;
    }
    return null;
  }

  /// Цена за выбранную единицу. В прайсе цена всегда за базовую единицу,
  /// а за коробку она умножается на вместимость коробки.
  num priceFor(ItemPackage? package) => price * (package?.quantity ?? 1);

  /// Подпись единицы: название упаковки или базовая единица товара.
  String unitLabelFor(ItemPackage? package) => package?.name ?? unit;

  /// Какую единицу подставить, когда клиент ещё ничего не выбирал.
  ItemPackage? get defaultPackage {
    for (final package in packages) {
      if (package.isDefault) return package;
    }
    return null;
  }

  /// Картинки для галереи: список с бэкенда, а если он пуст — одна главная картинка.
  List<String> get gallery {
    if (images.isNotEmpty) return images;
    return imageUrl.isEmpty ? const [] : [imageUrl];
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    // print(json);
    final rawImages = json['images'];
    return Product(
      id: json['id'].toString(),
      name: json['name'] ?? '',
      price: double.tryParse(json['price'].toString()) ?? 0.0,
      imageUrl: json['image_url'] ?? '', // Фолбэк, если картинки нет
      images: rawImages is List
          ? rawImages
                .where((e) => e != null && e.toString().isNotEmpty)
                .map((e) => e.toString())
                .toList()
          : const [],
      categoryId: json['category_id']?.toString() ?? '',
      // stock: double.tryParse(json['stock'].toString()) ?? 0.0,
      categoryName: json['category_name']?.toString() ?? '',
      articul: json['articul']?.toString() ?? '',
      unit: json['unit']?.toString() ?? '',
      stock: json['stock'] ?? 0,
      packages: json['packages'] is List
          ? (json['packages'] as List)
                .whereType<Map<String, dynamic>>()
                .map(ItemPackage.fromJson)
                .toList()
          : const [],
    );
  }
}

class PaginatedProducts {
  final int count;
  final String? nextUrl;
  final List<Product> results;

  PaginatedProducts({required this.count, this.nextUrl, required this.results});
}

class CartItem {
  final Product product;

  /// Количество в БАЗОВЫХ единицах товара — как и на бэкенде.
  num quantity;
  num total;

  /// Единица, в которой набрана ЭТА строка (null — базовая единица).
  /// Один товар может лежать в корзине несколькими строками: коробками и штуками.
  /// Упаковку берём из самой строки, а не из product.packages: там нет
  /// недействительных упаковок, а строка с такой упаковкой всё ещё в корзине.
  final ItemPackage? package;

  CartItem({
    required this.product,
    required this.quantity,
    required this.total,
    this.package,
  });

  String? get packageId => package?.id;

  /// Ключ строки в глобальном состоянии корзины.
  String get lineKey => cartLineKey(product.id, packageId);

  // Рассчитываем стоимость этой позиции локально
  num get totalWithItem => product.price * quantity;

  /// Шаг счётчика в базовых единицах: 1 шт или целая коробка.
  num get step => package?.quantity ?? 1;

  /// Количество в единице строки: 50 шт при коробке по 10 — это 5 коробок.
  num get displayQuantity => quantity / step;

  /// Подпись единицы рядом со счётчиком.
  String get unitLabel => package?.name ?? product.unit;

  /// Цена за единицу строки: за коробку — цена базовой единицы, умноженная на вместимость.
  num get unitPrice => product.price * step;

  factory CartItem.fromJson(Map<String, dynamic> json) {
    final rawPackage = json['package'];
    return CartItem(
      product: Product.fromJson(json['product']),
      quantity: num.tryParse(json['quantity'].toString()) ?? 1,
      total: num.tryParse(json['total'].toString()) ?? 0,
      package: rawPackage is Map<String, dynamic>
          ? ItemPackage.fromJson(rawPackage)
          : null,
    );
  }

  static List<CartItem> fromListJson(dynamic jsonList) {
    // Проверяем, что пришел не пустой список и это действительно List
    if (jsonList == null || jsonList is! List) {
      return [];
    }
    // Проходимся маппингом по каждому элементу массива и превращаем его в объект CartItem
    return jsonList
        .map((json) => CartItem.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}

class OrderItem {
  final Product product;

  /// Количество в БАЗОВЫХ единицах товара, цена — за ту же базовую единицу.
  num quantity;
  num price;
  num totalAmount;

  /// Снимок упаковки на момент заказа: чем клиент набирал позицию.
  /// Пусто — позиция набрана базовыми единицами.
  final String packageName;
  final num packageCount;

  OrderItem({
    required this.product,
    required this.quantity,
    required this.price,
    required this.totalAmount,
    this.packageName = '',
    this.packageCount = 0,
  });

  /// Количество для показа: «2 коробки» вместо «20 шт», если упаковка была.
  String get quantityLabel {
    if (packageName.isEmpty || packageCount <= 0) {
      return '${formatNumber(quantity)} ${product.unit}';
    }
    return '${formatNumber(packageCount)} $packageName '
        '(${formatNumber(quantity)} ${product.unit})';
  }

  // Рассчитываем стоимость этой позиции локально
  num get totalWithItem => product.price * quantity;

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      product: Product.fromJson(json['product']),
      quantity: num.parse(json['quantity'].toString()),
      price: num.parse(json['price'].toString()),
      totalAmount: num.parse(json['total_amount'].toString()),
      packageName: json['package_name']?.toString() ?? '',
      packageCount: num.tryParse(json['package_count'].toString()) ?? 0,
    );
  }

  static List<OrderItem> fromListJson(dynamic jsonList) {
    // Проверяем, что пришел не пустой список и это действительно List
    if (jsonList == null || jsonList is! List) {
      return [];
    }
    // Проходимся маппингом по каждому элементу массива и превращаем его в объект CartItem
    return jsonList
        .map((json) => OrderItem.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}

enum OrderStatus {
  newOrder('new', 'Новый', Color(0xFF2563EB)), // Синий
  processing(
    'processing',
    'В обработке',
    Color(0xFFD97706),
  ), // Оранжевый/Желтый
  completed('completed', 'Завершен', Color(0xFF10B981)), // Зеленый
  canceled('canceled', 'Отменен', Color(0xFFEF4444)); // Красный

  // Поля внутри каждого статуса
  final String jsonKey;
  final String label;
  final Color color;

  const OrderStatus(this.jsonKey, this.label, this.color);

  // Безопасный метод фабрики: превращает строку от Django в наш Enum
  factory OrderStatus.fromJson(String key) {
    return OrderStatus.values.firstWhere(
      (element) => element.jsonKey == key.toLowerCase(),
      orElse: () => OrderStatus
          .processing, // Если пришел неизвестный статус — ставим дефолтный
    );
  }
}

// Модель самого заказа
class OrderModel {
  final String id;
  final String number; // Номер заказа из 1С
  final String date; // Дата оформления
  final OrderStatus status; // Текстовый статус: "Новый", "Проведен", "Отгружен"
  final num totalAmount;
  final List<OrderItem> items;

  OrderModel({
    required this.id,
    required this.number,
    required this.date,
    required this.status,
    required this.totalAmount,
    required this.items,
  });

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    var list = json['items'] as List? ?? [];
    List<OrderItem> orderItems = list
        .map((i) => OrderItem.fromJson(i))
        .toList();

    return OrderModel(
      id: json['id'] ?? '',
      number: json['order_number'] ?? '№-',
      date: formatDateTime(json['created_at']) ?? '',
      status: OrderStatus.fromJson(json['status']),
      totalAmount: num.tryParse(json['total_amount'].toString()) ?? 0.0,
      items: orderItems,
    );
  }

  static List<OrderModel> fromListJson(dynamic jsonList) {
    if (jsonList == null || jsonList is! List) return [];
    return jsonList
        .map((json) => OrderModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}

/// Итог отправки заказа: либо номер и время, либо текст ошибки.
class OrderSubmitResult {
  final String? orderNumber;

  /// Время оформления в ISO-формате, как его вернул сервер.
  final String createdAt;
  final String? error;

  /// Машинный код ошибки с бэкенда, например `unregistered`.
  final String? code;

  const OrderSubmitResult._({
    this.orderNumber,
    this.createdAt = '',
    this.error,
    this.code,
  });

  const OrderSubmitResult.success({
    required String orderNumber,
    String createdAt = '',
  }) : this._(orderNumber: orderNumber, createdAt: createdAt);

  const OrderSubmitResult.failure(String error, {String? code})
    : this._(error: error, code: code);

  bool get isSuccess => orderNumber != null;

  /// Клиент не привязан к контрагенту в 1С — показываем отдельное окно.
  bool get isUnregistered => code == 'unregistered';
}

/// Заявка на акт сверки. Файл готовит 1С, поэтому заявка живёт в трёх состояниях.
class ActRequest {
  final String id;
  final String status; // pending | ready | failed
  final String dateFrom;
  final String dateTo;
  final String filename;

  /// Ссылка на готовый файл (подписанная, живёт неделю). Пусто, пока не готов.
  final String fileUrl;

  /// Текст от 1С, когда акт построить не удалось.
  final String message;

  /// Когда клиент отправил заявку (ISO с сервера).
  final String createdAt;

  const ActRequest({
    required this.id,
    required this.status,
    required this.dateFrom,
    required this.dateTo,
    this.filename = '',
    this.fileUrl = '',
    this.message = '',
    this.createdAt = '',
  });

  bool get isPending => status == 'pending';

  /// Период в виде «01.09.2026 — 21.09.2026».
  String get periodLabel =>
      '${formatIsoDate(dateFrom)} — ${formatIsoDate(dateTo)}';

  String get statusLabel => switch (status) {
    'ready' => 'Готов',
    'failed' => 'Ошибка',
    _ => 'Формируется',
  };

  bool get isReady => status == 'ready';
  bool get isFailed => status == 'failed';

  factory ActRequest.fromJson(Map<String, dynamic> json) {
    return ActRequest(
      id: json['id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      dateFrom: json['date_from']?.toString() ?? '',
      dateTo: json['date_to']?.toString() ?? '',
      filename: json['filename']?.toString() ?? '',
      fileUrl: json['file_url']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      createdAt: json['created_at']?.toString() ?? '',
    );
  }
}
