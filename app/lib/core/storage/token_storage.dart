import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Secure token storage (Keychain / EncryptedSharedPreferences).
/// Web tokens stay in memory only, preventing persistence in localStorage.
class TokenStorage {
  TokenStorage()
      : _secure = const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
        );

  final FlutterSecureStorage _secure;
  static const _kAccess = 'kora.access';
  static const _kRefresh = 'kora.refresh';
  static const _kBiometric = 'kora.biometric_enabled';

  SharedPreferences? _prefs;
  String? _webAccess;
  String? _webRefresh;

  Future<SharedPreferences> get _sp async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    if (kIsWeb) {
      _webAccess = access;
      _webRefresh = refresh;
      return;
    }
    await _secure.write(key: _kAccess, value: access);
    await _secure.write(key: _kRefresh, value: refresh);
  }

  Future<String?> readAccess() async =>
      kIsWeb ? _webAccess : _secure.read(key: _kAccess);

  Future<String?> readRefresh() async =>
      kIsWeb ? _webRefresh : _secure.read(key: _kRefresh);

  Future<void> clear() async {
    _webAccess = null;
    _webRefresh = null;
    if (!kIsWeb) {
      await _secure.delete(key: _kAccess);
      await _secure.delete(key: _kRefresh);
    }
  }

  Future<bool> get biometricEnabled async =>
      (await _sp).getBool(_kBiometric) ?? false;

  Future<void> setBiometricEnabled(bool v) async =>
      (await _sp).setBool(_kBiometric, v);
}
