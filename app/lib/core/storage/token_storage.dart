import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Secure token storage (Keychain / EncryptedSharedPreferences),
/// with SharedPreferences fallback for platforms without keystore.
class TokenStorage {
  TokenStorage() : _secure = const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
        );

  final FlutterSecureStorage _secure;
  static const _kAccess = 'kora.access';
  static const _kRefresh = 'kora.refresh';
  static const _kBiometric = 'kora.biometric_enabled';

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _sp async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    try {
      await _secure.write(key: _kAccess, value: access);
      await _secure.write(key: _kRefresh, value: refresh);
    } catch (_) {
      final p = await _sp;
      await p.setString(_kAccess, access);
      await p.setString(_kRefresh, refresh);
    }
  }

  Future<String?> readAccess() async {
    try {
      return await _secure.read(key: _kAccess);
    } catch (_) {
      return (await _sp).getString(_kAccess);
    }
  }

  Future<String?> readRefresh() async {
    try {
      return await _secure.read(key: _kRefresh);
    } catch (_) {
      return (await _sp).getString(_kRefresh);
    }
  }

  Future<void> clear() async {
    try {
      await _secure.delete(key: _kAccess);
      await _secure.delete(key: _kRefresh);
    } catch (_) {/* fall through */}
    final p = await _sp;
    await p.remove(_kAccess);
    await p.remove(_kRefresh);
  }

  Future<bool> get biometricEnabled async =>
      (await _sp).getBool(_kBiometric) ?? false;

  Future<void> setBiometricEnabled(bool v) async =>
      (await _sp).setBool(_kBiometric, v);
}
