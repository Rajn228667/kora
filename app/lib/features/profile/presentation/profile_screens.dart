import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/kora_colors.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/fields.dart';
import '../../../core/widgets/misc.dart';
import '../../../core/providers.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../checkout/data/checkout_repository.dart';
import '../../checkout/presentation/checkout_screen.dart'
    show MapPickResult;

// ---------------------------------------------------------------------------
// Profile hub.
// ---------------------------------------------------------------------------

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final user = switch (auth) {
      Authenticated(user: final u) => u,
      _ => null,
    };
    if (user == null) return const Scaffold();

    return Scaffold(
      appBar: AppBar(title: Text(S.t('profile.title'))),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          KoraCard(
            child: Row(
              children: [
                KoraAvatar(
                  imageUrl: user.avatarUrl,
                  initials: user.name.isEmpty
                      ? '?'
                      : user.name.substring(0, 1).toUpperCase(),
                  radius: 28,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name.isEmpty
                            ? S.t('profile.no_name')
                            : user.name,
                        style: AppTypography.title,
                      ),
                      Text(user.phone, style: AppTypography.caption),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: S.t('profile.edit_tooltip'),
                  icon: const Icon(AppIcons.edit,
                      color: KoraColors.primary, size: 20,),
                  onPressed: () => _editName(context, ref, user),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _section(S.t('profile.account'), [
            _item(context, AppIcons.locationOut, S.t('profile.addresses'),
                () => context.push('/addresses'),),
            _item(context, AppIcons.heartOut, S.t('profile.favorites'),
                () => context.push('/favorites'),),
            _item(context, AppIcons.history, S.t('profile.orders'),
                () => context.go('/orders'),),
            _item(context, AppIcons.notificationOut,
                S.t('profile.notifications'),
                () => context.push('/notifications'),),
            _item(context, AppIcons.promo, S.t('profile.promo'),
                () => context.push('/promo'),),
            _item(context, AppIcons.wallet, S.t('wallet.title'),
                () => context.push('/wallet'),),
            _item(context, AppIcons.gift, S.t('referral.title'),
                () => context.push('/referral'),),
          ]),
          _section(S.t('settings.title'), [
            _item(context, AppIcons.settings, S.t('profile.appearance'),
                () => context.push('/settings/appearance'),),
          ]),
          _section(S.t('profile.security'), [
            _item(context, AppIcons.biometric, S.t('profile.biometric'),
                () => context.push('/settings/security'),),
            _item(context, AppIcons.phone, S.t('profile.sessions'),
                () => context.push('/settings/sessions'),),
          ]),
          _section(S.t('profile.support_section'), [
            _item(context, AppIcons.help, S.t('profile.support'),
                () => context.push('/support'),),
            _item(context, AppIcons.doc, S.t('profile.privacy'),
                () => context.push('/legal/privacy'),),
            _item(context, AppIcons.doc, S.t('profile.terms'),
                () => context.push('/legal/terms'),),
          ]),
          if (user.role != UserRole.customer)
            _section(S.t('profile.work'), [
              if (user.role == UserRole.manager)
                _item(context, AppIcons.dashboard, S.t('profile.manager'),
                    () => context.push('/manager'),),
              if (user.role == UserRole.courier)
                _item(context, AppIcons.courier, S.t('profile.courier'),
                    () => context.push('/courier'),),
              if (user.role == UserRole.admin)
                _item(context, AppIcons.admin, S.t('profile.admin'),
                    () => context.push('/admin'),),
            ]),
          const SizedBox(height: AppSpacing.lg),
          KoraOutlinedButton(
            label: S.t('profile.logout'),
            icon: AppIcons.logout,
            onPressed: () async {
              final ok = await KoraDialog.confirm(
                context,
                title: S.t('profile.logout_title'),
                message: S.t('profile.logout_msg'),
                confirmLabel: S.t('profile.logout'),
              );
              if (ok) {
                await ref.read(authControllerProvider.notifier).logout();
                if (context.mounted) context.go('/welcome');
              }
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          KoraGhostButton(
            label: S.t('profile.delete'),
            icon: AppIcons.delete,
            color: KoraColors.error,
            onPressed: () => _deleteAccount(context, ref),
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            bottom: AppSpacing.sm,
            top: AppSpacing.md,
          ),
          child: Text(title, style: AppTypography.overline),
        ),
        KoraCard(
          padding: EdgeInsets.zero,
          child: Column(children: items),
        ),
      ],
    );
  }

  Widget _item(
      BuildContext context, IconData icon, String label, VoidCallback onTap,) {
    return ListTile(
      leading: Icon(icon, color: KoraColors.primary, size: 22),
      title: Text(label, style: AppTypography.label),
      trailing: Icon(AppIcons.chevronR,
          color: KoraColors.placeholderC, size: 20,),
      onTap: onTap,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.card),
    );
  }

  Future<void> _editName(BuildContext context, WidgetRef ref, User user) async {
    final controller = TextEditingController(text: user.name);
    final saved = await KoraBottomSheet.show<String>(
      context,
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(S.t('profile.edit_name'), style: AppTypography.title),
            const SizedBox(height: AppSpacing.md),
            KoraTextField(
                controller: controller, hint: S.t('profile_setup.hint'),),
            const SizedBox(height: AppSpacing.md),
            KoraButton(
              label: S.t('common.save'),
              onPressed: () =>
                  Navigator.pop(context, controller.text.trim()),
            ),
          ],
        ),
      ),
    );
    if (saved != null && saved.isNotEmpty) {
      final repo = ref.read(authRepositoryProvider);
      final updated = await repo.updateProfile(name: saved);
      ref.read(authControllerProvider.notifier).setUser(updated);
    }
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final confirmed = await KoraDialog.confirm(
      context,
      title: S.t('profile.delete_title'),
      message: S.t('profile.delete_msg'),
      destructive: true,
      confirmLabel: S.t('profile.delete_confirm'),
    );
    if (!confirmed) return;
    await ref.read(authControllerProvider.notifier).deleteAccount();
    if (context.mounted) context.go('/welcome');
  }
}

// ---------------------------------------------------------------------------
// Addresses CRUD.
// ---------------------------------------------------------------------------

class AddressesScreen extends ConsumerWidget {
  const AddressesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addresses = ref.watch(addressesProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(S.t('addresses.title')),
        actions: [
          IconButton(
            tooltip: S.t('addresses.add'),
            icon: const Icon(AppIcons.add),
            onPressed: () async {
              final r =
                  await context.push<MapPickResult>('/map-picker');
              if (r != null && context.mounted) {
                _newAddressSheet(context, ref, r);
              }
            },
          ),
        ],
      ),
      body: addresses.when(
        loading: () => const KoraLoadingState(),
        error: (_, __) => KoraErrorState(
          message: S.t('addresses.load_error'),
          onRetry: () => ref.invalidate(addressesProvider),
        ),
        data: (list) => list.isEmpty
            ? KoraEmptyState(
                icon: AppIcons.locationOut,
                title: S.t('addresses.empty'),
                message: S.t('addresses.empty_sub'),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.lg),
                itemCount: list.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (_, i) {
                  final a = list[i];
                  return KoraCard(
                    child: Row(
                      children: [
                        const Icon(AppIcons.location,
                            color: KoraColors.primary,),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(a.label,
                                      style: AppTypography.label,),
                                  if (a.isDefault) ...[
                                    const SizedBox(width: AppSpacing.xs),
                                    KoraBadge(
                                        label: S.t('addresses.default'),),
                                  ],
                                ],
                              ),
                              Text(a.address,
                                  style: AppTypography.caption,),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: S.t('common.delete'),
                          icon: Icon(AppIcons.delete,
                              color: KoraColors.placeholderC, size: 20,),
                          onPressed: () => ref
                              .read(addressesProvider.notifier)
                              .remove(a.id),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  void _newAddressSheet(
      BuildContext context,
      WidgetRef ref,
      MapPickResult pick,
    ) {
    final label = TextEditingController();
    final comment = TextEditingController();
    KoraBottomSheet.show<void>(
      context,
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(S.t('addresses.new'), style: AppTypography.title),
            const SizedBox(height: AppSpacing.sm),
            Text(pick.address ?? S.t('map.point_generic'),
                style: AppTypography.bodySecondary,),
            const SizedBox(height: AppSpacing.md),
            KoraTextField(
                controller: label, hint: S.t('addresses.name_hint'),),
            const SizedBox(height: AppSpacing.sm),
            KoraTextField(
                controller: comment, hint: S.t('addresses.comment_hint'),),
            const SizedBox(height: AppSpacing.md),
            KoraButton(
              label: S.t('common.save'),
              onPressed: () async {
                await ref.read(addressesProvider.notifier).add(
                      Address(
                        id: '',
                        label: label.text.trim().isEmpty
                            ? S.t('addresses.fallback')
                            : label.text.trim(),
                        address: pick.address ?? '',
                        point: pick.point,
                        comment: comment.text.trim().isEmpty
                            ? null
                            : comment.text.trim(),
                      ),
                    );
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Favorites.
// ---------------------------------------------------------------------------

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          leading: const BackButton(),
          title: Text(S.t('favorites.title')),
          bottom: TabBar(
            labelColor: KoraColors.primary,
            unselectedLabelColor: KoraColors.textSecondaryC,
            indicatorColor: KoraColors.primary,
            tabs: [
              Tab(text: S.t('favorites.products')),
              Tab(text: S.t('favorites.stores')),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_FavoriteProductsTab(), _FavoriteStoresTab()],
        ),
      ),
    );
  }
}

class _FavoriteProductsTab extends ConsumerWidget {
  const _FavoriteProductsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favIds = ref.watch(favoriteProductsProvider);
    return favIds.when(
      loading: () => const KoraLoadingState(),
      error: (_, __) =>
          KoraErrorState(message: S.t('favorites.load_error')),
      data: (ids) => FutureBuilder<List<Product>>(
        future: ref.read(catalogRepositoryProvider).favoriteProducts(),
        builder: (context, snap) {
          if (!snap.hasData) return const KoraLoadingState();
          final list = snap.data!.where((p) => ids.contains(p.id)).toList();
          if (list.isEmpty) {
            return KoraEmptyState(
              icon: AppIcons.heartOut,
              title: S.t('favorites.products_empty'),
              message: S.t('favorites.products_empty_sub'),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(AppSpacing.lg),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: AppSpacing.md,
              crossAxisSpacing: AppSpacing.md,
              childAspectRatio: 0.72,
            ),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final p = list[i];
              return KoraProductCard(
                name: p.name,
                priceTiyn: p.priceTiyn,
                oldPriceTiyn: p.oldPriceTiyn,
                imageUrl: p.imageUrl,
                blurHash: p.blurHash,
                available: p.available,
                isFavorite: true,
                onFavorite: () => ref
                    .read(favoriteProductsProvider.notifier)
                    .toggle(p.id),
                onTap: () => context
                    .push('/store/${p.storeId}/product/${p.id}'),
              );
            },
          );
        },
      ),
    );
  }
}

class _FavoriteStoresTab extends ConsumerWidget {
  const _FavoriteStoresTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider);
    final stores = ref.watch(storesProvider).value ?? const [];
    return favorites.when(
      loading: () => const KoraLoadingState(),
      error: (_, __) =>
          KoraErrorState(message: S.t('favorites.load_error')),
      data: (ids) {
        final favs = stores.where((s) => ids.contains(s.id)).toList();
        if (favs.isEmpty) {
          return KoraEmptyState(
            icon: AppIcons.heartOut,
            title: S.t('favorites.empty'),
            message: S.t('favorites.empty_sub'),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: favs.length,
          separatorBuilder: (_, __) =>
              const SizedBox(height: AppSpacing.lg),
          itemBuilder: (_, i) => KoraStoreHeroCard(
            name: favs[i].name,
            imageUrl: favs[i].bannerUrl ?? favs[i].logoUrl,
            blurHash: favs[i].blurHash,
            category: favs[i].description,
            rating: favs[i].rating,
            etaMinutes: favs[i].etaMinutes,
            deliveryFeeTiyn: favs[i].deliveryFeeTiyn,
            onTap: () => context.push('/store/${favs[i].id}'),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Security settings — biometric toggle.
// ---------------------------------------------------------------------------

class SecurityScreen extends ConsumerStatefulWidget {
  const SecurityScreen({super.key});

  @override
  ConsumerState<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends ConsumerState<SecurityScreen> {
  bool _enabled = false;
  bool _available = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final storage = ref.read(tokenStorageProvider);
    final enabled = await storage.biometricEnabled;
    var can = false;
    try {
      can = await LocalAuthentication().canCheckBiometrics;
    } catch (_) {/* no biometrics */}
    if (mounted) {
      setState(() {
        _enabled = enabled && can;
        _available = can;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(S.t('security.title')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          KoraCard(
            child: SwitchListTile(
              value: _enabled,
              onChanged: !_available
                  ? null
                  : (v) async {
                      if (v) {
                        try {
                          final ok = await LocalAuthentication()
                              .authenticate(
                            localizedReason:
                                S.t('security.biometric_reason'),
                          );
                          if (!ok) return;
                        } catch (_) {
                          return;
                        }
                      }
                      await ref
                          .read(tokenStorageProvider)
                          .setBiometricEnabled(v);
                      setState(() => _enabled = v);
                    },
              title:
                  Text(S.t('security.biometric'), style: AppTypography.label),
              subtitle: Text(
                _available
                    ? S.t('security.biometric_sub')
                    : S.t('security.biometric_off'),
                style: AppTypography.caption,
              ),
              secondary: const Icon(AppIcons.biometric,
                  color: KoraColors.primary,),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            S.t('security.biometric_note'),
            style: AppTypography.caption,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sessions.
// ---------------------------------------------------------------------------

class SessionsScreen extends ConsumerStatefulWidget {
  const SessionsScreen({super.key});

  @override
  ConsumerState<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends ConsumerState<SessionsScreen> {
  late Future<List<SessionInfo>> _future = _load();

  Future<List<SessionInfo>> _load() async {
    final res = await ref
        .read(apiClientProvider)
        .get('/users/me/sessions') as Map<String, dynamic>;
    return (res['items'] as List)
        .map((s) => SessionInfo.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  Future<void> _logoutOthers() async {
    await ref.read(apiClientProvider).post('/auth/logout-all');
    if (!mounted) return;
    setState(() => _future = _load());
    KoraSnackbar.show(context, S.t('sessions.logged_out'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(S.t('sessions.title')),
      ),
      body: FutureBuilder<List<SessionInfo>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) return const KoraLoadingState();
          final others =
              snap.data!.where((s) => !s.current).toList();
          return Column(
            children: [
              Expanded(
                child: ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: snap.data!.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: AppSpacing.sm),
            itemBuilder: (_, i) {
              final s = snap.data![i];
              return KoraCard(
                child: Row(
                  children: [
                    const Icon(AppIcons.phone,
                        color: KoraColors.primary,),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.device, style: AppTypography.label),
                          Text(
                            s.current
                                ? S.t('sessions.current')
                                : S.t('sessions.logged_in'),
                            style: AppTypography.caption,
                          ),
                        ],
                      ),
                    ),
                    if (s.current) KoraBadge(label: S.t('sessions.now')),
                  ],
                ),
              );
            },
                ),
              ),
              if (others.isNotEmpty)
                SafeArea(
                  child: Padding(
                    padding: AppSpacing.cardPadding,
                    child: KoraOutlinedButton(
                      label: S.t('sessions.logout_others'),
                      icon: AppIcons.logout,
                      onPressed: _logoutOthers,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
