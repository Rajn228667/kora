import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kora/core/l10n/app_strings.dart';
import 'package:kora/core/theme/app_theme.dart';
import 'package:kora/core/theme/kora_colors.dart';

void main() {
  group('Localization', () {
    test('every RU key exists in KK and EN', () {
      final ruKeys = S.keys(AppLanguage.ru);
      for (final lang in [AppLanguage.kk, AppLanguage.en]) {
        final missing = ruKeys.difference(S.keys(lang));
        expect(missing, isEmpty,
            reason: 'Missing ${lang.name} translations: $missing',);
      }
    });

    test('params interpolate', () {
      S.lang = AppLanguage.ru;
      expect(S.t('otp.sent_to', {'phone': '+7 700'}), 'Отправлен на +7 700');
      S.lang = AppLanguage.en;
      expect(S.t('otp.sent_to', {'phone': '+7 700'}), 'Sent to +7 700');
    });

    test('unknown key falls back to RU then to key itself', () {
      S.lang = AppLanguage.en;
      // 'map.point_label' exists in all langs
      expect(S.t('map.point_label'), 'Delivery point');
      expect(S.t('nonexistent.key'), 'nonexistent.key');
      S.lang = AppLanguage.ru;
    });

    test('KK and EN tables match RU key count', () {
      expect(S.keys(AppLanguage.kk).length, S.keys(AppLanguage.ru).length);
      expect(S.keys(AppLanguage.en).length, S.keys(AppLanguage.ru).length);
    });
  });

  group('Dark theme', () {
    test('semantic getters switch with KoraTheme.dark', () {
      KoraTheme.dark = false;
      expect(KoraColors.surface, KoraColors.white);
      KoraTheme.dark = true;
      expect(KoraColors.surface, KoraColors.darkCard);
      expect(KoraColors.background, KoraColors.darkBackground);
      KoraTheme.dark = false;
    });

    test('dark ThemeData uses KORA purple surfaces, not black/blue', () {
      final dark = AppTheme.dark;
      expect(dark.brightness, Brightness.dark);
      expect(
          dark.scaffoldBackgroundColor, KoraColors.darkBackground,);
      expect(dark.colorScheme.primary, KoraColors.primary);
      // Card surface must be purple-tinted, not pure black.
      expect(dark.cardTheme.color, KoraColors.darkCard);
    });

    test('dark palette stays purple-hued', () {
      // HSV hue of dark surfaces must sit in the purple band 250–290°.
      for (final c in [
        KoraColors.darkBackground,
        KoraColors.darkSurface,
        KoraColors.darkCard,
      ]) {
        final hue = HSVColor.fromColor(c).hue;
        expect(hue, inInclusiveRange(240, 300), reason: '$c hue=$hue');
      }
    });
  });
}

