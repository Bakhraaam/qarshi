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

  UserProfileModel({
    required this.id,
    required this.name,
    required this.priceType,
    required this.inn,
    required this.isBlocked,
  });

  // 1. Из JSON (для парсинга ответа от Django)
  factory UserProfileModel.fromJson(Map<String, dynamic>? json) {
    json ??= const {};
    return UserProfileModel(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      priceType: PriceType.fromJson(json['price_type']),
      inn: json['inn']?.toString() ?? '',
      isBlocked: json['is_blocked'] ?? false,
    );
  }
}

class SupportModel {
  final String phone;
  final String? tgUsername;
  final String instagram;

  SupportModel({required this.phone, this.tgUsername, this.instagram = ''});

  // 1. Из JSON (для парсинга ответа от Django)
  factory SupportModel.fromJson(Map<String, dynamic>? json) {
    json ??= const {};
    return SupportModel(
      phone: json['phone'] ?? '',
      tgUsername: json['telegram_username'] ?? '',
      instagram: json['instagram'] ?? '',
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

class Product {
  final String id;
  final String name;
  final num price;

  final String articul;
  final String imageUrl;
  final String categoryId;
  final String categoryName;

  final String unit;
  final num stock; // Остаток

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
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    // print(json);
    return Product(
      id: json['id'].toString(),
      name: json['name'] ?? '',
      price: double.tryParse(json['price'].toString()) ?? 0.0,
      imageUrl: json['image_url'] ?? '', // Фолбэк, если картинки нет
      categoryId: json['category_id'].toString(),
      // stock: double.tryParse(json['stock'].toString()) ?? 0.0,
      categoryName: json['category_name'],
      articul: json['articul'],
      unit: json['unit'],
      stock: json['stock'] ?? 0,
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
  num quantity;
  num total;
  CartItem({
    required this.product,
    required this.quantity,
    required this.total,
  });

  // Рассчитываем стоимость этой позиции локально
  num get totalWithItem => product.price * quantity;

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      product: Product.fromJson(json['product']),
      quantity: num.parse(json['quantity'].toString()) ?? 1,
      total: num.parse(json['total'].toString()) ?? 0,
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
  num quantity;
  num price;
  num totalAmount;
  OrderItem({
    required this.product,
    required this.quantity,
    required this.price,
    required this.totalAmount,
  });

  // Рассчитываем стоимость этой позиции локально
  num get totalWithItem => product.price * quantity;

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      product: Product.fromJson(json['product']),
      quantity: num.parse(json['quantity'].toString()),
      price: num.parse(json['price'].toString()),
      totalAmount: num.parse(json['total_amount'].toString()),
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
