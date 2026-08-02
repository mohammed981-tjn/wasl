import 'package:dio/dio.dart';
import 'env.dart';

class ApiClient {
  ApiClient._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: Env.baseUrl,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 20),
        headers: const {'Accept': 'application/json'},
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          // Add token here later when you implement auth
          return handler.next(options);
        },
        onError: (e, handler) => handler.next(e),
      ),
    );
  }

  static final ApiClient instance = ApiClient._internal();

  late final Dio _dio;
  Dio get dio => _dio;
}
