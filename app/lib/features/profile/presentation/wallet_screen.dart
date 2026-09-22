import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_animations.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/kora_colors.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/misc.dart';

// ---------------------------------------------------------------------------
// Wallet — bonus balance + transaction history (§23).
// ---------------------------------------------------------------------------

class WalletRepository {
  WalletRepository(this._ref);
  final Ref _ref;

  Future<({int balance, int earned, int spent})> summary() async {
    final res = await _ref.read(apiClientProvider)
        .get('/users/me/wallet') as Map<String, dynamic>;
    return (
      balance: (res['balanceTiyn'] as num).toInt(),
      earned: (res['earnedTiyn'] as num?)?.toInt() ?? 0,
      spent: (res['spentTiyn'] as num?)?.toInt() ?? 0,
    );
  }

  Future<List<Map<String, dynamic>>> transactions() async {
    final res = await _ref.read(apiClientProvider)
        .get('/users/me/wallet/transactions') as Map<String, dynamic>;
    return (res['items'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> referral() async =>
      await _ref.read(apiClientProvider).get('/users/me/referral')
          as Map<String, dynamic>;
}

final walletRepoProvider = Provider((ref) => WalletRepository(ref));

final walletSummaryProvider = FutureProvider(
    (ref) => ref.watch(walletRepoProvider).summary(),);

final walletTxnsProvider = FutureProvider(
    (ref) => ref.watch(walletRepoProvider).transactions(),);

class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(walletSummaryProvider);
    final txns = ref.watch(walletTxnsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(S.t('wallet.title')),
      ),
      body: ListView(
        padding: AppSpacing.screenPadding,
        children: [
          // Balance card — animated counter, brand gradient.
          summary.when(
            data: (s) => _BalanceCard(balance: s.balance,
                earned: s.earned, spent: s.spent,),
            loading: () => const KoraSkeleton(
                height: 150, radius: AppRadius.xl,),
            error: (_, __) => KoraErrorState(
                message: S.t('admin.load_error'),
                onRetry: () => ref.invalidate(walletSummaryProvider),),
          ),
          const SizedBox(height: AppSpacing.xl),
          KoraSectionHeader(title: S.t('wallet.history')),
          const SizedBox(height: AppSpacing.sm),
          txns.when(
            data: (list) => list.isEmpty
                ? KoraEmptyState(
                    icon: AppIcons.wallet,
                    title: S.t('wallet.empty'),
                    message: S.t('wallet.empty_sub'),
                  )
                : Column(
                    children: [
                      for (final t in list) ...[
                        _TxnTile(txn: t),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                    ],
                  ),
            loading: () => const Column(
              children: [
                KoraSkeleton(height: 64, radius: AppRadius.md),
                SizedBox(height: AppSpacing.sm),
                KoraSkeleton(height: 64, radius: AppRadius.md),
              ],
            ),
            error: (_, __) => KoraErrorState(
                message: S.t('admin.load_error'),
                onRetry: () => ref.invalidate(walletTxnsProvider),),
          ),
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard(
      {required this.balance, required this.earned,
       required this.spent,});

  final int balance;
  final int earned;
  final int spent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: KoraColors.primaryGradient,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: const [
          BoxShadow(
            color: KoraColors.primaryGlow,
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            S.t('wallet.balance'),
            style: AppTypography.caption.copyWith(
              color: KoraColors.lightPurple,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: balance.toDouble()),
            duration: AppAnimations.emphasis,
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => Text(
              KoraPrice.format(v.round()),
              style: AppTypography.displayLarge.copyWith(
                color: KoraColors.white,
                fontSize: 34,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              _MiniStat(
                icon: AppIcons.wallet,
                label: S.t('wallet.earned'),
                value: KoraPrice.format(earned),
              ),
              const SizedBox(width: AppSpacing.xl),
              _MiniStat(
                icon: AppIcons.cart,
                label: S.t('wallet.spent'),
                value: KoraPrice.format(spent),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(
      {required this.icon, required this.label,
       required this.value,});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: KoraColors.lightPurple, size: 16),
        const SizedBox(width: AppSpacing.xs),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: AppTypography.overline.copyWith(
                  color: KoraColors.lightPurple,
                  fontSize: 9,
                ),),
            Text(value,
                style: AppTypography.label.copyWith(
                  color: KoraColors.white,
                ),),
          ],
        ),
      ],
    );
  }
}

class _TxnTile extends StatelessWidget {
  const _TxnTile({required this.txn});

  final Map<String, dynamic> txn;

  @override
  Widget build(BuildContext context) {
    final amount = (txn['amountTiyn'] as num).toInt();
    final positive = amount >= 0;
    final at = DateTime.tryParse('${txn['at']}') ?? DateTime.now();
    return KoraCard(
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: positive
                  ? KoraColors.selected
                  : KoraColors.surfaceAlt,
              shape: BoxShape.circle,
            ),
            child: Icon(
              positive ? AppIcons.wallet : AppIcons.cart,
              color: KoraColors.primary,
              size: 18,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${txn['title']}', style: AppTypography.label,
                    maxLines: 1, overflow: TextOverflow.ellipsis,),
                Text(
                  '${at.day.toString().padLeft(2, '0')}.'
                  '${at.month.toString().padLeft(2, '0')} · '
                  '${at.hour.toString().padLeft(2, '0')}:'
                  '${at.minute.toString().padLeft(2, '0')}',
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
          Text(
            '${positive ? '+' : ''}${KoraPrice.format(amount)}',
            style: AppTypography.label.copyWith(
              color: positive ? KoraColors.primary : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Referral — invite code + stats (§40).
// ---------------------------------------------------------------------------

class ReferralScreen extends ConsumerWidget {
  const ReferralScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(S.t('referral.title')),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: ref.read(walletRepoProvider).referral(),
        builder: (context, snap) {
          if (snap.hasError) {
            return KoraErrorState(message: S.t('admin.load_error'));
          }
          if (!snap.hasData) return const KoraLoadingState();
          final r = snap.data!;
          final code = '${r['code']}';
          return ListView(
            padding: AppSpacing.screenPadding,
            children: [
              const SizedBox(height: AppSpacing.lg),
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: const BoxDecoration(
                    gradient: KoraColors.primaryGradient,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(AppIcons.gift,
                      color: KoraColors.white, size: 38,),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(S.t('referral.body'),
                  style: AppTypography.bodySecondary,
                  textAlign: TextAlign.center,),
              const SizedBox(height: AppSpacing.xl),
              KoraCard(
                child: Column(
                  children: [
                    Text(S.t('referral.your_code'),
                        style: AppTypography.caption,),
                    const SizedBox(height: AppSpacing.xs),
                    Text(code,
                        style: AppTypography.displayLarge
                            .copyWith(fontSize: 26),),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: KoraCard(
                      child: Column(
                        children: [
                          Text('${r['invited']}',
                              style: AppTypography.titleLarge,),
                          Text(S.t('referral.invited'),
                              style: AppTypography.caption,),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: KoraCard(
                      child: Column(
                        children: [
                          Text(
                              KoraPrice.format(
                                  (r['bonusTiyn'] as num).toInt(),),
                              style: AppTypography.titleLarge,),
                          Text(S.t('referral.bonus'),
                              style: AppTypography.caption,),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              KoraButton(
                label: S.t('referral.share'),
                icon: AppIcons.share,
                onPressed: () {
                  SharePlus.instance.share(ShareParams(
                    text: S.t('referral.share_text', {'code': code}),
                  ),);
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              KoraOutlinedButton(
                label: S.t('referral.copy'),
                icon: AppIcons.doc,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: code));
                  KoraSnackbar.show(context, S.t('common.copied'));
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
