import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:qarshi/core/data/constants.dart';
import 'package:qarshi/core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'package:url_strategy/url_strategy.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  setPathUrlStrategy();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Инициализация ScreenUtil для адаптивности шрифтов и размеров элементов
    return ScreenUtilInit(
      designSize: const Size(
        375,
        812,
      ), // Базовый размер экрана под макет (iPhone X)
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp.router(
          title: '$AppName',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.light, // Можно переключать динамически
          routerConfig: AppRouter.router,
        );
      },
    );
  }
}
