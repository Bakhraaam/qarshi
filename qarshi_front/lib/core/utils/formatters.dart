import 'package:intl/intl.dart';
import 'package:qarshi/core/data/constants.dart';

String formatPrice(num price) {
  // Паттерн '#,##0.##' означает: разделять тысячи, выводить минимум 0 знаков, максимум 2 знака после запятой (если они есть)
  final formatter = NumberFormat('#,##0.##', 'ru_RU');

  // Заменяем стандартные неразрывные пробелы на обычные для стабильного отображения на всех устройствах
  return formatter.format(price).replaceAll('\u00A0', ' ') +
      ' ' +
      currentUser!.userProfile.priceType.currency;
}

/// 1. Переводит ISO-строку в красивую дату (например: 30.05.2026)
String formatDate(String isoString) {
  if (isoString.isEmpty) return '';
  try {
    // DateTime.parse отлично понимает формат ISO 8601 автоматически
    DateTime dateTime = DateTime.parse(isoString).toLocal();
    return DateFormat('dd.MM.yyyy').format(dateTime);
  } catch (e) {
    print('Ошибка форматирования даты: $e');
    return isoString; // В случае ошибки возвращаем исходную строку
  }
}

/// 2. Переводит ISO-строку только во время (например: 17:27)
String formatTime(String isoString) {
  if (isoString.isEmpty) return '';
  try {
    DateTime dateTime = DateTime.parse(isoString).toLocal();
    return DateFormat('HH:mm').format(dateTime);
  } catch (e) {
    print('Ошибка форматирования времени: $e');
    return isoString;
  }
}

/// 3. Полный b2b-вариант: Дата и время вместе (например: 30.05.2026 в 17:27)
String formatDateTime(String isoString) {
  if (isoString.isEmpty) return '';
  try {
    DateTime dateTime = DateTime.parse(isoString).toLocal();
    String date = DateFormat('dd.MM.yyyy').format(dateTime);
    String time = DateFormat('HH:mm').format(dateTime);
    return '$date $time';
  } catch (e) {
    print('Ошибка форматирования даты/времени: $e');
    return isoString;
  }
}
