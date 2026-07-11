// import 'package:flutter/foundation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:qarshi/core/data/api/api_django.dart';
import 'package:telegram_web_app/telegram_web_app.dart';
import '../../core/data/api/api_django.dart';
import 'dart:ui';

class TelegramWebAppAuthScreen extends StatefulWidget {
  const TelegramWebAppAuthScreen({super.key});

  @override
  State<TelegramWebAppAuthScreen> createState() =>
      _TelegramWebAppAuthScreenState();
}

class _TelegramWebAppAuthScreenState extends State<TelegramWebAppAuthScreen>
    with SingleTickerProviderStateMixin {
  final DjangoApi _api = DjangoApi();
  String _statusMessage = 'Инициализация сессии Telegram...';
  bool _hasError = false;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    // Начинаем проверку подлинности сразу при открытии экрана
    _authenticateViaTelegram();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _authenticateViaTelegram() async {
    try {
      if (TelegramWebApp.instance.isSupported) {
        TelegramWebApp.instance.ready();
        TelegramWebApp.instance.expand();
        // Отключаем вертикальный свайп-закрытие: иначе скролл вниз в каталоге
        // сворачивает окно WebApp вместо прокрутки контента.
        try {
          TelegramWebApp.instance.disableVerticalSwipes();
        } catch (_) {
          // Старые клиенты Telegram (Bot API < 7.7) метод не поддерживают — не критично.
        }
        // Открываем на весь экран (Bot API 8.0+). На старых клиентах — no-op.
        try {
          TelegramWebApp.instance.requestFullscreen();
        } catch (_) {}

        final String initData = TelegramWebApp.instance.initData.raw;

        if (initData.isNotEmpty) {
          setState(() => _statusMessage = 'Авторизация...');

          // 1. ПРОВЕРЯЕМ, ЕСТЬ ЛИ УЖЕ НОМЕР (например, если бот запрашивает его впервые)
          // TelegramWebApp позволяет вызвать нативный диалог запроса контакта:

          // setState(() => _statusMessage = 'Запрос номера телефона...');

          // Внимание: Этот метод асинхронный и вызывает нативное окно Telegram.
          // Результат прилетит в callback, но во многих пакетах можно использовать callback-подписку.
          // Если ваш пакет поддерживает прямой вызов с ответом:

          // TelegramWebApp.instance.requestContact((bool granted) async {
          // if (granted) {
          // Пользователь нажал "Поделиться"
          setState(() => _statusMessage = 'Авторизация...');

          // Снова берем initData (теперь в ней на бэкенде или в сессии могут обновиться данные,
          // либо Django сам посмотрит контакт через API бота)
          final String initData = TelegramWebApp.instance.initData.raw;

          final String? message = await _api.loginWithTelegram(initData);
          if (message == null && mounted) {
            context.go('/');
          } else {
            setState(() {
              _statusMessage = message!;
              _hasError = true;
            });
          }
          // } else {
          //   // Пользователь нажал "Отмена"
          //   setState(() {
          //     _statusMessage =
          //         'Для продолжения необходимо предоставить номер телефона.';
          //     _hasError = true;
          //   });
          // }
          // });
        } else {
          setState(() {
            _statusMessage = 'Данные авторизации Telegram пусты.';
            _hasError = true;
          });
        }
      } else {
        setState(() {
          _statusMessage = 'Приложение запущено вне Telegram...';
          _hasError = true;
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Критическая ошибка TWA:\n$e';
        _hasError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF2563EB);
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(32.w),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Логотип с пульсирующими кольцами (или иконка ошибки)
              SizedBox(
                width: 140.w,
                height: 140.w,
                child: _hasError
                    ? Center(
                        child: Container(
                          padding: EdgeInsets.all(22.w),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.error_outline_rounded,
                            color: Colors.red[600],
                            size: 48.w,
                          ),
                        ),
                      )
                    : AnimatedBuilder(
                        animation: _pulse,
                        builder: (context, child) {
                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              _ripple(accent, _pulse.value, 140.w),
                              _ripple(accent, (_pulse.value + 0.5) % 1.0, 140.w),
                              child!,
                            ],
                          );
                        },
                        child: Container(
                          width: 84.w,
                          height: 84.w,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [accent, Color(0xFF60A5FA)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.35),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.blur_on_rounded,
                            color: Colors.white,
                            size: 40.w,
                          ),
                        ),
                      ),
              ),
              SizedBox(height: 28.h),
              // Статус авторизации (без названия приложения)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  _statusMessage,
                  key: ValueKey(_statusMessage),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15.sp,
                    color: _hasError
                        ? Colors.red[700]
                        : const Color(0xFF475569),
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ),
              if (!_hasError) ...[
                SizedBox(height: 20.h),
                SizedBox(
                  width: 120.w,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      minHeight: 3.5,
                      backgroundColor: accent.withValues(alpha: 0.12),
                      valueColor: const AlwaysStoppedAnimation<Color>(accent),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Расходящееся кольцо для эффекта загрузки (t: 0..1).
  Widget _ripple(Color color, double t, double maxSize) {
    final size = maxSize * (0.55 + 0.45 * t);
    return Opacity(
      opacity: (1.0 - t) * 0.45,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2),
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _AdaptiveLoginScreenState();
}

class _AdaptiveLoginScreenState extends State<LoginScreen> {
  final DjangoApi _api = DjangoApi();
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isPasswordObscured = true;
  bool _isLoading = false;
  String? _errorMessage;
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final String username = _usernameController.text.trim();
    final String password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Заполните все поля');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final String? message = await _api.loginWithPassword(username, password);

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (message == null) {
      context.go('/');
    } else {
      setState(() => _errorMessage = message);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Получаем ширину экрана для адаптивной логики
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 650;

    return Scaffold(
      body: Stack(
        children: [
          // 1. Градиентный фон и декоративные круги
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Positioned(
            top: isDesktop ? 100 : -30,
            right: isDesktop ? 150 : -40,
            child: CircleAvatar(
              radius: isDesktop ? 140 : 90,
              backgroundColor: const Color(0xFF38BDF8).withOpacity(0.15),
            ),
          ),
          Positioned(
            bottom: isDesktop ? 100 : -50,
            left: isDesktop ? 150 : -30,
            child: CircleAvatar(
              radius: isDesktop ? 160 : 100,
              backgroundColor: const Color(0xFF818CF8).withOpacity(0.1),
            ),
          ), // 2. Основной контент
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                // На десктопе ограничиваем ширину, на мобилках — во весь экран
                width: isDesktop ? 450 : double.infinity,
                padding: EdgeInsets.all(isDesktop ? 40.0 : 16.0),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(isDesktop ? 0.03 : 0.0),
                  borderRadius: BorderRadius.circular(24),
                  border: isDesktop
                      ? Border.all(color: Colors.white.withOpacity(0.08))
                      : null,
                  boxShadow: isDesktop
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 40,
                            offset: const Offset(0, 20),
                          ),
                        ]
                      : [],
                ),
                child: isDesktop
                    // Эффект матового стекла (только для Desktop, чтобы не нагружать мобильные процессоры)
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: _buildFormContent(),
                        ),
                      )
                    : _buildFormContent(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Вынесли форму в отдельный метод для чистоты кода
  Widget _buildFormContent() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          const Text(
            'Вход в систему',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 32),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _errorMessage != null
                ? Container(
                    key: ValueKey(_errorMessage),
                    width: double.infinity,
                    margin: EdgeInsets.only(bottom: 16.h),
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          color: Colors.red,
                          size: 20,
                        ),
                        SizedBox(width: 10.w),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            maxLines: 4,
                            style: TextStyle(
                              color: Colors.red,
                              fontSize: 13,

                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ), // Поле Логина
          TextFormField(
            controller: _usernameController,
            style: const TextStyle(color: Colors.white),
            decoration: _buildInputDecoration(
              hint: 'Логин',
              icon: Icons.person,
            ),
            validator: (value) =>
                (value == null || value.isEmpty) ? 'Обязательное поле' : null,
          ),
          const SizedBox(height: 20),

          // Поле Пароля
          TextFormField(
            controller: _passwordController,
            obscureText: _isPasswordObscured,
            style: const TextStyle(color: Colors.white),
            decoration:
                _buildInputDecoration(
                  hint: 'Пароль',
                  icon: Icons.lock_open_rounded,
                ).copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isPasswordObscured
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: Colors.white60,
                      size: 20,
                    ),
                    onPressed: () => setState(
                      () => _isPasswordObscured = !_isPasswordObscured,
                    ),
                  ),
                ),
            validator: (value) => (value == null || value.length < 6)
                ? 'Минимум 6 символов'
                : null,
          ),

          // Ссылка восстановления
          // Align(
          //   alignment: Alignment.centerRight,
          //   child: TextButton(
          //     onPressed: () {},
          //     style: TextButton.styleFrom(foregroundColor: Colors.white54),
          //     child: const Text(
          //       'Забыли пароль?',
          //       style: TextStyle(fontSize: 13),
          //     ),
          //   ),
          // ),
          const SizedBox(height: 20),

          // Адаптивная Кнопка Войти
          MouseRegion(
            cursor: SystemMouseCursors.click, // Курсор-ручка для веб/десктопа
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(
                  colors: [Color(0xFF38BDF8), Color(0xFF818CF8)],
                ),
              ),
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Войти',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _buildInputDecoration({
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
      prefixIcon: Icon(icon, color: Colors.white54, size: 22),
      filled: true,
      fillColor: Colors.white.withOpacity(0.05),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.redAccent.withOpacity(0.5)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
    );
  }
}
