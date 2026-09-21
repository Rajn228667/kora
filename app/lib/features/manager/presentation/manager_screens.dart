import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/maps/map_provider.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/kora_colors.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/fields.dart';
import '../../../core/widgets/misc.dart';
import '../../orders/data/orders_repository.dart';

class ManagerRepository {
  ManagerRepository(this._ref);

  final Ref _ref;

  Future<ManagerDashboard> dashboard() async {
    final res = await _ref
        .read(apiClientProvider)
        .get('/manager/dashboard') as Map<String, dynamic>;
    return ManagerDashboard(
      newOrders: (res['newOrders'] as num?)?.toInt() ?? 0,
      preparing: (res['preparing'] as num?)?.toInt() ?? 0,
      ready: (res['ready'] as num?)?.toInt() ?? 0,
      deliveredToday: (res['deliveredToday'] as num?)?.toInt() ?? 0,
      cancelledToday: (res['cancelledToday'] as num?)?.toInt() ?? 0,
      salesTodayTiyn: (res['salesTodayTiyn'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> act(String orderId, String action,
      {String? courierId,}) async {
    await _ref.read(apiClientProvider).post(
        '/manager/orders/$orderId/$action',
        body: {if (courierId != null) 'courierId': courierId},);
  }

  Future<List<CourierInfo>> couriers() async {
    final res = await _ref
        .read(apiClientProvider)
        .get('/manager/couriers') as Map<String, dynamic>;
    return (res['items'] as List)
        .map((c) => CourierInfo(
              id: (c as Map)['id'] as String,
              name: c['name'] as String? ?? S.t('call.courier'),
              status: CourierStatus.values.firstWhere(
                (s) => s.name == c['status'],
                orElse: () => CourierStatus.offline,
              ),
              activeOrders: (c['activeOrders'] as num?)?.toInt() ?? 0,
            ),)
        .toList();
  }

  Future<List<Product>> products() async {
    final res = await _ref
        .read(apiClientProvider)
        .get('/manager/products') as Map<String, dynamic>;
    return (res['items'] as List)
        .map((p) => Product.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveProduct(Product p) async {
    final body = {
      'name': p.name,
      'description': p.description,
      'priceTiyn': p.priceTiyn,
      'oldPriceTiyn': p.oldPriceTiyn,
      'bonusPercent': p.bonusPercent,
      'stock': p.stock,
      'available': p.available,
      'storeId': p.storeId,
    };
    if (p.id.isEmpty) {
      await _ref.read(apiClientProvider).post('/manager/products', body: body);
    } else {
      await _ref
          .read(apiClientProvider)
          .patch('/manager/products/${p.id}', body: body);
    }
  }

  Future<Map<String, dynamic>> cityMap() async =>
      await _ref.read(apiClientProvider).get('/manager/map')
          as Map<String, dynamic>;
}

final managerRepoProvider = Provider((ref) => ManagerRepository(ref));

final managerDashboardProvider = FutureProvider(
    (ref) => ref.watch(managerRepoProvider).dashboard(),);

final managerCouriersProvider = FutureProvider(
    (ref) => ref.watch(managerRepoProvider).couriers(),);

final managerProductsProvider = AsyncNotifierProvider<
    ManagerProductsController, List<Product>>(ManagerProductsController.new);

class ManagerProductsController extends AsyncNotifier<List<Product>> {
  @override
  Future<List<Product>> build() =>
      ref.watch(managerRepoProvider).products();

  Future<void> save(Product p) async {
    await ref.read(managerRepoProvider).saveProduct(p);
    ref.invalidateSelf();
  }
}

/// Manager cabinet — tabs: Dashboard / Orders / Products / Map.
class ManagerScreen extends ConsumerStatefulWidget {
  const ManagerScreen({super.key});

  @override
  ConsumerState<ManagerScreen> createState() => _ManagerScreenState();
}

class _ManagerScreenState extends ConsumerState<ManagerScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(S.t('manager.title')),
      ),
      body: IndexedStack(
        index: _tab,
        children: const [
          _DashboardTab(),
          _OrdersTab(),
          _ProductsTab(),
          _MapTab(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        items: [
          BottomNavigationBarItem(
              icon: const Icon(AppIcons.dashboard),
              label: S.t('manager.dashboard'),),
          BottomNavigationBarItem(
              icon: const Icon(AppIcons.orders),
              label: S.t('manager.orders'),),
          BottomNavigationBarItem(
              icon: const Icon(AppIcons.inventory),
              label: S.t('manager.products'),),
          BottomNavigationBarItem(
              icon: const Icon(AppIcons.map), label: S.t('manager.map'),),
        ],
      ),
    );
  }
}

class _DashboardTab extends ConsumerWidget {
  const _DashboardTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dash = ref.watch(managerDashboardProvider);
    return dash.when(
      loading: () => const KoraLoadingState(),
      error: (_, __) => KoraErrorState(
        message: S.t('manager.load_error'),
        onRetry: () => ref.invalidate(managerDashboardProvider),
      ),
      data: (d) => GridView.count(
        padding: const EdgeInsets.all(AppSpacing.lg),
        crossAxisCount: 2,
        mainAxisSpacing: AppSpacing.md,
        crossAxisSpacing: AppSpacing.md,
        childAspectRatio: 1.5,
        children: [
          _ToolAction(S.t('manager.action_card'), AppIcons.palette,
              () => context.push('/manager/card-generator'),),
          _ToolAction(S.t('manager.action_photo'), AppIcons.camera,
              () => context.push('/manager/image-editor'),),
          _ToolAction(S.t('manager.action_promo'), AppIcons.promo,
              () => context.push('/manager/promo-builder'),),
          _ToolAction(S.t('manager.action_schedule'), AppIcons.clock,
              () => context.push('/manager/schedule'),),
          _ToolAction(S.t('manager.grant_bonus'), AppIcons.gift,
              () => _GrantBonusSheet.show(context),),
          _Stat(S.t('manager.new'), '${d.newOrders}',
              AppIcons.notification,),
          _Stat(S.t('manager.preparing'), '${d.preparing}',
              AppIcons.restaurant,),
          _Stat(S.t('manager.ready'), '${d.ready}', AppIcons.check),
          _Stat(S.t('manager.delivered'), '${d.deliveredToday}',
              AppIcons.bike,),
          _Stat(S.t('manager.cancelled'), '${d.cancelledToday}',
              AppIcons.close,),
          _Stat(S.t('manager.sales'), KoraPrice.format(d.salesTodayTiyn),
              AppIcons.analytics,),
        ],
      ),
    );
  }
}

class _ToolAction extends StatelessWidget {
  const _ToolAction(this.label, this.icon, this.onTap);

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return KoraCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              gradient: KoraColors.primaryGradient,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: KoraColors.white, size: 17),
          ),
          const Spacer(),
          Text(label,
              style: AppTypography.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.icon);

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return KoraCard(
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: KoraColors.primary, size: 22),
          const Spacer(),
          Text(value,
              style: AppTypography.titleLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,),
          Text(label, style: AppTypography.caption),
        ],
      ),
    );
  }
}

class _OrdersTab extends ConsumerWidget {
  const _OrdersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(ordersProvider);
    return orders.when(
      loading: () => const Column(
        children: [KoraCardSkeleton(), KoraCardSkeleton()],
      ),
      error: (_, __) => KoraErrorState(
        message: S.t('orders.load_error'),
        onRetry: () => ref.read(ordersProvider.notifier).refresh(),
      ),
      data: (list) => list.isEmpty
          ? KoraEmptyState(
              icon: AppIcons.orders,
              title: S.t('manager.no_orders'),
              message: S.t('manager.no_orders_sub'),
            )
          : RefreshIndicator(
              color: KoraColors.primary,
              onRefresh: () =>
                  ref.read(ordersProvider.notifier).refresh(),
              child: ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.lg),
                itemCount: list.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (_, i) =>
                    _ManagerOrderTile(order: list[i]),
              ),
            ),
    );
  }
}

class _ManagerOrderTile extends ConsumerWidget {
  const _ManagerOrderTile({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(managerRepoProvider);
    Future<void> act(String action) async {
      await repo.act(order.id, action);
      await ref.read(ordersProvider.notifier).refresh();
    }

    Future<void> assignCourier() async {
      final couriers = await ref.read(managerCouriersProvider.future);
      if (!context.mounted) return;
      final picked = await KoraBottomSheet.show<CourierInfo>(
        context,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: couriers
                .map(
                  (c) => ListTile(
                    leading: const Icon(AppIcons.courier,
                        color: KoraColors.primary,),
                    title: Text(c.name, style: AppTypography.label),
                    subtitle: Text(
                      S.t('manager.courier_orders', {
                        'status': c.status.name,
                        'count': '${c.activeOrders}',
                      }),
                      style: AppTypography.caption,
                    ),
                    onTap: () => Navigator.pop(context, c),
                  ),
                )
                .toList(),
          ),
        ),
      );
      if (picked != null) {
        await repo.act(order.id, 'assign-courier', courierId: picked.id);
        await ref.read(ordersProvider.notifier).refresh();
      }
    }

    return KoraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('№ ${order.number} · ${order.storeName}',
                    style: AppTypography.titleSmall,),
              ),
              KoraStatusChip(label: orderStatusLabel(order.status)),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${S.t('order.positions', {'count': '${order.items.fold(0, (s, i) => s + i.quantity)}'})} · '
            '${KoraPrice.format(order.totalTiyn)} · '
            '${paymentStatusLabel(order.paymentStatus)}',
            style: AppTypography.caption,
          ),
          Text(order.delivery.address, style: AppTypography.caption),
          if (order.delivery.comment != null)
            Text('«${order.delivery.comment}»',
                style: AppTypography.caption,),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              if (order.status == OrderStatus.pending)
                _Action(S.t('manager.accept'), () => act('accept')),
              if (order.status == OrderStatus.pending)
                _Action(S.t('manager.reject'), () => act('reject'),
                    danger: true,),
              if (order.status == OrderStatus.accepted ||
                  order.status == OrderStatus.preparing)
                _Action(S.t('manager.ready_btn'), () => act('ready')),
              if (order.status == OrderStatus.readyForPickup)
                _Action(S.t('manager.assign'), assignCourier),
              _Action(
                S.t('chat.title'),
                () => context.push('/chat/${order.id}'),
                ghost: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet: search customer by phone, credit wallet bonus.
class _GrantBonusSheet extends ConsumerStatefulWidget {
  const _GrantBonusSheet();

  static Future<void> show(BuildContext context) =>
      KoraBottomSheet.show<void>(context, child: const _GrantBonusSheet());

  @override
  ConsumerState<_GrantBonusSheet> createState() => _GrantBonusSheetState();
}

class _GrantBonusSheetState extends ConsumerState<_GrantBonusSheet> {
  final _phone = TextEditingController();
  final _amount = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  Map<String, dynamic>? _selected;
  bool _busy = false;

  Future<void> _search(String q) async {
    _selected = null;
    if (q.trim().length < 3) {
      setState(() => _results = []);
      return;
    }
    final res = await ref.read(apiClientProvider).get(
      '/manager/users',
      query: {'q': q.trim()},
    ) as Map<String, dynamic>;
    if (mounted) {
      setState(() =>
          _results = (res['items'] as List).cast<Map<String, dynamic>>(),);
    }
  }

  Future<void> _grant() async {
    final user = _selected;
    final amount = (int.tryParse(_amount.text) ?? 0) * 100;
    if (user == null || amount <= 0) return;
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).post(
        '/manager/users/${user['id']}/bonus',
        body: {
          'amountTiyn': amount,
          'title': S.t('manager.grant_bonus'),
        },
      );
      if (mounted) {
        Navigator.pop(context);
        KoraSnackbar.show(context, S.t('manager.bonus_sent'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppSpacing.cardPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(S.t('manager.grant_bonus'), style: AppTypography.title),
          const SizedBox(height: AppSpacing.md),
          KoraTextField(
            controller: _phone,
            hint: S.t('manager.user_phone'),
            keyboardType: TextInputType.phone,
            onChanged: _search,
          ),
          if (_results.isNotEmpty)
            ..._results.map(
              (u) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${u['name'] == '' ? u['phone'] : u['name']} · ${u['phone']}',
                  style: AppTypography.label,
                ),
                onTap: () => setState(() {
                  _selected = u;
                  _results = [];
                  _phone.text = '${u['phone']}';
                }),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          KoraTextField(
            controller: _amount,
            hint: S.t('manager.bonus_amount'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: AppSpacing.md),
          KoraButton(
            label: _selected == null
                ? S.t('manager.user_not_found')
                : S.t('manager.grant_bonus'),
            onPressed: _selected != null && !_busy ? _grant : null,
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action(this.label, this.onTap,
      {this.danger = false, this.ghost = false,});

  final String label;
  final VoidCallback onTap;
  final bool danger;
  final bool ghost;

  @override
  Widget build(BuildContext context) {
    if (ghost) {
      return TextButton(onPressed: onTap, child: Text(label));
    }
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor:
            danger ? KoraColors.error : KoraColors.primary,
        minimumSize: const Size(48, 40),
        textStyle: AppTypography.label,
      ),
      child: Text(label),
    );
  }
}

class _ProductsTab extends ConsumerWidget {
  const _ProductsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(managerProductsProvider);
    return Scaffold(
      body: products.when(
        loading: () => const KoraLoadingState(),
        error: (_, __) => KoraErrorState(
          message: S.t('manager.products_error'),
          onRetry: () => ref.invalidate(managerProductsProvider),
        ),
        data: (list) => ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: list.length,
          separatorBuilder: (_, __) =>
              const SizedBox(height: AppSpacing.sm),
          itemBuilder: (_, i) {
            final p = list[i];
            return KoraCard(
              onTap: () => _editProduct(context, ref, p),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name, style: AppTypography.label),
                        Text(
                          '${KoraPrice.format(p.priceTiyn)} · '
                          '${S.t('manager.stock_line', {'count': '${p.stock}'})}',
                          style: AppTypography.caption,
                        ),
                      ],
                    ),
                  ),
                  KoraStatusChip(
                    label: p.available
                        ? S.t('manager.in_sale')
                        : S.t('manager.hidden'),
                    tone: p.available
                        ? KoraStatusTone.success
                        : KoraStatusTone.neutral,
                  ),
                ],
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: KoraColors.primary,
        onPressed: () => _editProduct(context, ref, null),
        child: const Icon(AppIcons.add, color: KoraColors.white),
      ),
    );
  }

  void _editProduct(BuildContext context, WidgetRef ref, Product? p) {
    final name = TextEditingController(text: p?.name ?? '');
    final price = TextEditingController(
        text: p == null ? '' : '${p.priceTiyn ~/ 100}',);
    final stock =
        TextEditingController(text: '${p?.stock ?? 0}');
    final bonus =
        TextEditingController(text: '${p?.bonusPercent ?? 0}');
    var available = p?.available ?? true;
    KoraBottomSheet.show<void>(
      context,
      child: StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: AppSpacing.cardPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                  p == null
                      ? S.t('manager.new_product')
                      : S.t('manager.edit_product'),
                  style: AppTypography.title,),
              const SizedBox(height: AppSpacing.md),
              KoraTextField(
                  controller: name, hint: S.t('manager.product_name'),),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: KoraTextField(
                      controller: price,
                      hint: S.t('manager.price'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: KoraTextField(
                      controller: stock,
                      hint: S.t('manager.stock'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: KoraTextField(
                      controller: bonus,
                      hint: S.t('manager.bonus_percent'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                value: available,
                onChanged: (v) => setSheet(() => available = v),
                title:
                    Text(S.t('manager.in_sale'), style: AppTypography.label),
                contentPadding: EdgeInsets.zero,
              ),
              KoraButton(
                label: S.t('common.save'),
                onPressed: () async {
                  await ref
                      .read(managerProductsProvider.notifier)
                      .save(Product(
                        id: p?.id ?? '',
                        storeId: p?.storeId ?? 'kora-market',
                        name: name.text.trim(),
                        priceTiyn:
                            (int.tryParse(price.text) ?? 0) * 100,
                        bonusPercent:
                            (int.tryParse(bonus.text) ?? 0).clamp(0, 50),
                        stock: int.tryParse(stock.text) ?? 0,
                        available: available,
                      ),);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapTab extends ConsumerWidget {
  const _MapTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<Map<String, dynamic>>(
      future: ref.read(managerRepoProvider).cityMap(),
      builder: (context, snap) {
        if (!snap.hasData) return const KoraLoadingState();
        final m = snap.data!;
        final markers = <KoraMarker>[
          for (final s in (m['stores'] as List? ?? const []))
            if (s['lat'] != null)
              KoraMarker(
                point: GeoPoint(
                    lat: (s['lat'] as num).toDouble(),
                    lng: (s['lng'] as num).toDouble(),),
                kind: KoraMarkerKind.store,
                label: s['name'] as String?,
              ),
          for (final c in (m['couriers'] as List? ?? const []))
            KoraMarker(
              point: GeoPoint(
                  lat: (c['lat'] as num).toDouble(),
                  lng: (c['lng'] as num).toDouble(),),
              kind: KoraMarkerKind.courier,
            ),
          for (final o in (m['orders'] as List? ?? const []))
            if (o['lat'] != null)
              KoraMarker(
                point: GeoPoint(
                    lat: (o['lat'] as num).toDouble(),
                    lng: (o['lng'] as num).toDouble(),),
                kind: KoraMarkerKind.deliveryPoint,
                label: o['status'] as String?,
              ),
        ];
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: KoraMap(
            center: const GeoPoint(lat: 42.3417, lng: 69.5901),
            markers: markers,
          ),
        );
      },
    );
  }
}
