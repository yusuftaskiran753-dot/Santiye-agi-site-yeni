import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config.dart';

/// OpenStreetMap tabanlı harita. Yayında yoğun kullanım için kendi harita
/// sağlayıcınızın (MapTiler, Mapbox vb.) adresini `lib/config.dart` →
/// [AppConfig.tileUrl] alanına yazın.
class AppMap extends StatelessWidget {
  const AppMap({
    super.key,
    required this.center,
    required this.layers,
    this.zoom = 10,
    this.onTap,
    this.controller,
    this.onMapReady,
    this.onUserMove,
  });

  static const String tileUrl = AppConfig.tileUrl;
  static const String packageName = AppConfig.packageName;

  final LatLng center;
  final double zoom;
  final List<Widget> layers;
  final void Function(LatLng point)? onTap;
  final MapController? controller;
  final VoidCallback? onMapReady;
  final VoidCallback? onUserMove;

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: center,
        initialZoom: zoom,
        onMapReady: onMapReady,
        onPositionChanged: (_, hasGesture) {
          if (hasGesture) onUserMove?.call();
        },
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onTap: onTap == null ? null : (_, point) => onTap!(point),
      ),
      children: [
        TileLayer(urlTemplate: tileUrl, userAgentPackageName: packageName),
        ...layers,
        const SimpleAttributionWidget(source: Text(AppConfig.mapAttribution)),
      ],
    );
  }
}

class MapPin extends StatelessWidget {
  const MapPin({
    super.key,
    required this.icon,
    required this.color,
    this.size = 40,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.5),
    );
  }
}
