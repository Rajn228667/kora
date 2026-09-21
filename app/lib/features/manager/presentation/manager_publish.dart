import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/config/env.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/media/file_sink.dart';
import '../../../core/media/kora_image.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/kora_colors.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/fields.dart';
import '../data/manager_repository.dart';
import 'manager_tools.dart';

/// Manager "+" → product publish flow: pick a photo, one-tap
/// "process" normalizes it into a Wolt/Glovo-style 1:1 card (white
/// canvas, product centered, soft border, mild enhancement), then
/// name/description/price/stock/bonus → publish.
class PublishProductSheet extends ConsumerStatefulWidget {
  const PublishProductSheet({super.key, this.product});

  final Product? product;

  static Future<void> show(BuildContext context, {Product? product}) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: KoraColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
        ),
        builder: (_) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: PublishProductSheet(product: product),
        ),
      );

  @override
  ConsumerState<PublishProductSheet> createState() =>
      _PublishProductSheetState();
}

class _PublishProductSheetState extends ConsumerState<PublishProductSheet> {
  final _captureKey = GlobalKey();
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _price = TextEditingController();
  final _stock = TextEditingController();
  final _bonus = TextEditingController();
  bool _available = true;
  bool _busy = false;

  /// Raw picked photo; preview renders it on the normalized card.
  Uint8List? _raw;

  /// Final image reference — `file://` after processing/editing.
  String? _imageUrl;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    if (p != null) {
      _name.text = p.name;
      _desc.text = p.description;
      _price.text = '${p.priceTiyn ~/ 100}';
      _stock.text = '${p.stock}';
      _bonus.text = '${p.bonusPercent}';
      _available = p.available;
      _imageUrl = p.imageUrl;
    }
  }

  // Slight auto-enhancement — the "script" look used by grocery cards:
  // a touch of contrast + saturation so products pop on white.
  List<double> get _enhance => const [
        1.12, 0.02, 0.02, 0, -6,
        0.02, 1.10, 0.02, 0, -6,
        0.02, 0.02, 1.08, 0, -6,
        0, 0, 0, 1, 0,
      ];

  Future<void> _pick() async {
    try {
      final x = await ImagePicker()
          .pickImage(source: ImageSource.gallery, maxWidth: 1600);
      if (x == null) return;
      final b = await x.readAsBytes();
      setState(() {
        _raw = b;
        _imageUrl = null; // raw must be processed before publishing
      });
    } catch (_) {
      if (mounted) {
        KoraSnackbar.show(context, S.t('chat.photo_unavailable'));
      }
    }
  }

  /// Bakes the normalized card to PNG — output is what customers see.
  Future<void> _process() async {
    if (_raw == null) return;
    setState(() => _busy = true);
    try {
      // Wait a frame so the RepaintBoundary has the latest paint.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final boundary = _captureKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 2);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      _imageUrl =
          await koraSavePng(data.buffer.asUint8List(), 'kora_product');
      setState(() {});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editManually() async {
    final uri = await ProductImageEditor.show(context);
    if (uri != null && mounted) setState(() => _imageUrl = uri);
  }

  /// API mode uploads the baked PNG to `/v1/media`; mock keeps `file://`.
  Future<String?> _resolveImageUrl() async {
    final url = _imageUrl;
    if (url == null || !url.startsWith('file://')) return url;
    if (AppEnv.isMock) return url;
    final bytes = await File(url.substring(7)).readAsBytes();
    final res = await ref.read(apiClientProvider).post(
      '/media',
      body: {
        'dataBase64': base64Encode(bytes),
        'contentType': 'image/png',
      },
    ) as Map<String, dynamic>;
    return '${AppEnv.apiUrl}${res['url']}';
  }

  Future<void> _publish() async {
    final p = widget.product;
    if (_name.text.trim().length < 2) return;
    setState(() => _busy = true);
    try {
      final imageUrl = await _resolveImageUrl();
      await ref.read(managerProductsProvider.notifier).save(
            Product(
              id: p?.id ?? '',
              storeId: p?.storeId ?? 'kora-market',
              name: _name.text.trim(),
              description: _desc.text.trim(),
              priceTiyn: (int.tryParse(_price.text) ?? 0) * 100,
              bonusPercent:
                  (int.tryParse(_bonus.text) ?? 0).clamp(0, 50),
              stock: int.tryParse(_stock.text) ?? 0,
              available: _available,
              imageUrl: imageUrl,
            ),
          );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return Padding(
      padding: AppSpacing.cardPadding,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              p == null
                  ? S.t('manager.new_product')
                  : S.t('manager.edit_product'),
              style: AppTypography.title,
            ),
            const SizedBox(height: AppSpacing.md),

            // ── Photo zone: normalized 1:1 card preview ──
            Center(
              child: RepaintBoundary(
                key: _captureKey,
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    color: KoraColors.white,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: KoraColors.softBorderC),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _imageUrl != null
                      ? KoraImage(url: _imageUrl, fit: BoxFit.cover)
                      : _raw != null
                          ? Padding(
                              padding: const EdgeInsets.all(14),
                              child: ColorFiltered(
                                colorFilter:
                                    ColorFilter.matrix(_enhance),
                                child: Image.memory(
                                  _raw!,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            )
                          : Icon(
                              AppIcons.gallery,
                              size: 40,
                              color: KoraColors.placeholderC,
                            ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: KoraOutlinedButton(
                    label: S.t('editor.pick'),
                    icon: AppIcons.gallery,
                    onPressed: _busy ? null : _pick,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: KoraOutlinedButton(
                    label: S.t('manager.process_photo'),
                    icon: AppIcons.auto,
                    onPressed: _raw == null || _busy ? null : _process,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Center(
              child: TextButton(
                onPressed: _busy ? null : _editManually,
                child: Text(
                  S.t('manager.edit_photo'),
                  style: AppTypography.label
                      .copyWith(color: KoraColors.primary),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),

            KoraTextField(
              controller: _name,
              hint: S.t('manager.product_name'),
            ),
            const SizedBox(height: AppSpacing.sm),
            KoraTextField(
              controller: _desc,
              hint: S.t('manager.description'),
              maxLines: 2,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: KoraTextField(
                    controller: _price,
                    hint: S.t('manager.price'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: KoraTextField(
                    controller: _stock,
                    hint: S.t('manager.stock'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: KoraTextField(
                    controller: _bonus,
                    hint: S.t('manager.bonus_percent'),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            SwitchListTile(
              value: _available,
              onChanged: (v) => setState(() => _available = v),
              title: Text(S.t('manager.in_sale'),
                  style: AppTypography.label,),
              contentPadding: EdgeInsets.zero,
            ),
            KoraButton(
              label: S.t('manager.publish'),
              loading: _busy,
              onPressed: _busy ? null : _publish,
            ),
            SizedBox(
              height: MediaQuery.of(context).viewPadding.bottom +
                  AppSpacing.sm,
            ),
          ],
        ),
      ),
    );
  }
}
