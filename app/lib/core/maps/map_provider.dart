import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../theme/app_animations.dart';
import '../theme/app_icons.dart';
import '../theme/app_metrics.dart';
import '../theme/app_typography.dart';
import '../theme/kora_colors.dart';
import '../widgets/misc.dart';

/// Geographic point used across the app (delivery, courier, store).
class GeoPoint {
  const GeoPoint({required this.lat, required this.lng});

  final double lat;
  final double lng;

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};

  factory GeoPoint.fromJson(Map<String, dynamic> j) => GeoPoint(
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      other is GeoPoint && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);
}

enum KoraMarkerKind { store, customer, courier, deliveryPoint }

class KoraMarker {
  const KoraMarker({
    required this.point,
    required this.kind,
    this.label,
  });

  final GeoPoint point;
  final KoraMarkerKind kind;
  final String? label;
}

/// Map abstraction. Today it renders a functional stylized city map
/// (pan/zoom gestures, markers, tap-to-pick). To switch to a real SDK
/// (Yandex MapKit for KZ), implement the same widget contract inside
/// `KoraMap` — no feature code changes needed.
class KoraMap extends StatefulWidget {
  const KoraMap({
    super.key,
    required this.center,
    this.markers = const [],
    this.route = const [],
    this.onTapPick,
    this.picked,
    this.followMarker,
    this.interactive = true,
  });

  final GeoPoint center;
  final List<KoraMarker> markers;

  /// Ordered polyline points (store → customer etc).
  final List<GeoPoint> route;

  /// When set, tapping the map reports a picked coordinate.
  final ValueChanged<GeoPoint>? onTapPick;
  final GeoPoint? picked;

  /// Marker kind to keep centered while its position streams in.
  final KoraMarkerKind? followMarker;
  final bool interactive;

  /// Rough px-per-degree scale at zoom 1 for the stub renderer.
  static const double _scale = 12000;

  @override
  State<KoraMap> createState() => _KoraMapState();
}

class _KoraMapState extends State<KoraMap> {
  Offset _pan = Offset.zero;
  double _zoom = 1;

  Offset _project(GeoPoint p, Size size) {
    final dx = (p.lng - widget.center.lng) * KoraMap._scale * _zoom;
    final dy = -(p.lat - widget.center.lat) * KoraMap._scale * _zoom;
    return Offset(size.width / 2 + dx + _pan.dx, size.height / 2 + dy + _pan.dy);
  }

  GeoPoint _unproject(Offset o, Size size) {
    final dx = o.dx - size.width / 2 - _pan.dx;
    final dy = o.dy - size.height / 2 - _pan.dy;
    return GeoPoint(
      lat: widget.center.lat - dy / (KoraMap._scale * _zoom),
      lng: widget.center.lng + dx / (KoraMap._scale * _zoom),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: GestureDetector(
            onScaleStart: widget.interactive ? (_) {} : null,
            onScaleUpdate: widget.interactive
                ? (d) => setState(() {
                      _pan += d.focalPointDelta;
                      _zoom = (_zoom * d.scale).clamp(0.6, 3.0);
                    })
                : null,
            onTapUp: widget.onTapPick == null
                ? null
                : (d) =>
                    widget.onTapPick!(_unproject(d.localPosition, size)),
            child: Container(
              color: KoraColors.surfaceAlt,
              child: CustomPaint(
                painter: _CityPainter(
                  pan: _pan,
                  zoom: _zoom,
                  route: widget.route
                      .map((p) => _project(p, size))
                      .toList(),
                ),
                child: Stack(
                  children: [
                    for (final m in widget.markers)
                      _Marker(
                        position: _project(m.point, size),
                        marker: m,
                      ),
                    if (widget.picked != null)
                      _Marker(
                        position: _project(widget.picked!, size),
                        marker: KoraMarker(
                          point: widget.picked!,
                          kind: KoraMarkerKind.deliveryPoint,
                          label: S.t('map.point_label'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Marker extends StatelessWidget {
  const _Marker({required this.position, required this.marker});

  final Offset position;
  final KoraMarker marker;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (marker.kind) {
      KoraMarkerKind.store => (AppIcons.store, KoraColors.darkPurple),
      KoraMarkerKind.customer => (AppIcons.profile, KoraColors.softPurple),
      KoraMarkerKind.courier => (AppIcons.courier, KoraColors.primary),
      KoraMarkerKind.deliveryPoint =>
        (AppIcons.location, KoraColors.deepPurple),
    };
    // AnimatedPositioned gives smooth marker glide between GPS updates
    // (courier tracking) instead of teleporting.
    return AnimatedPositioned(
      duration: AppAnimations.normal,
      curve: AppAnimations.ease,
      left: position.dx - 20,
      top: position.dy - 40,
      child: KoraMapMarker(icon: icon, color: color, label: marker.label),
    );
  }
}

/// Stylized city grid + route polyline for the stub map.
class _CityPainter extends CustomPainter {
  _CityPainter({required this.pan, required this.zoom, required this.route});

  final Offset pan;
  final double zoom;
  final List<Offset> route;

  @override
  void paint(Canvas canvas, Size size) {
    final street = Paint()
      ..color = KoraColors.softBorderC
      ..strokeWidth = 1.2;
    final block = Paint()
      ..color = KoraColors.selected.withValues(alpha: 0.35);

    // City blocks grid.
    const cell = 90.0;
    final offX = pan.dx % (cell * zoom);
    final offY = pan.dy % (cell * zoom);
    for (double x = offX - cell * zoom; x < size.width; x += cell * zoom) {
      for (double y = offY - cell * zoom;
          y < size.height;
          y += cell * zoom) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              x + 6,
              y + 6,
              cell * zoom - 12,
              cell * zoom - 12,
            ),
            const Radius.circular(10),
          ),
          block,
        );
      }
    }
    // Street lines.
    for (double x = offX; x < size.width; x += cell * zoom) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), street);
    }
    for (double y = offY; y < size.height; y += cell * zoom) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), street);
    }
    // Route polyline.
    if (route.length >= 2) {
      final p = Paint()
        ..color = KoraColors.primary
        ..strokeWidth = 3.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final path = Path()..moveTo(route.first.dx, route.first.dy);
      for (final pt in route.skip(1)) {
        path.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(path, p);
    }
    // Hint label.
    final tp = TextPainter(
      text: TextSpan(
        text: 'KORA Map',
        style: AppTypography.caption,
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(size.width - tp.width - 10, size.height - 20));
  }

  @override
  bool shouldRepaint(_CityPainter old) =>
      old.pan != pan || old.zoom != zoom || old.route != route;
}
