import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/l10n/app_strings.dart';
import 'core/providers.dart';
import 'core/push/push_service.dart';
import 'core/realtime/realtime.dart';
import 'core/router/app_router.dart';
import 'core/settings/settings_provider.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_typography.dart';
import 'core/theme/kora_colors.dart';
import 'core/widgets/feedback.dart';
import 'features/auth/presentation/auth_providers.dart';

class KoraApp extends ConsumerStatefulWidget {
  const KoraApp({super.key});

  @override
  ConsumerState<KoraApp> createState() => _KoraAppState();
}

class _KoraAppState extends ConsumerState<KoraApp> {
  StreamSubscription? _connSub;
  StreamSubscription<RealtimeEvent>? _rtSub;
  bool _offline = false;
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _connSub = Connectivity()
        .onConnectivityChanged
        .listen((results) => setState(() {
              _offline = results.contains(ConnectivityResult.none);
            }),);

    // Connect realtime once authenticated; feed global events to UI.
    ref.listenManual(authControllerProvider, (prev, next) {
      final rt = ref.read(realtimeProvider);
      if (next is Authenticated) {
        rt.connect();
        _rtSub ??= rt.events.listen(_onEvent);
        unawaited(ref.read(pushServiceProvider).sync());
      } else if (next is Unauthenticated) {
        _rtSub?.cancel();
        _rtSub = null;
      }
    });
  }

  void _onEvent(RealtimeEvent e) {
    final ctx = _messengerKey.currentContext;
    if (ctx == null) return;
    switch (e.type) {
      case 'notification.created':
        KoraSnackbar.show(
            ctx, e.data['title'] as String? ?? S.t('notif.new'),);
        break;
      case 'order.status_changed':
        final status = e.data['status'] as String?;
        if (status != null) {
          KoraSnackbar.show(
              ctx, S.t('notif.status_changed', {'status': status}),);
        }
        break;
      case 'courier.assigned':
        KoraSnackbar.show(
            ctx,
            S.t('notif.courier_assigned',
                {'name': e.data['courierName'] as String? ?? ''},),);
        break;
      case 'order.delivered':
        KoraSnackbar.show(ctx, S.t('notif.delivered'));
        break;
    }
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _rtSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final settings = ref.watch(settingsProvider);
    S.lang = settings.language;
    return MaterialApp.router(
      title: 'KORA',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      // KORA ships a single light lilac identity — no dark mode.
      themeMode: ThemeMode.light,
      routerConfig: router,
      scaffoldMessengerKey: _messengerKey,
      builder: (context, child) {
        // Single light lilac identity — dark tokens stay unused.
        KoraTheme.dark = false;
        SystemChrome.setSystemUIOverlayStyle(
          const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            systemNavigationBarColor: KoraColors.white,
            systemNavigationBarIconBrightness: Brightness.dark,
          ),
        );
        final mq = MediaQuery.of(context);
        final content = MediaQuery(
          data: mq.copyWith(disableAnimations: settings.reduceMotion),
          child: child ?? const SizedBox.shrink(),
        );
        return Column(
          children: [
            if (_offline)
              Container(
                width: double.infinity,
                color: KoraColors.deepPurple,
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 6,
                  bottom: 6,
                ),
                child: Text(
                  S.t('common.no_internet'),
                  textAlign: TextAlign.center,
                  style: AppTypography.caption
                      .copyWith(color: KoraColors.white),
                ),
              ),
            Expanded(child: content),
          ],
        );
      },
    );
  }
}
