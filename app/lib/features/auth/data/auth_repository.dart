import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../../../core/storage/token_storage.dart';

class OtpRequest {
  const OtpRequest({
    required this.requestId,
    required this.ttlSeconds,
    required this.phone,
    this.channel = 'sms',
    this.devOtp,
  });

  final String requestId;
  final int ttlSeconds;
  final String phone;

  /// Delivery channel chosen by the user: `sms` or `whatsapp`.
  final String channel;
  final String? devOtp;
}

class AuthResult {
  const AuthResult({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
    required this.isNewUser,
  });

  final User user;
  final String accessToken;
  final String refreshToken;
  final bool isNewUser;
}

class AuthRepository {
  AuthRepository({required ApiClient api, required TokenStorage tokens})
      : _api = api,
        _tokens = tokens;

  final ApiClient _api;
  final TokenStorage _tokens;

  Future<OtpRequest> requestOtp(String phone,
      {String channel = 'sms',}) async {
    final res = await _api.post('/auth/request-otp',
        body: {'phone': phone, 'channel': channel},
        auth: false,) as Map<String, dynamic>;
    return OtpRequest(
      requestId: res['requestId'] as String,
      ttlSeconds: (res['ttlSeconds'] as num).toInt(),
      phone: phone,
      channel: channel,
      devOtp: res['devOtp'] as String?,
    );
  }

  Future<AuthResult> verifyOtp(OtpRequest req, String code) async {
    final res = await _api.post('/auth/verify-otp', body: {
      'requestId': req.requestId,
      'code': code,
      'phone': req.phone,
    }, auth: false,) as Map<String, dynamic>;
    final result = AuthResult(
      user: User.fromJson(res['user'] as Map<String, dynamic>),
      accessToken: res['accessToken'] as String,
      refreshToken: res['refreshToken'] as String,
      isNewUser: res['isNewUser'] as bool? ?? false,
    );
    await _tokens.saveTokens(
        access: result.accessToken, refresh: result.refreshToken,);
    return result;
  }

  /// Staff console login (manager/admin). Password is verified
  /// server-side; the client only sends it over HTTPS.
  Future<AuthResult> loginWithPassword(
      String email, String password,) async {
    final res = await _api.post('/auth/login', body: {
      'email': email,
      'password': password,
    }, auth: false,) as Map<String, dynamic>;
    final result = AuthResult(
      user: User.fromJson(res['user'] as Map<String, dynamic>),
      accessToken: res['accessToken'] as String,
      refreshToken: res['refreshToken'] as String,
      isNewUser: res['isNewUser'] as bool? ?? false,
    );
    await _tokens.saveTokens(
        access: result.accessToken, refresh: result.refreshToken,);
    return result;
  }

  Future<User?> restoreSession() async {
    final access = await _tokens.readAccess();
    if (access == null) return null;
    try {
      final res = await _api.get('/users/me') as Map<String, dynamic>;
      return User.fromJson(res);
    } catch (_) {
      return null;
    }
  }

  Future<User> updateProfile({
    String? name,
    String? lastName,
    String? nickname,
    String? profileBg,
    String? email,
    String? avatarUrl,
    bool? acceptTerms,
    bool? acceptPrivacy,
  }) async {
    final res = await _api.patch('/users/me', body: {
      if (name != null) 'name': name,
      if (lastName != null) 'lastName': lastName,
      if (nickname != null) 'nickname': nickname.isEmpty ? null : nickname,
      if (profileBg != null) 'profileBg': profileBg,
      if (email != null) 'email': email.isEmpty ? null : email,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      if (acceptTerms == true) 'acceptTerms': true,
      if (acceptPrivacy == true) 'acceptPrivacy': true,
    },) as Map<String, dynamic>;
    return User.fromJson(res);
  }

  /// Avatar upload — ≤2MB enforced client- and server-side.
  Future<String> uploadAvatar(Uint8List bytes, String contentType) async {
    final res = await _api.post('/media', body: {
      'dataBase64': base64Encode(bytes),
      'kind': 'avatar',
      'contentType': contentType,
    },) as Map<String, dynamic>;
    return res['url'] as String;
  }

  /// Set (first time) or change the account password.
  Future<void> setPassword({String? currentPassword,
      required String newPassword,}) async {
    await _api.post('/users/me/password', body: {
      if (currentPassword != null) 'currentPassword': currentPassword,
      'newPassword': newPassword,
    },);
  }

  Future<void> logout() async {
    try {
      await _api.post('/auth/logout');
    } finally {
      await _tokens.clear();
    }
  }

  /// Account deletion — when the account has a password the server
  /// requires it for re-authentication. Tokens clear only on success,
  /// so a failed confirmation doesn't kill the local session.
  Future<void> deleteAccount({String? password}) async {
    await _api.delete('/users/me', body: {
      if (password != null) 'password': password,
    },);
    await _tokens.clear();
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    api: ref.watch(apiClientProvider),
    tokens: ref.watch(tokenStorageProvider),
  ),
);
