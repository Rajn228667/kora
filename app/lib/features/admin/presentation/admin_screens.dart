import '../../../core/media/local_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/l10n/app_strings.dart';
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
import '../../manager/presentation/manager_tools.dart';

class AdminRepository {
  AdminRepository(this._ref);

  final Ref _ref;

  Future<List<Map<String, dynamic>>> _list(String path) async {
    final res = await _ref.read(apiClientProvider).get(path)
        as Map<String, dynamic>;
    return (res['items'] as List).cast<Map<String, dynamic>>();
  }

  Future<List<User>> users() async =>
      (await _list('/admin/users')).map(User.fromJson).toList();

  Future<List<Order>> orders() async =>
      (await _list('/admin/orders')).map(Order.fromJson).toList();

  Future<List<Map<String, dynamic>>> payments() => _list('/admin/payments');

  Future<List<Store>> stores() async =>
      (await _list('/admin/stores')).map(Store.fromJson).toList();

  Future<List<Product>> products() async =>
      (await _list('/admin/products')).map(Product.fromJson).toList();

  Future<Product> saveProduct(Product? existing,
      Map<String, dynamic> body,) async {
    final api = _ref.read(apiClientProvider);
    final res = existing == null
        ? await api.post('/admin/products', body: body)
        : await api.patch('/admin/products/${existing.id}', body: body);
    return Product.fromJson(res as Map<String, dynamic>);
  }

  Future<void> deleteProduct(String id) =>
      _ref.read(apiClientProvider).delete('/admin/products/$id');

  Future<List<Map<String, dynamic>>> promoCodes() =>
      _list('/admin/promo-codes');

  Future<void> createPromoCode(Map<String, dynamic> body) =>
      _ref.read(apiClientProvider).post('/admin/promo-codes', body: body);

  Future<void> deletePromoCode(String code) =>
      _ref.read(apiClientProvider).delete('/admin/promo-codes/$code');

  Future<List<Promotion>> promotions() async =>
      (await _list('/admin/promotions')).map((j) {
        return Promotion(
          id: j['id'] as String,
          title: j['title'] as String? ?? '',
          subtitle: j['subtitle'] as String?,
          imageUrl: j['imageUrl'] as String?,
          storeId: j['storeId'] as String?,
          code: j['code'] as String?,
          discountPercent: (j['discountPercent'] as num?)?.toInt(),
        );
      }).toList();

  Future<void> createPromotion(Map<String, dynamic> body) =>
      _ref.read(apiClientProvider).post('/admin/promotions', body: body);

  Future<void> deletePromotion(String id) =>
      _ref.read(apiClientProvider).delete('/admin/promotions/$id');

  Future<List<AuditEntry>> audit() async =>
      (await _list('/admin/audit-logs')).map((j) {
        return AuditEntry(
          id: j['id'] as String,
          actor: j['actor'] as String? ?? '',
          role: UserRole.values.firstWhere(
            (r) => r.name == j['role'],
            orElse: () => UserRole.admin,
          ),
          action: j['action'] as String? ?? '',
          resource: j['resource'] as String? ?? '',
          at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
        );
      }).toList();
}

final adminRepoProvider = Provider((ref) => AdminRepository(ref));

/// Admin panel — catalog / promos / promo codes / orders / users /
/// payments / audit. Catalog CRUD lives here; everything an admin
/// creates shows up in the customer app instantly (same data source).
class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  int _tab = 0;
  int _refresh = 0;

  void _bump() => setState(() => _refresh++);

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(adminRepoProvider);
    final showFab = _tab <= 2;
    final tabs = [
      AdminCatalogTab(key: ValueKey('cat-$_refresh'), repo: repo),
      AdminPromoTab(key: ValueKey('promo-$_refresh'), repo: repo),
      AdminPromoCodeTab(
          key: ValueKey('code-$_refresh'), repo: repo,),
      
      _DataTab<User>(
        loader: repo.users,
        itemBuilder: (u) => KoraCard(
          child: Row(
            children: [
              KoraAvatar(
                initials: u.name.isEmpty
                    ? '?'
                    : u.name.substring(0, 1).toUpperCase(),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(u.name.isEmpty ? u.phone : u.name,
                        style: AppTypography.label,),
                    Text('${u.phone} · ${u.role.name}',
                        style: AppTypography.caption,),
                  ],
                ),
              ),
              KoraStatusChip(
                label: u.blocked
                    ? S.t('admin.blocked')
                    : S.t('admin.active'),
                tone: u.blocked
                    ? KoraStatusTone.error
                    : KoraStatusTone.success,
              ),
            ],
          ),
        ),
      ),
      _DataTab<Order>(
        loader: repo.orders,
        itemBuilder: (o) => KoraCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('№ ${o.number} · ${o.storeName}',
                        style: AppTypography.label,),
                    Text(
                      '${orderStatusLabel(o.status)} · '
                      '${paymentStatusLabel(o.paymentStatus)}',
                      style: AppTypography.caption,
                    ),
                  ],
                ),
              ),
              KoraPrice(tiyn: o.totalTiyn, style: AppTypography.label),
            ],
          ),
        ),
      ),
      _DataTab<Map<String, dynamic>>(
        loader: repo.payments,
        itemBuilder: (p) => KoraCard(
          child: Row(
            children: [
              const Icon(AppIcons.wallet, color: KoraColors.primary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${p['id']}', style: AppTypography.label,
                        maxLines: 1, overflow: TextOverflow.ellipsis,),
                    Text(
                        '${S.t('admin.order_of', {'id': '${p['orderId']}'})} · ${p['status']}',
                        style: AppTypography.caption,),
                  ],
                ),
              ),
              KoraPrice(
                tiyn: (p['amountTiyn'] as num?)?.toInt() ?? 0,
                style: AppTypography.label,
              ),
            ],
          ),
        ),
      ),
      _DataTab<AuditEntry>(
        loader: repo.audit,
        itemBuilder: (a) => KoraCard(
          child: Row(
            children: [
              const Icon(AppIcons.security, color: KoraColors.primary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.action, style: AppTypography.label),
                    Text(
                      '${a.actor} (${a.role.name}) → ${a.resource}',
                      style: AppTypography.caption,
                    ),
                  ],
                ),
              ),
              Text(
                '${a.at.hour}:${a.at.minute.toString().padLeft(2, '0')}',
                style: AppTypography.caption,
              ),
            ],
          ),
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(S.t('admin.title')),
      ),
      body: IndexedStack(index: _tab, children: tabs),
      floatingActionButton: !showFab
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                final show = switch (_tab) {
                  0 => AdminProductEditor.show,
                  1 => AdminPromoEditor.show,
                  _ => AdminPromoCodeEditor.show,
                };
                if (!context.mounted) return;
                final created = await show(context, repo);
                if (created && mounted) _bump();
              },
              icon: const Icon(AppIcons.add, color: KoraColors.white),
              label: Text(
                switch (_tab) {
                  0 => S.t('admin.product_new'),
                  1 => S.t('admin.promo_new'),
                  _ => S.t('admin.promocode_new'),
                },
                style: AppTypography.button
                    .copyWith(color: KoraColors.white),
              ),
              backgroundColor: KoraColors.primary,
            ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        selectedFontSize: 10,
        unselectedFontSize: 10,
        items: [
          BottomNavigationBarItem(
              icon: const Icon(AppIcons.inventory),
              label: S.t('admin.catalog'),),
          BottomNavigationBarItem(
              icon: const Icon(AppIcons.gift),
              label: S.t('admin.promos'),),
          BottomNavigationBarItem(
              icon: const Icon(AppIcons.promo),
              label: S.t('admin.promocodes'),),
          BottomNavigationBarItem(
              icon: const Icon(AppIcons.orders),
              label: S.t('admin.orders'),),
          BottomNavigationBarItem(
              icon: const Icon(AppIcons.people),
              label: S.t('admin.users'),),
          BottomNavigationBarItem(
              icon: const Icon(AppIcons.wallet),
              label: S.t('admin.payments'),),
          BottomNavigationBarItem(
              icon: const Icon(AppIcons.security),
              label: S.t('admin.audit'),),
        ],
      ),
    );
  }
}

class _DataTab<T> extends StatelessWidget {
  const _DataTab({required this.loader, required this.itemBuilder});

  final Future<List<T>> Function() loader;
  final Widget Function(T) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<T>>(
      future: loader(),
      builder: (context, snap) {
        if (snap.hasError) {
          return KoraErrorState(message: S.t('admin.load_error'));
        }
        if (!snap.hasData) return const KoraLoadingState();
        if (snap.data!.isEmpty) {
          return KoraEmptyState(
              icon: AppIcons.info, title: S.t('admin.empty'),);
        }
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: snap.data!.length,
          separatorBuilder: (_, __) =>
              const SizedBox(height: AppSpacing.sm),
          itemBuilder: (_, i) => itemBuilder(snap.data![i]),
        );
      },
    );
  }
}


// ---------------------------------------------------------------------------
// Catalog tab — every product across all stores, create/edit/delete.
// ---------------------------------------------------------------------------

class AdminCatalogTab extends StatefulWidget {
  const AdminCatalogTab({super.key, required this.repo});

  final AdminRepository repo;

  @override
  State<AdminCatalogTab> createState() => _AdminCatalogTabState();
}

class _AdminCatalogTabState extends State<AdminCatalogTab> {
  Future<(List<Product>, Map<String, String>)>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(List<Product>, Map<String, String>)> _load() async {
    final products = await widget.repo.products();
    final stores = await widget.repo.stores();
    return (
      products,
      {for (final s in stores) s.id: s.name},
    );
  }

  Future<void> _delete(Product p) async {
    final ok = await KoraDialog.confirm(
      context,
      title: S.t('admin.delete_product'),
      message: p.name,
      confirmLabel: S.t('common.delete'),
      destructive: true,
    );
    if (!ok) return;
    await widget.repo.deleteProduct(p.id);
    if (mounted) {
      KoraSnackbar.show(context, S.t('admin.deleted'));
      setState(() => _future = _load());
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(List<Product>, Map<String, String>)>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return KoraErrorState(
            message: S.t('admin.load_error'),
            onRetry: () => setState(() => _future = _load()),
          );
        }
        if (!snap.hasData) return const KoraLoadingState();
        final (products, storeNames) = snap.data!;
        if (products.isEmpty) {
          return KoraEmptyState(
            icon: AppIcons.inventory,
            title: S.t('admin.catalog_empty'),
            message: S.t('admin.catalog_empty_sub'),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: products.length,
          separatorBuilder: (_, __) =>
              const SizedBox(height: AppSpacing.sm),
          itemBuilder: (_, i) {
            final p = products[i];
            return KoraCard(
              onTap: () async {
                final saved =
                    await AdminProductEditor.show(
                        context, widget.repo,
                        existing: p,);
                if (saved && context.mounted) {
                  setState(() => _future = _load());
                }
              },
              child: Row(
                children: [
                  _ProductThumb(url: p.imageUrl),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name,
                            style: AppTypography.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,),
                        Text(
                          '${storeNames[p.storeId] ?? p.storeId} · '
                          '${S.t('manager.stock_line', {'count': '${p.stock}'})}',
                          style: AppTypography.caption,
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      KoraPrice(
                          tiyn: p.priceTiyn, style: AppTypography.label,),
                      if (p.oldPriceTiyn != null)
                        Text(
                          KoraPrice.format(p.oldPriceTiyn!),
                          style: AppTypography.caption.copyWith(
                            decoration: TextDecoration.lineThrough,
                            color: KoraColors.placeholderC,
                          ),
                        ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(AppIcons.delete,
                        color: KoraColors.placeholderC, size: 20,),
                    onPressed: () => _delete(p),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _ProductThumb extends StatelessWidget {
  const _ProductThumb({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final isFile = url != null && url!.startsWith('file://');
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        width: 48,
        height: 48,
        color: KoraColors.surfaceAlt,
        child: isFile
            ? koraLocalImage(url!.substring(7))
            : const Icon(AppIcons.inventory,
                color: KoraColors.softPurple, size: 22,),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Product editor — photo + name + price in ₸ + stock → catalog card.
// ---------------------------------------------------------------------------

class AdminProductEditor extends StatefulWidget {
  const AdminProductEditor(
      {super.key, required this.repo, this.existing,});

  final AdminRepository repo;
  final Product? existing;

  /// Returns true when a product was saved.
  static Future<bool> show(BuildContext context, AdminRepository repo,
      {Product? existing,}) async {
    final res = await KoraBottomSheet.show<bool>(
      context,
      child: AdminProductEditor(repo: repo, existing: existing),
    );
    return res ?? false;
  }

  @override
  State<AdminProductEditor> createState() => _AdminProductEditorState();
}

class _AdminProductEditorState extends State<AdminProductEditor> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _desc =
      TextEditingController(text: widget.existing?.description);
  late final _price = TextEditingController(
    text: widget.existing == null
        ? ''
        : '${widget.existing!.priceTiyn ~/ 100}',
  );
  late final _oldPrice = TextEditingController(
    text: widget.existing?.oldPriceTiyn == null
        ? ''
        : '${widget.existing!.oldPriceTiyn! ~/ 100}',
  );
  late final _stock = TextEditingController(
    text: '${widget.existing?.stock ?? 0}',
  );
  String? _storeId;
  String? _imagePath;
  bool _available = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _storeId = widget.existing?.storeId;
    _available = widget.existing?.available ?? true;
    _imagePath = widget.existing?.imageUrl;
  }

  Future<void> _pickPhoto() async {
    try {
      final x = await ImagePicker()
          .pickImage(source: ImageSource.gallery, maxWidth: 1024);
      if (x != null) setState(() => _imagePath = 'file://${x.path}');
    } catch (_) {
      if (mounted) {
        KoraSnackbar.show(context, S.t('chat.photo_unavailable'));
      }
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final priceKzt = int.tryParse(_price.text.trim()) ?? 0;
    if (name.isEmpty || priceKzt <= 0 || _storeId == null) return;
    setState(() => _saving = true);
    try {
      await widget.repo.saveProduct(widget.existing, {
        'storeId': _storeId,
        'name': name,
        'description': _desc.text.trim(),
        'imageUrl': _imagePath,
        'priceTiyn': priceKzt * 100,
        'oldPriceTiyn': (int.tryParse(_oldPrice.text.trim()) ?? 0) > 0
            ? int.parse(_oldPrice.text.trim()) * 100
            : null,
        'stock': int.tryParse(_stock.text.trim()) ?? 0,
        'available': _available,
      });
      if (mounted) {
        KoraSnackbar.show(context, S.t('admin.product_saved'));
        Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    return Padding(
      padding: AppSpacing.cardPadding,
      child: FutureBuilder<List<Store>>(
        future: repo.stores(),
        builder: (context, snap) {
          final stores = snap.data ?? const <Store>[];
          _storeId ??= stores.isNotEmpty ? stores.first.id : null;
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.existing == null
                      ? S.t('admin.product_new')
                      : S.t('common.edit'),
                  style: AppTypography.title,
                ),
                const SizedBox(height: AppSpacing.md),
                // Photo picker — square tile with dashed-ish border.
                GestureDetector(
                  onTap: _pickPhoto,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: Container(
                      height: 140,
                      decoration: BoxDecoration(
                        color: KoraColors.surfaceAlt,
                        border: Border.all(color: KoraColors.softBorderC),
                        borderRadius:
                            BorderRadius.circular(AppRadius.md),
                      ),
                      child: _imagePath == null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(AppIcons.camera,
                                    color: KoraColors.softPurple,
                                    size: 32,),
                                const SizedBox(height: AppSpacing.xs),
                                Text(S.t('admin.photo_add'),
                                    style: AppTypography.caption,),
                              ],
                            )
                          : koraLocalImage(
                              _imagePath!.startsWith('file://')
                                  ? _imagePath!.substring(7)
                                  : _imagePath!,
                              width: double.infinity,
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: KoraGhostButton(
                        label: S.t('editor.open'),
                        icon: AppIcons.tune,
                        onPressed: () async {
                          final p = await ProductImageEditor
                              .show(context);
                          if (p != null && mounted) {
                            setState(() => _imagePath = p);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: KoraGhostButton(
                        label: S.t('cardgen.open'),
                        icon: AppIcons.palette,
                        onPressed: () async {
                          final p = await CardGeneratorScreen
                              .show(context);
                          if (p != null && mounted) {
                            setState(() => _imagePath = p);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                KoraTextField(
                    controller: _name, hint: S.t('admin.product_name'),),
                const SizedBox(height: AppSpacing.sm),
                KoraTextField(
                  controller: _desc,
                  hint: S.t('admin.product_desc'),
                  maxLines: 2,
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: KoraTextField(
                        controller: _price,
                        hint: S.t('admin.price_kzt'),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: KoraTextField(
                        controller: _oldPrice,
                        hint: S.t('admin.old_price'),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: KoraTextField(
                        controller: _stock,
                        hint: S.t('admin.stock_qty'),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _storeId,
                        decoration: InputDecoration(
                            labelText: S.t('admin.store'),),
                        items: [
                          for (final s in stores)
                            DropdownMenuItem(
                                value: s.id, child: Text(s.name),),
                        ],
                        onChanged: (v) =>
                            setState(() => _storeId = v),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(S.t('admin.available'),
                      style: AppTypography.label,),
                  value: _available,
                  activeThumbColor: KoraColors.primary,
                  onChanged: (v) => setState(() => _available = v),
                ),
                KoraButton(
                  label: S.t('common.save'),
                  loading: _saving,
                  onPressed: _save,
                ),
                SizedBox(
                    height: MediaQuery.of(context).viewInsets.bottom,),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Promotions tab + editor (banners shown on the customer home screen).
// ---------------------------------------------------------------------------

class AdminPromoTab extends StatefulWidget {
  const AdminPromoTab({super.key, required this.repo});

  final AdminRepository repo;

  @override
  State<AdminPromoTab> createState() => _AdminPromoTabState();
}

class _AdminPromoTabState extends State<AdminPromoTab> {
  Future<List<Promotion>>? _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repo.promotions();
  }

  void _reload() =>
      setState(() => _future = widget.repo.promotions());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Promotion>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return KoraErrorState(
            message: S.t('admin.load_error'),
            onRetry: _reload,
          );
        }
        if (!snap.hasData) return const KoraLoadingState();
        final list = snap.data!;
        if (list.isEmpty) {
          return KoraEmptyState(
            icon: AppIcons.gift,
            title: S.t('admin.promos_empty'),
            message: S.t('admin.promos_empty_sub'),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: list.length,
          separatorBuilder: (_, __) =>
              const SizedBox(height: AppSpacing.sm),
          itemBuilder: (_, i) {
            final p = list[i];
            return KoraCard(
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      gradient: KoraColors.primaryGradient,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(AppIcons.gift,
                        color: KoraColors.white, size: 20,),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.title, style: AppTypography.label),
                        if (p.subtitle != null)
                          Text(p.subtitle!,
                              style: AppTypography.caption,),
                      ],
                    ),
                  ),
                  if (p.discountPercent != null)
                    KoraBadge(label: '-${p.discountPercent}%'),
                  IconButton(
                    icon: Icon(AppIcons.delete,
                        color: KoraColors.placeholderC, size: 20,),
                    onPressed: () async {
                      await widget.repo.deletePromotion(p.id);
                      _reload();
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class AdminPromoEditor extends StatefulWidget {
  const AdminPromoEditor({super.key, required this.repo});

  final AdminRepository repo;

  static Future<bool> show(
      BuildContext context, AdminRepository repo,) async {
    final res = await KoraBottomSheet.show<bool>(
      context,
      child: AdminPromoEditor(repo: repo),
    );
    return res ?? false;
  }

  @override
  State<AdminPromoEditor> createState() => _AdminPromoEditorState();
}

class _AdminPromoEditorState extends State<AdminPromoEditor> {
  final _title = TextEditingController();
  final _subtitle = TextEditingController();
  final _percent = TextEditingController();
  bool _saving = false;

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.repo.createPromotion({
        'title': _title.text.trim(),
        'subtitle': _subtitle.text.trim().isEmpty
            ? null
            : _subtitle.text.trim(),
        'discountPercent': int.tryParse(_percent.text.trim()),
      });
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
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
          Text(S.t('admin.promo_new'), style: AppTypography.title),
          const SizedBox(height: AppSpacing.md),
          KoraTextField(
              controller: _title, hint: S.t('admin.promo_title'),),
          const SizedBox(height: AppSpacing.sm),
          KoraTextField(
              controller: _subtitle, hint: S.t('admin.promo_subtitle'),),
          const SizedBox(height: AppSpacing.sm),
          KoraTextField(
            controller: _percent,
            hint: S.t('admin.promo_percent'),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          const SizedBox(height: AppSpacing.lg),
          KoraButton(
              label: S.t('common.save'),
              loading: _saving,
              onPressed: _save,),
          SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Promo codes tab + editor — codes validate at checkout (KORA700 pattern).
// ---------------------------------------------------------------------------

class AdminPromoCodeTab extends StatefulWidget {
  const AdminPromoCodeTab({super.key, required this.repo});

  final AdminRepository repo;

  @override
  State<AdminPromoCodeTab> createState() => _AdminPromoCodeTabState();
}

class _AdminPromoCodeTabState extends State<AdminPromoCodeTab> {
  Future<List<Map<String, dynamic>>>? _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repo.promoCodes();
  }

  void _reload() =>
      setState(() => _future = widget.repo.promoCodes());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return KoraErrorState(
            message: S.t('admin.load_error'),
            onRetry: _reload,
          );
        }
        if (!snap.hasData) return const KoraLoadingState();
        final list = snap.data!;
        if (list.isEmpty) {
          return KoraEmptyState(
            icon: AppIcons.promo,
            title: S.t('admin.codes_empty'),
            message: S.t('admin.codes_empty_sub'),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: list.length,
          separatorBuilder: (_, __) =>
              const SizedBox(height: AppSpacing.sm),
          itemBuilder: (_, i) {
            final c = list[i];
            final discount = (c['discountTiyn'] as num?)?.toInt() ?? 0;
            final percent = (c['percent'] as num?)?.toInt();
            final productId = c['productId'] as String?;
            return KoraCard(
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: KoraColors.selected,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(AppIcons.promo,
                        color: KoraColors.primary, size: 20,),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${c['code']}', style: AppTypography.label),
                        Text(
                          [
                            if (discount > 0)
                              '−${KoraPrice.format(discount)}',
                            if (percent != null) '−$percent%',
                            if (productId != null)
                              S.t('admin.for_product'),
                            if (((c['minOrderTiyn'] as num?)?.toInt() ??
                                    0) >
                                0)
                              S.t('promo.min_order', {
                                'amount': KoraPrice.format(
                                    (c['minOrderTiyn'] as num).toInt(),),
                              },),
                          ].join(' · '),
                          style: AppTypography.caption,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(AppIcons.delete,
                        color: KoraColors.placeholderC, size: 20,),
                    onPressed: () async {
                      await widget.repo
                          .deletePromoCode('${c['code']}');
                      _reload();
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class AdminPromoCodeEditor extends StatefulWidget {
  const AdminPromoCodeEditor({super.key, required this.repo});

  final AdminRepository repo;

  static Future<bool> show(
      BuildContext context, AdminRepository repo,) async {
    final res = await KoraBottomSheet.show<bool>(
      context,
      child: AdminPromoCodeEditor(repo: repo),
    );
    return res ?? false;
  }

  @override
  State<AdminPromoCodeEditor> createState() =>
      _AdminPromoCodeEditorState();
}

class _AdminPromoCodeEditorState extends State<AdminPromoCodeEditor> {
  final _code = TextEditingController();
  final _discount = TextEditingController();
  final _minOrder = TextEditingController();
  String? _productId;
  bool _saving = false;

  Future<void> _save() async {
    if (_code.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.repo.createPromoCode({
        'code': _code.text.trim().toUpperCase(),
        'discountTiyn':
            (int.tryParse(_discount.text.trim()) ?? 0) * 100,
        'minOrderTiyn':
            (int.tryParse(_minOrder.text.trim()) ?? 0) * 100,
        if (_productId != null) 'productId': _productId,
      });
      if (mounted) {
        KoraSnackbar.show(context, S.t('admin.code_saved'));
        Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppSpacing.cardPadding,
      child: FutureBuilder<List<Product>>(
        future: widget.repo.products(),
        builder: (context, snap) {
          final products = snap.data ?? const <Product>[];
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(S.t('admin.promocode_new'),
                  style: AppTypography.title,),
              const SizedBox(height: AppSpacing.md),
              KoraTextField(
                controller: _code,
                hint: S.t('admin.code_field'),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: KoraTextField(
                      controller: _discount,
                      hint: S.t('admin.discount_kzt'),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: KoraTextField(
                      controller: _minOrder,
                      hint: S.t('admin.min_order_kzt'),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                initialValue: _productId,
                decoration: InputDecoration(
                  labelText: S.t('admin.promo_scope'),
                ),
                items: [
                  DropdownMenuItem(
                    child: Text(S.t('admin.any_product')),
                  ),
                  for (final p in products)
                    DropdownMenuItem(value: p.id, child: Text(p.name)),
                ],
                onChanged: (v) => setState(() => _productId = v),
              ),
              const SizedBox(height: AppSpacing.lg),
              KoraButton(
                label: S.t('common.save'),
                loading: _saving,
                onPressed: _save,
              ),
              SizedBox(
                  height: MediaQuery.of(context).viewInsets.bottom,),
            ],
          );
        },
      ),
    );
  }
}
