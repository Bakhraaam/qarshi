import 'package:dio/dio.dart';

class Api1c {
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl:
          'https://api.yourdomain.com/1c_sync/', // Лучше через Django-мидлварь
      connectTimeout: const Duration(
        seconds: 30,
      ), // Для 1С таймаут делаем больше
    ),
  );

  // Получение акта сверки по контрагенту за период
  Future<Map<String, dynamic>?> getActSverki({
    required String contractorId,
    required String dateFrom,
    required String dateTo,
  }) async {
    try {
      final response = await _dio.post(
        'reports/act-sverki/',
        data: {
          'contractor_id': contractorId,
          'date_from': dateFrom,
          'date_to': dateTo,
        },
      );
      return response.data; // Возвращает JSON с табличной частью акта
    } catch (e) {
      print('1C API Error: $e');
      return null;
    }
  }
}
