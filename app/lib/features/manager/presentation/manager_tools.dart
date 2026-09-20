import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/media/file_sink.dart';
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
import 'manager_screens.dart';

// ---------------------------------------------------------------------------
// Store schedule editor (§41) — per-weekday open/close, closed toggle.
// ---------------------------------------------------------------------------

class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  /// weekday (0=Mon) → (open, close) minutes; null = closed.
  final Map<int, ({int open, int close})?> _days = {};
  bool _loaded = false;
  bool _saving = false;

  Future<void> _load() async {
    final res = await ref.read(apiClientProvider)
        .get('/manager/schedule') as Map<String, dynamic>;
    final days = res['days'] as Map? ?? {};
    days.forEach((k, v) {
      final d = int.tryParse('$k');
      if (d == null) return;
      if (v == null) {
        _days[d] = null;
      } else {
        _days[d] = (
          open: (v['open'] as num).toInt(),
          close: (v['close'] as num).toInt(),
        );
      }
    });
    if (mounted) setState(() => _loaded = true);
  }

  String _fmt(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';

  Future<int?> _pick(int current) async {
    final t = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    return t == null ? null : t.hour * 60 + t.minute;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(apiClientProvider).put('/manager/schedule', body: {
        'storeId': 'st-handam',
        'days': _days.map(
          (d, v) => MapEntry(
            '$d',
            v == null ? null : {'open': v.open, 'close': v.close},
          ),
        ),
      },);
      if (mounted) {
        KoraSnackbar.show(context, S.t('common.saved'));
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(leading: const BackButton()),
        body: const KoraLoadingState(),
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(S.t('schedule.title')),
      ),
      body: ListView.separated(
        padding: AppSpacing.screenPadding,
        itemCount: 7,
        separatorBuilder: (_, __) =>
            const SizedBox(height: AppSpacing.sm),
        itemBuilder: (_, d) {
          final day = _days[d];
          final open = day != null;
          return KoraCard(
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Text(
                    S.t('schedule.d$d'),
                    style: AppTypography.label,
                  ),
                ),
                const Spacer(),
                if (open) ...[
                  _TimeChip(
                    label: _fmt(day.open),
                    onTap: () async {
                      final t = await _pick(day.open);
                      if (t != null) {
                        setState(() => _days[d] =
                            (open: t, close: day.close),);
                      }
                    },
                  ),
                  Text(' — ', style: AppTypography.caption),
                  _TimeChip(
                    label: _fmt(day.close),
                    onTap: () async {
                      final t = await _pick(day.close);
                      if (t != null) {
                        setState(() => _days[d] =
                            (open: day.open, close: t),);
                      }
                    },
                  ),
                ] else
                  Text(S.t('schedule.closed'),
                      style: AppTypography.caption,),
                const SizedBox(width: AppSpacing.sm),
                Switch(
                  value: open,
                  activeThumbColor: KoraColors.primary,
                  onChanged: (v) => setState(() {
                    _days[d] =
                        v ? (open: 10 * 60, close: 21 * 60) : null;
                  }),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: AppSpacing.screenPadding,
          child: KoraButton(
            label: S.t('common.save'),
            loading: _saving,
            onPressed: _save,
          ),
        ),
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: AppSpacing.xs,),
        decoration: BoxDecoration(
          color: KoraColors.selected,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Text(label,
            style: AppTypography.label
                .copyWith(color: KoraColors.primary),),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Image editor (§29–30): rotate / brightness / contrast / saturation,
// hold-to-compare, baked PNG via RepaintBoundary. Original is never
// mutated — the edited render is saved as a new file.
// ---------------------------------------------------------------------------

class ProductImageEditor extends StatefulWidget {
  const ProductImageEditor({super.key});

  /// Returns the baked file path (or null).
  static Future<String?> show(BuildContext context) =>
      Navigator.of(context).push<String?>(
        MaterialPageRoute(
            builder: (_) => const ProductImageEditor(),),
      );

  @override
  State<ProductImageEditor> createState() => _ProductImageEditorState();
}

class _ProductImageEditorState extends State<ProductImageEditor> {
  final _captureKey = GlobalKey();
  Uint8List? _bytes;
  int _quarterTurns = 0;
  double _brightness = 0; // -1..1
  double _contrast = 1; // 0..2
  double _saturation = 1; // 0..2
  bool _comparing = false;
  bool _saving = false;

  Future<void> _pick() async {
    try {
      final x = await ImagePicker()
          .pickImage(source: ImageSource.gallery, maxWidth: 1600);
      if (x != null) {
        setState(() => _bytes = null); // reset while reading
        final b = await x.readAsBytes();
        setState(() => _bytes = b);
      }
    } catch (_) {
      if (mounted) {
        KoraSnackbar.show(context, S.t('chat.photo_unavailable'));
      }
    }
  }

  List<double> get _matrix {
    // saturation
    const rw = 0.2126, gw = 0.7152, bw = 0.0722;
    final s = _saturation;
    final sat = <double>[
      rw + (1 - rw) * s, gw - gw * s, bw - bw * s, 0, 0,
      rw - rw * s, gw + (1 - gw) * s, bw - bw * s, 0, 0,
      rw - rw * s, gw - gw * s, bw + (1 - bw) * s, 0, 0,
      0, 0, 0, 1, 0,
    ];
    // contrast * brightness (offset in 0..255 space)
    final c = _contrast;
    final off = _brightness * 255 + (1 - c) * 128;
    return <double>[
      sat[0] * c, sat[1] * c, sat[2] * c, 0, off,
      sat[5] * c, sat[6] * c, sat[7] * c, 0, off,
      sat[10] * c, sat[11] * c, sat[12] * c, 0, off,
      0, 0, 0, 1, 0,
    ];
  }

  Future<void> _save() async {
    if (_bytes == null) return;
    setState(() => _saving = true);
    try {
      final boundary = _captureKey.currentContext!
          .findRenderObject()! as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 2);
      final data =
          await img.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      final uri = await koraSavePng(
          data.buffer.asUint8List(), 'kora_edit',);
      if (mounted) Navigator.of(context).pop(uri);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _reset() => setState(() {
        _quarterTurns = 0;
        _brightness = 0;
        _contrast = 1;
        _saturation = 1;
      });

  @override
  void initState() {
    super.initState();
    _pick();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KoraColors.background,
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(S.t('editor.title')),
        actions: [
          IconButton(
            tooltip: S.t('editor.pick'),
            icon: const Icon(AppIcons.gallery),
            onPressed: _pick,
          ),
          IconButton(
            tooltip: S.t('editor.reset'),
            icon: const Icon(AppIcons.refresh),
            onPressed: _reset,
          ),
        ],
      ),
      body: _bytes == null
          ? const KoraLoadingState()
          : Column(
              children: [
                Expanded(
                  child: Center(
                    child: GestureDetector(
                      onLongPressStart: (_) =>
                          setState(() => _comparing = true),
                      onLongPressEnd: (_) =>
                          setState(() => _comparing = false),
                      child: RepaintBoundary(
                        key: _captureKey,
                        child: Container(
                          color: KoraColors.white,
                          child: _comparing
                              ? Image.memory(_bytes!,
                                  fit: BoxFit.contain,)
                              : ColorFiltered(
                                  colorFilter:
                                      ColorFilter.matrix(_matrix),
                                  child: RotatedBox(
                                    quarterTurns: _quarterTurns,
                                    child: Image.memory(
                                      _bytes!,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  padding: AppSpacing.screenPadding,
                  color: KoraColors.surface,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          _ToolIcon(
                            icon: AppIcons.rotate,
                            label: S.t('editor.rotate'),
                            onTap: () => setState(() =>
                                _quarterTurns =
                                    (_quarterTurns + 1) % 4,),
                          ),
                          const Spacer(),
                          Text(
                            S.t('editor.compare_hint'),
                            style: AppTypography.caption,
                          ),
                        ],
                      ),
                      _Slider(
                        icon: AppIcons.brightness,
                        label: S.t('editor.brightness'),
                        value: _brightness,
                        min: -0.5,
                        max: 0.5,
                        onChanged: (v) =>
                            setState(() => _brightness = v),
                      ),
                      _Slider(
                        icon: AppIcons.contrast,
                        label: S.t('editor.contrast'),
                        value: _contrast,
                        min: 0.5,
                        max: 1.8,
                        onChanged: (v) =>
                            setState(() => _contrast = v),
                      ),
                      _Slider(
                        icon: AppIcons.palette,
                        label: S.t('editor.saturation'),
                        value: _saturation,
                        min: 0,
                        max: 2,
                        onChanged: (v) =>
                            setState(() => _saturation = v),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      KoraButton(
                        label: S.t('editor.apply'),
                        loading: _saving,
                        onPressed: _save,
                      ),
                      SizedBox(
                          height: MediaQuery.of(context)
                              .viewPadding
                              .bottom,),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: KoraColors.primary),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
            width: 76,
            child: Text(label, style: AppTypography.caption),),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            activeColor: KoraColors.primary,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _ToolIcon extends StatelessWidget {
  const _ToolIcon(
      {required this.icon, required this.label,
       required this.onTap,});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: KoraColors.selected,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: KoraColors.primary, size: 20),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(label, style: AppTypography.caption),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Card generator (§31) — KORA templates rendered → PNG → product image.
// ---------------------------------------------------------------------------

enum KoraCardTemplate { clean, sale, premium }

class CardGeneratorScreen extends StatefulWidget {
  const CardGeneratorScreen({super.key});

  /// Returns the generated card file path (file://…) or null.
  static Future<String?> show(BuildContext context) =>
      Navigator.of(context).push<String?>(
        MaterialPageRoute(
            builder: (_) => const CardGeneratorScreen(),),
      );

  @override
  State<CardGeneratorScreen> createState() =>
      _CardGeneratorScreenState();
}

class _CardGeneratorScreenState extends State<CardGeneratorScreen> {
  final _captureKey = GlobalKey();
  final _name = TextEditingController();
  final _brand = TextEditingController();
  final _price = TextEditingController();
  final _oldPrice = TextEditingController();
  KoraCardTemplate _template = KoraCardTemplate.clean;
  Uint8List? _imageBytes;
  bool _saving = false;

  Future<void> _pick() async {
    try {
      final x = await ImagePicker()
          .pickImage(source: ImageSource.gallery, maxWidth: 1200);
      if (x != null) {
        final b = await x.readAsBytes();
        setState(() => _imageBytes = b);
      }
    } catch (_) {/* picker unavailable */}
  }

  Future<void> _export() async {
    setState(() => _saving = true);
    try {
      final boundary = _captureKey.currentContext!
          .findRenderObject()! as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 3);
      final data =
          await img.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      final uri = await koraSavePng(
          data.buffer.asUint8List(), 'kora_card',);
      if (mounted) Navigator.of(context).pop(uri);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(S.t('cardgen.title')),
      ),
      body: ListView(
        padding: AppSpacing.screenPadding,
        children: [
          Center(
            child: RepaintBoundary(
              key: _captureKey,
              child: SizedBox(
                width: 300,
                height: 375, // 4:5
                child: _TemplateCard(
                  template: _template,
                  name: _name.text.isEmpty
                      ? S.t('admin.product_name')
                      : _name.text,
                  brand: _brand.text,
                  price: _price.text,
                  oldPrice: _oldPrice.text,
                  imageBytes: _imageBytes,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              for (final t in KoraCardTemplate.values) ...[
                Expanded(
                  child: _TemplateChip(
                    label: switch (t) {
                      KoraCardTemplate.clean => 'KORA Clean',
                      KoraCardTemplate.sale => 'KORA Sale',
                      KoraCardTemplate.premium => 'KORA Premium',
                    },
                    selected: _template == t,
                    onTap: () => setState(() => _template = t),
                  ),
                ),
                if (t != KoraCardTemplate.values.last)
                  const SizedBox(width: AppSpacing.sm),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          KoraOutlinedButton(
            label: S.t('admin.photo_add'),
            icon: AppIcons.camera,
            onPressed: _pick,
          ),
          const SizedBox(height: AppSpacing.sm),
          KoraTextField(
            controller: _name,
            hint: S.t('admin.product_name'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.sm),
          KoraTextField(
            controller: _brand,
            hint: S.t('cardgen.brand'),
            onChanged: (_) => setState(() {}),
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
                  onChanged: (_) => setState(() {}),
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
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          KoraButton(
            label: S.t('cardgen.export'),
            loading: _saving,
            onPressed: _export,
          ),
        ],
      ),
    );
  }
}

class _TemplateChip extends StatelessWidget {
  const _TemplateChip(
      {required this.label, required this.selected,
       required this.onTap,});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? KoraColors.primary : KoraColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? KoraColors.primary : KoraColors.softBorderC,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: AppTypography.label.copyWith(
            color: selected ? KoraColors.white : KoraColors.textPrimaryC,
          ),
        ),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.name,
    required this.brand,
    required this.price,
    required this.oldPrice,
    this.imageBytes,
  });

  final KoraCardTemplate template;
  final String name;
  final String brand;
  final String price;
  final String oldPrice;
  final Uint8List? imageBytes;

  Widget get _img => Container(
        decoration: const BoxDecoration(
          gradient: KoraColors.softGradient,
        ),
        child: imageBytes == null
            ? const Center(
                child: Icon(AppIcons.gallery,
                    color: KoraColors.softPurple, size: 40,),)
            : Image.memory(
                imageBytes!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(AppIcons.gallery,
                      color: KoraColors.softPurple, size: 40,),
                ),
              ),
      );

  @override
  Widget build(BuildContext context) {
    final discount = _discountPct();
    return switch (template) {
      KoraCardTemplate.clean => _clean(discount),
      KoraCardTemplate.sale => _sale(discount),
      KoraCardTemplate.premium => _premium(discount),
    };
  }

  int? _discountPct() {
    final p = int.tryParse(price);
    final o = int.tryParse(oldPrice);
    if (p == null || o == null || o <= p) return null;
    return ((o - p) / o * 100).round();
  }

  Widget _priceBlock({Color? color}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (oldPrice.isNotEmpty)
            Text(
              '$oldPrice ₸',
              style: AppTypography.caption.copyWith(
                decoration: TextDecoration.lineThrough,
                color: KoraColors.placeholderC,
              ),
            ),
          Text(
            price.isEmpty ? '0 ₸' : '$price ₸',
            style: AppTypography.titleLarge.copyWith(
              color: color ?? KoraColors.textPrimaryC,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      );

  Widget _clean(int? discount) => Container(
        decoration: BoxDecoration(
          color: KoraColors.white,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppRadius.lg),),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _img,
                    if (discount != null)
                      Positioned(
                        top: 10,
                        left: 10,
                        child: _Badge('−$discount%'),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (brand.isNotEmpty)
                    Text(brand.toUpperCase(),
                        style: AppTypography.overline.copyWith(
                          color: KoraColors.primary,
                          fontSize: 9,
                        ),),
                  Text(name,
                      style: AppTypography.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,),
                  const SizedBox(height: 4),
                  _priceBlock(),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _sale(int? discount) => Container(
        decoration: BoxDecoration(
          gradient: KoraColors.primaryGradient,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        padding: const EdgeInsets.all(3),
        child: Container(
          decoration: BoxDecoration(
            color: KoraColors.white,
            borderRadius: BorderRadius.circular(AppRadius.lg - 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppRadius.lg - 2),),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _img,
                      Positioned(
                        top: 10,
                        left: 10,
                        child: _Badge(discount != null
                            ? '−$discount%'
                            : 'SALE',),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(
                  color: KoraColors.veryLightPurple,
                  borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(AppRadius.lg - 2),),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: AppTypography.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,),
                    const SizedBox(height: 4),
                    _priceBlock(color: KoraColors.primary),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _premium(int? discount) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF241F3D),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppRadius.lg),),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _img,
                    if (discount != null)
                      Positioned(
                        top: 10,
                        left: 10,
                        child: _Badge('−$discount%'),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (brand.isNotEmpty)
                    Text(brand.toUpperCase(),
                        style: AppTypography.overline.copyWith(
                          color: KoraColors.softPurple,
                          fontSize: 9,
                        ),),
                  Text(name,
                      style: AppTypography.label
                          .copyWith(color: KoraColors.white),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,),
                  const SizedBox(height: 4),
                  _priceBlock(color: KoraColors.white),
                ],
              ),
            ),
          ],
        ),
      );
}

class _Badge extends StatelessWidget {
  const _Badge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: KoraColors.primary,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          color: KoraColors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Promotion Builder (§28) — type → conditions → scope → preview → publish.
// ---------------------------------------------------------------------------

enum _PromoType { percent, fixed, bogo, firstOrder }

class PromotionBuilderScreen extends ConsumerStatefulWidget {
  const PromotionBuilderScreen({super.key});

  static Future<void> show(BuildContext context) =>
      Navigator.of(context).push(
        MaterialPageRoute(
            builder: (_) => const PromotionBuilderScreen(),),
      );

  @override
  ConsumerState<PromotionBuilderScreen> createState() =>
      _PromotionBuilderScreenState();
}

class _PromotionBuilderScreenState
    extends ConsumerState<PromotionBuilderScreen> {
  int _step = 0;
  _PromoType _type = _PromoType.percent;
  final _value = TextEditingController(text: '10');
  final _minOrder = TextEditingController();
  final _code = TextEditingController();
  String? _productId;
  bool _saving = false;

  String get _typeName => switch (_type) {
        _PromoType.percent => '−${_value.text}%',
        _PromoType.fixed => '−${_value.text} ₸',
        _PromoType.bogo => '2+1',
        _PromoType.firstOrder => S.t('promobuilder.first_order'),
      };

  Future<void> _publish() async {
    setState(() => _saving = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.post('/admin/promotions', body: {
        'title': _typeName,
        'subtitle': _minOrder.text.isEmpty
            ? null
            : S.t('promo.min_order', {'amount': '${_minOrder.text} ₸'}),
        'discountPercent':
            _type == _PromoType.percent ? int.tryParse(_value.text) : null,
        if (_code.text.isNotEmpty) 'code': _code.text.toUpperCase(),
        if (_productId != null) 'productId': _productId,
      },);
      if (_code.text.isNotEmpty) {
        await api.post('/admin/promo-codes', body: {
          'code': _code.text.trim().toUpperCase(),
          if (_type == _PromoType.fixed)
            'discountTiyn': (int.tryParse(_value.text) ?? 0) * 100,
          if (_type == _PromoType.percent || _type == _PromoType.firstOrder)
            'percent': int.tryParse(_value.text) ?? 0,
          if (_type == _PromoType.bogo) 'bogo': true,
          if (_type == _PromoType.firstOrder) 'firstOrder': true,
          'minOrderTiyn': (int.tryParse(_minOrder.text) ?? 0) * 100,
          if (_productId != null) 'productId': _productId,
        },);
      }
      if (mounted) {
        KoraSnackbar.show(context, S.t('promobuilder.published'));
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(S.t('promobuilder.title')),
      ),
      body: Stepper(
        currentStep: _step,
        onStepContinue: () {
          if (_step < 3) {
            setState(() => _step++);
          } else {
            _publish();
          }
        },
        onStepCancel: () {
          if (_step > 0) setState(() => _step--);
        },
        controlsBuilder: (context, d) => Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: KoraButton(
                  label: _step == 3
                      ? S.t('promobuilder.publish')
                      : S.t('common.next'),
                  loading: _saving,
                  onPressed: d.onStepContinue,
                ),
              ),
              if (_step > 0) ...[
                const SizedBox(width: AppSpacing.sm),
                KoraGhostButton(
                    label: S.t('common.back'),
                    onPressed: d.onStepCancel,),
              ],
            ],
          ),
        ),
        steps: [
          // Step 1 — type
          Step(
            title: Text(S.t('promobuilder.step_type')),
            isActive: _step >= 0,
            content: RadioGroup<_PromoType>(
              groupValue: _type,
              onChanged: (v) =>
                  setState(() => _type = v ?? _PromoType.percent),
              child: Column(
                children: [
                  for (final t in _PromoType.values)
                    RadioListTile<_PromoType>(
                      title: Text(switch (t) {
                        _PromoType.percent =>
                          S.t('promobuilder.t_percent'),
                        _PromoType.fixed => S.t('promobuilder.t_fixed'),
                        _PromoType.bogo => S.t('promobuilder.t_bogo'),
                        _PromoType.firstOrder =>
                          S.t('promobuilder.t_first'),
                      },),
                      value: t,
                      activeColor: KoraColors.primary,
                    ),
                ],
              ),
            ),
          ),
          // Step 2 — conditions
          Step(
            title: Text(S.t('promobuilder.step_conditions')),
            isActive: _step >= 1,
            content: Column(
              children: [
                if (_type != _PromoType.bogo)
                  KoraTextField(
                    controller: _value,
                    hint: _type == _PromoType.fixed
                        ? S.t('admin.discount_kzt')
                        : S.t('admin.promo_percent'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                  ),
                const SizedBox(height: AppSpacing.sm),
                KoraTextField(
                  controller: _minOrder,
                  hint: S.t('admin.min_order_kzt'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                KoraTextField(
                  controller: _code,
                  hint: S.t('admin.code_field'),
                ),
              ],
            ),
          ),
          // Step 3 — scope (product)
          Step(
            title: Text(S.t('promobuilder.step_scope')),
            isActive: _step >= 2,
            content: FutureBuilder<List<Product>>(
              future:
                  ref.read(managerRepoProvider).products(),
              builder: (context, snap) {
                final products = snap.data ?? const <Product>[];
                return DropdownButtonFormField<String>(
                  initialValue: _productId,
                  decoration: InputDecoration(
                      labelText: S.t('admin.promo_scope'),),
                  items: [
                    DropdownMenuItem(
                        child: Text(S.t('admin.any_product')),),
                    for (final p in products)
                      DropdownMenuItem(
                          value: p.id, child: Text(p.name),),
                  ],
                  onChanged: (v) => setState(() => _productId = v),
                );
              },
            ),
          ),
          // Step 4 — preview
          Step(
            title: Text(S.t('promobuilder.step_preview')),
            isActive: _step >= 3,
            content: Container(
              width: double.infinity,
              padding: AppSpacing.cardPadding,
              decoration: const BoxDecoration(
                gradient: KoraColors.primaryGradient,
                borderRadius: AppRadius.card,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_typeName,
                      style: AppTypography.titleLarge
                          .copyWith(color: KoraColors.white),),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    [
                      if (_code.text.isNotEmpty)
                        _code.text.toUpperCase(),
                      if (_minOrder.text.isNotEmpty)
                        S.t('promo.min_order',
                            {'amount': '${_minOrder.text} ₸'},),
                    ].join(' · '),
                    style: AppTypography.caption
                        .copyWith(color: KoraColors.lightPurple),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
