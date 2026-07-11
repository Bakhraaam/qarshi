import 'package:dio/dio.dart';
import 'package:qarshi/core/data/constants.dart';
import 'package:qarshi/core/data/models.dart';
import 'package:qarshi/core/utils/auth_token_manager.dart';
import 'package:qarshi/core/utils/domain_resolver.dart';
import 'package:telegram_web_app/telegram_web_app.dart';

class DjangoApi {
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: DomainResolver.getBaseApiUrl(),
      // baseUrl:
      //     'http://127.0.0.1:8000/api/v1/avto/', // URL вашего Django бэкенда
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
  Future<String?> loginWithPassword(String username, String password) async {
    try {
      final response = await _dio.post(
        'auth/login/',
        data: {'username': username, 'password': password},
      );

      print('login: ${_dio.options.baseUrl}');

      // Сюда мы попадаем только при статусе 200 (успех)
      if (response.statusCode == 200 && response.data != null) {
        tokenAccess =
            response.data['access'] ?? response.data['tokens']?['access'] ?? '';

        currentUser = UserModel.fromJson(response.data['user']);
        // Сохраняем токен НЕблокирующе (см. коммент в loginWithTelegram).
        AuthTokenManager.saveToken(tokenAccess).catchError((_) {});
        return null; // Всё отлично
      }

      return 'Непредвиденный ответ сервера.';
    } on DioException catch (e) {
      // 1. Проверяем, ответил ли вообще бэкенд данными
      if (e.response != null && e.response?.data != null) {
        final responseData = e.response!.data;

        // Вытаскиваем "message", который вы прописали в Django
        if (responseData is Map && responseData.containsKey('message')) {
          return responseData['message'].toString();
          // Вернет: "Пользователь заблокирован в 1С." или "Неверный логин или пароль"
        }
      }

      // 2. Если бэкенд не ответил (например, упал сервер или нет интернета)
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Превышено время ожидания ответа от сервера.';
        case DioExceptionType.connectionError:
          return 'Нет интернет-соединения или сервер недоступен.';
        default:
          return 'Ошибка сети: ${e.message}';
      }
    } catch (e) {
      // На случай других системных ошибок Dart
      return 'Произошла непредвиденная ошибка: $e';
    }
  }

  Future<String?> loginWithTelegram(
    String initData, {
    String? phone = null,
  }) async {
    try {
      final response = await _dio.post(
        'auth/telegram/',
        data: {'init_data': initData, 'phone': phone},
      );

      if (response.statusCode == 200 && response.data != null) {
        tokenAccess = response.data['tokens']?['access'] ?? '';

        currentUser = UserModel.fromJson(response.data['user']);
        // Сохраняем токен НЕблокирующе: в вебвью Telegram localStorage может быть
        // недоступен и подвесить/кинуть — вход не должен от этого зависеть.
        AuthTokenManager.saveToken(tokenAccess).catchError((_) {});
        return null; // Всё отлично
      }

      return '${response.data}';
    } on DioException catch (e) {
      // 1. Проверяем, ответил ли вообще бэкенд данными
      if (e.response != null && e.response?.data != null) {
        final responseData = e.response!.data;

        // Вытаскиваем "message", который вы прописали в Django
        if (responseData is Map && responseData.containsKey('message')) {
          return responseData['message'].toString();
          // Вернет: "Пользователь заблокирован в 1С." или "Неверный логин или пароль"
        }
      }

      // 2. Если бэкенд не ответил (например, упал сервер или нет интернета)
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Превышено время ожидания ответа от сервера.';
        case DioExceptionType.connectionError:
          return 'Нет интернет-соединения или сервер недоступен.';
        default:
          return 'Ошибка сети: ${e.message}';
      }
    } catch (e) {
      // На случай других системных ошибок Dart
      return 'Произошла непредвиденная ошибка: $e';
    }
  }

  // Пример получения данных профиля пользователя
  Future<Map<String, dynamic>?> getUserProfile() async {
    try {
      final response = await _dio.get(
        'user/profile/',
        options: Options(headers: {'Authorization': 'Bearer $tokenAccess'}),
      );
      return response.data;
    } catch (e) {
      // Здесь должна быть обработка ошибок
      print('Django API Error: $e');
      return null;
    }
  }

  // Получить список категорий
  Future<List<ProductCategory>> getCategories() async {
    try {
      final response = await _dio.get(
        'categories/',
        options: Options(
          headers: {
            'Authorization': 'Bearer $tokenAccess',
            // 'ngrok-skip-browser-warning': 'any-value',
          },
        ),
      );
      // print('_dio.options.baseUrl: ${_dio.options.baseUrl}');
      if (response.statusCode == 200) {
        List<dynamic> data = response.data;
        return data.map((json) => ProductCategory.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      print('Ошибка получения категорий: $e');
      return [];
    }
  }

  Future<PaginatedProducts?> getProducts({
    String? categoryId,
    int page = 1,
    double? minPrice,
    double? maxPrice,
    String? query,
  }) async {
    try {
      final Map<String, dynamic> queryParams = {'page': page};

      if (categoryId != null) queryParams['category'] = categoryId;
      if (minPrice != null) queryParams['price_from'] = minPrice;
      if (maxPrice != null) queryParams['price_to'] = maxPrice;
      if (query != null) queryParams['query'] = query;

      final response = await _dio.get(
        'products/',
        queryParameters: queryParams,
      );

      if (response.statusCode == 200) {
        // print(response.data['results'][0]);
        final Map<String, dynamic> data = response.data;
        final List<dynamic> resultsList = data['results'] ?? [];

        List<Product> products = resultsList
            .map((json) => Product.fromJson(json))
            .toList();

        return PaginatedProducts(
          count: data['count'] ?? 0,
          nextUrl: data['next'],
          results: products,
        );
      }
      return null;
    } catch (e) {
      print('Ошибка получения товаров: $e');
      return null;
    }
  }

  // 1. Получить все товары в корзине
  Future<List<CartItem>> getCart() async {
    try {
      final response = await _dio.get(
        'cart/',
        options: Options(headers: {'Authorization': 'Bearer $tokenAccess'}),
      );
      if (response.statusCode == 200) {
        var data = response.data['results'];
        List<CartItem> result = CartItem.fromListJson(data);
        return result;
      }
      return [];
    } catch (e) {
      print('Ошибка получения корзины: $e');
      return [];
    }
  }

  // 2. Обновить количество товара в корзине (или добавить, если его нет)
  Future<bool> updateCartItem(String productId, num quantity) async {
    print('tokenAccess: $tokenAccess');
    try {
      final response = await _dio.post(
        'cart/',
        data: {'item_id': productId, 'quantity': quantity},
        options: Options(headers: {'Authorization': 'Bearer $tokenAccess'}),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Ошибка обновления корзины: $e');
      return false;
    }
  }

  // 3. Удалить товар из корзины полностью
  Future<bool> removeCart(String productId) async {
    try {
      final response = await _dio.delete(
        'cart/clear/',
        options: Options(headers: {'Authorization': 'Bearer $tokenAccess'}),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Ошибка удаления из корзины: $e');
      return false;
    }
  }

  // Возвращает ID товара и его количество в корзине: {'product_id': quantity}
  Future<Map<String, num>> getCartQuantities() async {
    try {
      final cartItems = await getCart(); // Используем метод из предыдущего шага
      final Map<String, num> quantities = {};
      for (var item in cartItems) {
        quantities[item.product.id] = item.quantity;
      }
      return quantities;
    } catch (e) {
      return {};
    }
  }

  Future<List<OrderModel>> getOrders() async {
    try {
      final response = await _dio.get(
        'orders/',
        options: Options(headers: {'Authorization': 'Bearer $tokenAccess'}),
      ); // Ваш эндпоинт в Django
      if (response.statusCode == 200) {
        return OrderModel.fromListJson(response.data);
      }
      return [];
    } catch (e) {
      print('Ошибка загрузки списка заказов: $e');
      return [];
    }
  }

  Future<String?> createOrder() async {
    try {
      final response = await _dio.post(
        'orders/',
        options: Options(headers: {'Authorization': 'Bearer $tokenAccess'}),
      ); // Ваш эндпоинт в Django
      if (response.statusCode == 200) {
        return response.data['order_number'] ??
            response.data['number'] ??
            'Успешно';
      }
      return null;
    } catch (e) {
      print('Ошибка загрузки списка заказов: $e');
      return null;
    }
  }

  Future<List<OrderItem>> getOrderDetails(String id) async {
    try {
      final response = await _dio.get(
        'orders/$id/',
        options: Options(headers: {'Authorization': 'Bearer $tokenAccess'}),
      ); // Ваш эндпоинт в Django
      if (response.statusCode == 200) {
        // print(response.data);
        return OrderItem.fromListJson(response.data['items']);
      }
      return [];
    } catch (e) {
      print('Ошибка загрузки списка заказов: $e');
      return [];
    }
  }
}
