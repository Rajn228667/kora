import 'package:dio/dio.dart';
import '../config/env.dart';
import '../storage/token_storage.dart';
import 'api_exception.dart';

/// Transport abstraction. Repositories depend on this interface only,
/// so `MockApiClient` can stand in for the whole backend in mock mode.
abstract class ApiClient {
  /// Called when refresh rotation fails and the session is dead.
  void Function()? onSessionExpired;

  Future<dynamic> get(String path,
      {Map<String, dynamic>? query, bool auth = true,});
  Future<dynamic> post(String path,
      {Object? body, Map<String, dynamic>? query, bool auth = true,});
  Future<dynamic> patch(String path,
      {Object? body, bool auth = true,});
  Future<dynamic> delete(String path,
      {Object? body, bool auth = true,});
  Future<dynamic> put(String path, {Object? body, bool auth = true});
}

/// Dio implementation with bearer auth, single-flight token refresh
/// and retry-once-after-refresh on 401.
class DioApiClient implements ApiClient {
  DioApiClient({required TokenStorage tokens})
      : _tokens = tokens,
        _dio = Dio(
          BaseOptions(
            baseUrl: AppEnv.apiBase,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 20),
            headers: {'Accept': 'application/json'},
          ),
        );

  final Dio _dio;
  final TokenStorage _tokens;
  Future<bool>? _refreshing;

  @override
  void Function()? onSessionExpired;

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool auth = true,
    bool retried = false,
  }) async {
    try {
      final opts = Options(method: method);
      if (auth) {
        final token = await _tokens.readAccess();
        if (token != null) {
          opts.headers = {'Authorization': 'Bearer $token'};
        }
      }
      final res = await _dio.request<dynamic>(
        path,
        data: body,
        queryParameters: query,
        options: opts,
      );
      return res.data;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 && auth && !retried) {
        final ok = await _refresh();
        if (ok) {
          return _send(method, path,
              body: body, query: query, auth: auth, retried: true,);
        }
        onSessionExpired?.call();
        throw ApiException.fromBody(401, e.response?.data);
      }
      throw _mapError(e);
    }
  }

  Future<bool> _refresh() {
    return _refreshing ??= _doRefresh().whenComplete(() {
      _refreshing = null;
    });
  }

  Future<bool> _doRefresh() async {
    final refresh = await _tokens.readRefresh();
    if (refresh == null) return false;
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refreshToken': refresh},
      );
      final data = res.data!;
      await _tokens.saveTokens(
        access: data['accessToken'] as String,
        refresh: data['refreshToken'] as String,
      );
      return true;
    } on DioException {
      await _tokens.clear();
      return false;
    }
  }

  ApiException _mapError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException.timeout();
      case DioExceptionType.connectionError:
        return ApiException.network();
      default:
        return ApiException.fromBody(e.response?.statusCode, e.response?.data);
    }
  }

  @override
  Future<dynamic> get(String path,
          {Map<String, dynamic>? query, bool auth = true,}) =>
      _send('GET', path, query: query, auth: auth);

  @override
  Future<dynamic> post(String path,
          {Object? body, Map<String, dynamic>? query, bool auth = true,}) =>
      _send('POST', path, body: body, query: query, auth: auth);

  @override
  Future<dynamic> patch(String path, {Object? body, bool auth = true}) =>
      _send('PATCH', path, body: body, auth: auth);

  @override
  Future<dynamic> put(String path, {Object? body, bool auth = true}) =>
      _send('PUT', path, body: body, auth: auth);

  @override
  Future<dynamic> delete(String path, {Object? body, bool auth = true}) =>
      _send('DELETE', path, body: body, auth: auth);
}
