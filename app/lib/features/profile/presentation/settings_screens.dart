import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/kora_colors.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/fields.dart';
import '../../../core/widgets/misc.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../checkout/data/checkout_repository.dart';

/// Settings → Appearance: language (ru/kk/en) and animation preferences.
/// KORA ships a single light lilac identity — there is no theme switch.
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final ctrl = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(S.t('settings.appearance')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text(S.t('settings.language'), style: AppTypography.overline),
          const SizedBox(height: AppSpacing.sm),
          KoraCard(
            padding: EdgeInsets.zero,
            child: RadioGroup<AppLanguage>(
              groupValue: settings.language,
              onChanged: (v) =>
                  v != null ? ctrl.setLanguage(v) : null,
              child: Column(
                children: [
                  for (final (lang, label) in [
                    (AppLanguage.ru, 'Русский'),
                    (AppLanguage.kk, 'Қазақша'),
                    (AppLanguage.en, 'English'),
                  ])
                    RadioListTile<AppLanguage>(
                      value: lang,
                      title: Text(label, style: AppTypography.label),
                      activeColor: KoraColors.primary,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(S.t('settings.animations'), style: AppTypography.overline),
          const SizedBox(height: AppSpacing.sm),
          KoraCard(
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              value: !settings.reduceMotion,
              onChanged: (v) => ctrl.setReduceMotion(!v),
              secondary: const Icon(AppIcons.animations,
                  color: KoraColors.primary, size: 20,),
              title: Text(S.t('settings.anim_full'),
                  style: AppTypography.label,),
              subtitle: Text(S.t('settings.anim_sub'),
                  style: AppTypography.caption,),
              activeThumbColor: KoraColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Profile → Ввести промокод. Validation is server-side
/// (ApiClient → /promo-codes/validate); UI only displays the result.
class PromoScreen extends ConsumerStatefulWidget {
  const PromoScreen({super.key});

  @override
  ConsumerState<PromoScreen> createState() => _PromoScreenState();
}

class _PromoScreenState extends ConsumerState<PromoScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  ({bool valid, int discountTiyn, String message})? _result;
  String? _error;

  Future<void> _apply() async {
    final code = _controller.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final res = await ref
          .read(catalogRepositoryProvider)
          .validatePromo(code, '');
      if (res.valid) {
        setState(() => _result = res);
        ref.read(appliedPromoProvider.notifier).state = (
          code: code.toUpperCase(),
          discountTiyn: res.discountTiyn,
        );
        if (mounted) {
          KoraSnackbar.show(context, S.t('promo.applied'));
        }
      } else {
        setState(() =>
            _error = res.message.isEmpty
                ? S.t('error.promo_not_found')
                : res.message,);
      }
    } catch (_) {
      setState(() => _error = S.t('error.promo_not_found'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(S.t('promo.title')),
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KoraTextField(
              controller: _controller,
              hint: S.t('promo.hint'),
              prefixIcon: AppIcons.promo,
              autofocus: true,
              errorText: _error,
              onSubmitted: (_) => _apply(),
            ),
            const SizedBox(height: AppSpacing.md),
            KoraButton(
              label: S.t('promo.apply'),
              loading: _loading,
              onPressed: _apply,
            ),
            if (_result != null && _result!.valid) ...[
              const SizedBox(height: AppSpacing.lg),
              KoraCard(
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: KoraColors.successSurfaceC,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(AppIcons.check,
                          color: KoraColors.success,),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_controller.text.trim().toUpperCase(),
                              style: AppTypography.label,),
                          Text(
                            S.t('promo.discount', {
                              'amount':
                                  KoraPrice.format(_result!.discountTiyn),
                            }),
                            style: AppTypography.caption,
                          ),
                          Text(
                            S.t('promo.min_order', {
                              'amount': KoraPrice.format(200000),
                            }),
                            style: AppTypography.caption,
                          ),
                        ],
                      ),
                    ),
                    const KoraBadge(label: 'OK', filled: true),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
