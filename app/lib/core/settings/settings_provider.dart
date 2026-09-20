import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_strings.dart';

/// Persisted user preferences: theme, language, animation intensity.
/// Synced to the account server-side when the backend supports it.
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.language = AppLanguage.ru,
  });

  final ThemeMode themeMode;
  final AppLanguage language;

  AppSettings copyWith({ThemeMode? themeMode, AppLanguage? language}) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        language: language ?? this.language,
      );
}

class SettingsController extends Notifier<AppSettings> {
  static const _kTheme = 'kora.theme';
  static const _kLang = 'kora.lang';

  @override
  AppSettings build() {
    Future.microtask(_load);
    return const AppSettings();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final themeIdx = p.getInt(_kTheme);
    final langName = p.getString(_kLang);
    state = AppSettings(
      themeMode: themeIdx == null
          ? ThemeMode.system
          : ThemeMode.values[themeIdx.clamp(0, 2)],
      language: AppLanguage.values.firstWhere(
        (l) => l.name == langName,
        orElse: () => AppLanguage.ru,
      ),
    );
    S.lang = state.language;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kTheme, mode.index);
  }

  Future<void> setLanguage(AppLanguage lang) async {
    state = state.copyWith(language: lang);
    S.lang = lang;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLang, lang.name);
  }
}

final settingsProvider =
    NotifierProvider<SettingsController, AppSettings>(
        SettingsController.new,);

/// Convenience: `ref.watch(languageProvider)` forces rebuild on change.
final languageProvider = Provider<AppLanguage>(
  (ref) => ref.watch(settingsProvider).language,
);

/// `ref.tr('key')` — localized string bound to the active language.
extension Tr on WidgetRef {
  String tr(String key, [Map<String, String>? params]) {
    watch(languageProvider);
    return S.t(key, params);
  }
}
