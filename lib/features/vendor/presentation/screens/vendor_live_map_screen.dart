import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/loaders/state_views.dart';
import '../../domain/entities/vendor_rider_entity.dart';
import '../providers/vendor_providers.dart';

class VendorLiveMapScreen extends ConsumerStatefulWidget {
  const VendorLiveMapScreen({super.key});

  @override
  ConsumerState<VendorLiveMapScreen> createState() => _VendorLiveMapScreenState();
}

class _VendorLiveMapScreenState extends ConsumerState<VendorLiveMapScreen> {
  GoogleMapController? _mapController;
  bool _initialFitDone = false;

  static const _fallbackCenter = LatLng(33.7551, 72.2831);

  void _fitToRiders(List<LatLng> points) {
    if (_mapController == null || points.isEmpty) return;

    if (points.length == 1) {
      _mapController!.animateCamera(CameraUpdate.newLatLngZoom(points.first, 15));
      return;
    }

    final lats = points.map((p) => p.latitude);
    final lngs = points.map((p) => p.longitude);
    final bounds = LatLngBounds(
      southwest: LatLng(lats.reduce((a, b) => a < b ? a : b), lngs.reduce((a, b) => a < b ? a : b)),
      northeast: LatLng(lats.reduce((a, b) => a > b ? a : b), lngs.reduce((a, b) => a > b ? a : b)),
    );
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 60));
  }

  @override
  Widget build(BuildContext context) {
    final ridersAsync = ref.watch(vendorRidersProvider);
    final locationsAsync = ref.watch(riderLocationsStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Live Riders')),
      body: ridersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorStateView(message: e.toString(), onRetry: () => ref.invalidate(vendorRidersProvider)),
        data: (riders) {
          final riderById = {for (final r in riders) r.id: r};
          final locations = locationsAsync.valueOrNull ?? [];

          // Only show riders who are approved, NOT offline, and have
          // fresh location data. Unapproved (pending) riders are hidden
          // until their vendor approves them.
          final freshLocations = locations.where((loc) {
            if (loc.isStale) return false;
            final rider = riderById[loc.riderId];
            if (rider == null) return false;
            if (!rider.isApproved) return false;
            return rider.status != RiderStatus.offline;
          }).toList();

          final markers = freshLocations.map((loc) {
            final rider = riderById[loc.riderId]!;
            return Marker(
              markerId: MarkerId(loc.riderId),
              position: LatLng(loc.latitude, loc.longitude),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
              rotation: loc.headingDegrees ?? 0,
              infoWindow: InfoWindow(title: rider.fullName, snippet: rider.status.label),
            );
          }).toSet();

          final riderPoints = markers.map((m) => m.position).toList();

          final initialTarget = riderPoints.isNotEmpty ? riderPoints.first : _fallbackCenter;

          return Stack(
            children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(target: initialTarget, zoom: 15),
                onMapCreated: (controller) {
                  _mapController = controller;
                  if (!_initialFitDone && riderPoints.isNotEmpty) {
                    _initialFitDone = true;
                    Future.delayed(const Duration(milliseconds: 500), () {
                      _fitToRiders(riderPoints);
                    });
                  }
                },
                markers: markers,
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: true,
                mapType: MapType.normal,
              ),
              if (markers.isEmpty)
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: _InfoBanner(riderCount: riders.length),
                ),
              Positioned(
                bottom: 16,
                left: 16,
                right: 16,
                child: _RiderCountBar(total: riders.length, online: markers.length),
              ),
              if (markers.isNotEmpty)
                Positioned(
                  top: 16,
                  right: 16,
                  child: FloatingActionButton.small(
                    heroTag: 'recenter',
                    backgroundColor: AppColors.surface,
                    onPressed: () => _fitToRiders(riderPoints),
                    child: const Icon(Icons.my_location_rounded, color: AppColors.primary),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final int riderCount;
  const _InfoBanner({required this.riderCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.textTertiary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              riderCount == 0
                  ? 'Link a rider from the Riders screen to see them here.'
                  : 'No riders are currently broadcasting a live location — they need to go on shift first.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _RiderCountBar extends StatelessWidget {
  final int total;
  final int online;
  const _RiderCountBar({required this.total, required this.online});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text('$online of $total riders live', style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}
