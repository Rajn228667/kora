import '../l10n/app_strings.dart';

/// Normalized API error matching the backend contract:
/// `{ "error": { "code": "SNAKE_CODE", "message": "...", "details": any } }`
class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.details,
  });

  final String code;
  final String message;
  final int? statusCode;
  final Object? details;

  factory ApiException.fromBody(int? status, Object? body) {
    if (body is Map<String, dynamic>) {
      final err = body['error'];
      if (err is Map<String, dynamic>) {
        return ApiException(
          code: (err['code'] as String?) ?? 'UNKNOWN',
          message: (err['message'] as String?) ?? S.t('error.server'),
          statusCode: status,
          details: err['details'],
        );
      }
    }
    return ApiException(
      code: 'HTTP_$status',
      message: '${S.t('error.server')} ($status)',
      statusCode: status,
    );
  }

  factory ApiException.network() => ApiException(
        code: 'NO_INTERNET',
        message: S.t('common.no_internet'),
      );

  factory ApiException.timeout() => ApiException(
        code: 'TIMEOUT',
        message: S.t('error.timeout'),
      );

  bool get isUnauthorized => statusCode == 401 || code == 'UNAUTHORIZED';

  @override
  String toString() => 'ApiException($code, $statusCode): $message';
}
