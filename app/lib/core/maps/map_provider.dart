import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/env.dart';
import '../l10n/app_strings.dart';
import '../theme/app_icons.dart';
import '../theme/app_metrics.dart';
import '../theme/app_typography.dart';
import '../theme/kora_colors.dart';
import '../widgets/misc.dart';

/// Geographic point used across delivery, courier, address and store flows.
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

/// Real interactive city map backed by configurable XYZ tiles.
/// Courier coordinates arrive through the existing realtime/GPS streams;
/// [followMarker] moves the camera as those coordinates change.
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
  final List<GeoPoint> route;
  final ValueChanged<GeoPoint>? onTapPick;
  final GeoPoint? picked;
  final KoraMarkerKind? followMarker;
  final bool interactive;

  @override
  State<KoraMap> createState() => _KoraMapState();
}

class _KoraMapState extends State<KoraMap> {
  final _controller = MapController();

  LatLng _latLng(GeoPoint point) => LatLng(point.lat, point.lng);

  @override
  void didUpdateWidget(covariant KoraMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.followMarker == null) return;
    final marker = widget.markers
        .where((item) => item.kind == widget.followMarker)
        .firstOrNull;
    final oldMarker = oldWidget.markers
        .where((item) => item.kind == widget.followMarker)
        .firstOrNull;
    if (marker != null && marker.point != oldMarker?.point) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _controller.move(_latLng(marker.point), _controller.camera.zoom);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mapMarkers = [
      ...widget.markers,
      if (widget.picked != null)
        KoraMarker(
          point: widget.picked!,
          kind: KoraMarkerKind.deliveryPoint,
          label: S.t('map.point_label'),
        ),
    ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: FlutterMap(
        mapController: _controller,
        options: MapOptions(
          initialCenter: _latLng(widget.center),
          initialZoom: 14,
          minZoom: 3,
          maxZoom: 19,
          interactionOptions: InteractionOptions(
            flags:
                widget.interactive ? InteractiveFlag.all : InteractiveFlag.none,
          ),
          onTap: widget.onTapPick == null
              ? null
              : (_, point) => widget.onTapPick!(
                    GeoPoint(lat: point.latitude, lng: point.longitude),
                  ),
        ),
        children: [
          TileLayer(
            urlTemplate: AppEnv.mapTileUrl,
            userAgentPackageName: 'kz.kora.kora',
            maxZoom: 19,
            tileProvider: NetworkTileProvider(),
          ),
          if (widget.route.length >= 2)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: widget.route.map(_latLng).toList(),
                  color: KoraColors.primary,
                  strokeWidth: 5,
                ),
              ],
            ),
          MarkerLayer(
            markers: mapMarkers.map(_marker).toList(),
          ),
          Positioned(
            right: 4,
            bottom: 2,
            child: Material(
              color: KoraColors.surface.withValues(alpha: 0.84),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: InkWell(
                onTap: () => launchUrl(
                  Uri.parse('https://www.openstreetmap.org/copyright'),
                  mode: LaunchMode.externalApplication,
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    '© OpenStreetMap',
                    style: AppTypography.caption.copyWith(fontSize: 9),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Marker _marker(KoraMarker marker) {
    final (icon, color) = switch (marker.kind) {
      KoraMarkerKind.store => (AppIcons.store, KoraColors.darkPurple),
      KoraMarkerKind.customer => (AppIcons.profile, KoraColors.softPurple),
      KoraMarkerKind.courier => (AppIcons.courier, KoraColors.primary),
      KoraMarkerKind.deliveryPoint => (
          AppIcons.location,
          KoraColors.deepPurple
        ),
    };
    return Marker(
      point: _latLng(marker.point),
      width: marker.label == null ? 48 : 132,
      height: 64,
      alignment: Alignment.topCenter,
      child: KoraMapMarker(icon: icon, color: color, label: marker.label),
    );
  }
}
