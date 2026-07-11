import 'package:shared_preferences/shared_preferences.dart';

class AuthTokenManager {
  static const String _tokenKey = 'auth_jwt_token';

  // 1. Сохранение токена после успешного входа через Telegram
  static Future<void> saveToken(String token) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  // 2. Чтение токена (используется Интерцептором и GoRouter)
  static Future<String?> getToken() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  // 3. Удаление токена (для выхода из системы / разлогина)
  static Future<void> clearToken() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }
}
