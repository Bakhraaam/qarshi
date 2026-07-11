import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qarshi/core/data/constants.dart';
import 'package:qarshi/core/utils/telegram_launch.dart';
import 'package:qarshi/presentations/screens/cart_screen_quantity_input.dart';
import 'package:qarshi/presentations/screens/catalog_screen_responsive.dart';
import 'package:qarshi/presentations/screens/home_screen_adaptive.dart';
import 'package:qarshi/presentations/screens/login.dart';
import 'package:qarshi/presentations/screens/orders_screen.dart';
import 'package:qarshi/presentations/screens/reconciliation_report_screen.dart';
// import 'utils/auth';

class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/',
    // МЕХАНИЗМ REDIRECT (Защита роутов)
    redirect: (context, state) async {
      // Роутер честно проверяет, есть ли токен в SharedPreferences
      // String? _token = await AuthTokenManager.getToken();
      // final bool isLoggedIn = _token != null && _token.isNotEmpty;

      // Экраны авторизации, на которые redirect не должен зацикливаться
      final location = state.matchedLocation;
      final bool isGoingToAuth =
          location == '/login' || location == '/login/telegram';

      if (tokenAccess.isEmpty && !isGoingToAuth) {
        // Запуск внутри Telegram WebApp → бесшовный TWA-вход,
        // иначе — обычная форма логина/пароля.
        return isRunningInTelegram() ? '/login/telegram' : '/login';
      }

      // if (isLoggedIn && isGoingToLogin) {
      // return '/'; // Авторизован — перекидываем на рабочий стол
      // }

      return null; // Разрешаем переход (нет перенаправлений)
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/login/telegram',
        builder: (context, state) => const TelegramWebAppAuthScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) {
          return const HomeScreen(); // Наш главный экран (как на макете)
        },
      ),

      GoRoute(
        path: '/reports',
        builder: (context, state) => const ReconciliationReportScreen(),
      ),
      GoRoute(
        path: '/catalog',
        builder: (context, state) => const CatalogScreen(),
      ),
      GoRoute(path: '/cart', builder: (context, state) => const CartScreen()),
      GoRoute(
        path: '/orders',
        builder: (context, state) => const OrdersScreen(),
      ),
    ],
  );
}
