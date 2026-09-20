import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/admin/presentation/admin_screens.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/auth_providers.dart';
import '../../features/auth/presentation/auth_screens.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/calls/presentation/call_screen.dart';
import '../../features/cart/presentation/cart_screen.dart';
import '../../features/catalog/presentation/catalog_screens.dart';
import '../../features/chat/presentation/chat_screen.dart';
import '../../features/checkout/presentation/checkout_screen.dart';
import '../../features/courier/presentation/courier_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/manager/presentation/manager_screens.dart';
import '../../features/manager/presentation/manager_tools.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/orders/presentation/orders_screens.dart';
import '../../features/profile/presentation/legal_screens.dart';
import '../../features/profile/presentation/profile_screens.dart';
import '../../features/profile/presentation/settings_screens.dart';
import '../../features/profile/presentation/wallet_screen.dart';
import '../../features/support/presentation/support_screens.dart';
import '../models/models.dart';
import '../theme/app_animations.dart';
import 'app_shell.dart';

CustomTransitionPage<void> _page(Widget child, GoRouterState state) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionDuration: AppAnimations.normal,
    transitionsBuilder: KoraPageTransition.page,
  );
}

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authControllerProvider);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: _AuthRefresh(ref),
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final onAuth = loc.startsWith('/auth') ||
          loc == '/' ||
          loc == '/welcome';

      if (auth is AuthLoading) {
        return loc == '/' ? null : '/';
      }
      if (auth is Unauthenticated) {
        return onAuth ? null : '/welcome';
      }
      if (auth is Authenticated) {
        if (auth.needsProfile && loc != '/auth/profile') {
          return '/auth/profile';
        }
        if (!auth.needsProfile && onAuth) return '/home';
        // Role gates — server-side RBAC is the real enforcement;
        // this only shapes navigation.
        final role = auth.user.role;
        if (loc.startsWith('/manager') && role != UserRole.manager && role != UserRole.admin) {
          return '/home';
        }
        if (loc.startsWith('/courier') && role != UserRole.courier && role != UserRole.admin) {
          return '/home';
        }
        if (loc.startsWith('/admin') && role != UserRole.admin) {
          return '/home';
        }
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/welcome', builder: (_, __) => const WelcomeScreen()),
      GoRoute(path: '/auth/phone', builder: (_, __) => const PhoneScreen()),
      GoRoute(
        path: '/auth/otp',
        builder: (_, state) =>
            OtpScreen(request: state.extra as OtpRequest),
      ),
      GoRoute(
        path: '/auth/profile',
        builder: (_, __) => const ProfileSetupScreen(),
      ),

      ShellRoute(
        builder: (_, __, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (_, s) => _page(const HomeScreen(), s),
          ),
          GoRoute(
            path: '/search',
            pageBuilder: (_, s) => _page(const SearchScreen(), s),
          ),
          GoRoute(
            path: '/orders',
            pageBuilder: (_, s) => _page(const OrdersScreen(), s),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (_, s) => _page(const ProfileScreen(), s),
          ),
        ],
      ),

      GoRoute(
        path: '/store/:id',
        builder: (_, s) => StoreScreen(storeId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/store/:id/product/:pid',
        builder: (_, s) => ProductScreen(
          storeId: s.pathParameters['id']!,
          productId: s.pathParameters['pid']!,
        ),
      ),
      GoRoute(
        path: '/category/:id',
        builder: (_, s) => CategoryScreen(
          categoryId: s.pathParameters['id']!,
          name: s.uri.queryParameters['name'],
        ),
      ),
      GoRoute(path: '/cart', builder: (_, __) => const CartScreen()),
      GoRoute(
        path: '/checkout',
        builder: (_, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return CheckoutScreen(
            promoCode: extra?['promoCode'] as String?,
            discountTiyn: (extra?['discount'] as num?)?.toInt() ?? 0,
          );
        },
      ),
      GoRoute(
        path: '/map-picker',
        builder: (_, __) => const MapPickerScreen(),
      ),
      GoRoute(
        path: '/order-success',
        builder: (_, s) =>
            OrderSuccessScreen(order: s.extra as Order),
      ),
      GoRoute(
        path: '/orders/:id',
        builder: (_, s) =>
            OrderDetailScreen(orderId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/chat/:orderId',
        builder: (_, s) =>
            ChatScreen(orderId: s.pathParameters['orderId']!),
      ),
      GoRoute(
        path: '/call/:orderId',
        builder: (_, s) => CallScreen(
          peerName: s.uri.queryParameters['to'] == 'courier'
              ? 'Курьер'
              : 'Магазин',
        ),
      ),
      GoRoute(
        path: '/addresses',
        builder: (_, __) => const AddressesScreen(),
      ),
      GoRoute(
        path: '/favorites',
        builder: (_, __) => const FavoritesScreen(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (_, __) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/support',
        builder: (_, __) => const SupportScreen(),
      ),
      GoRoute(
        path: '/settings/security',
        builder: (_, __) => const SecurityScreen(),
      ),
      GoRoute(
        path: '/settings/sessions',
        builder: (_, __) => const SessionsScreen(),
      ),
      GoRoute(
        path: '/settings/appearance',
        builder: (_, __) => const AppearanceScreen(),
      ),
      GoRoute(
        path: '/promo',
        builder: (_, __) => const PromoScreen(),
      ),
      GoRoute(
        path: '/wallet',
        builder: (_, __) => const WalletScreen(),
      ),
      GoRoute(
        path: '/referral',
        builder: (_, __) => const ReferralScreen(),
      ),
      GoRoute(
        path: '/legal/:kind',
        builder: (_, s) => LegalScreen(kind: s.pathParameters['kind']!),
      ),
      GoRoute(
        path: '/manager',
        builder: (_, __) => const ManagerScreen(),
      ),
      GoRoute(
        path: '/manager/schedule',
        builder: (_, __) => const ScheduleScreen(),
      ),
      GoRoute(
        path: '/manager/image-editor',
        builder: (_, __) => const ProductImageEditor(),
      ),
      GoRoute(
        path: '/manager/card-generator',
        builder: (_, __) => const CardGeneratorScreen(),
      ),
      GoRoute(
        path: '/manager/promo-builder',
        builder: (_, __) => const PromotionBuilderScreen(),
      ),
      GoRoute(
        path: '/courier',
        builder: (_, __) => const CourierScreen(),
      ),
      GoRoute(path: '/admin', builder: (_, __) => const AdminScreen()),
    ],
  );
});

/// Re-run redirect logic whenever auth state changes.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Ref ref) {
    ref.listen(authControllerProvider, (_, __) => notifyListeners());
  }
}
