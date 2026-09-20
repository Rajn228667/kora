import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/cart/data/cart_repository.dart';
import '../l10n/app_strings.dart';
import '../theme/app_icons.dart';
import '../theme/kora_colors.dart';
import '../widgets/misc.dart';

/// Customer shell — bottom navigation: Home / Search / Orders / Profile
/// + cart FAB with live badge.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  static const _tabs = ['/home', '/search', '/orders', '/profile'];

  int _indexOf(String location) {
    for (var i = 0; i < _tabs.length; i++) {
      if (location.startsWith(_tabs[i])) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.toString();
    final index = _indexOf(location);
    final cartCount = ref.watch(cartCountProvider);

    return Scaffold(
      body: child,
      floatingActionButton: FloatingActionButton(
        heroTag: 'cart-fab',
        backgroundColor: KoraColors.primary,
        onPressed: () => context.push('/cart'),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(AppIcons.cart, color: KoraColors.white),
            Positioned(
              right: -8,
              top: -8,
              child: KoraCountBadge(count: cartCount),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,
        onTap: (i) => context.go(_tabs[i]),
        items: [
          BottomNavigationBarItem(
              icon: const Icon(AppIcons.home), label: S.t('nav.home'),),
          BottomNavigationBarItem(
              icon: const Icon(AppIcons.search), label: S.t('nav.search'),),
          BottomNavigationBarItem(
              icon: const Icon(AppIcons.orders), label: S.t('nav.orders'),),
          BottomNavigationBarItem(
              icon: const Icon(AppIcons.profile), label: S.t('nav.profile'),),
        ],
      ),
    );
  }
}
