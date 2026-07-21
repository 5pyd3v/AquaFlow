import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/extensions/num_extensions.dart';
import '../../../../shared/widgets/loaders/state_views.dart';
import '../../domain/entities/vendor_rider_entity.dart';
import '../providers/vendor_providers.dart';

/// Bottom sheet listing only *this vendor's* riders (linked via
/// `link_rider_to_vendor`), sorted nearest-first to the delivery
/// address using each rider's last broadcast location — so the
/// vendor's natural first tap is the rider who can actually get there
/// fastest, not just whoever is alphabetically first. Riders with no
/// recent location (never gone on shift, or stale >5 min) sort to the
/// bottom with a "location unknown" note rather than being hidden.
class RiderAssignmentSheet extends ConsumerWidget {
  final double destinationLat;
  final double destinationLng;

  const RiderAssignmentSheet({
    super.key,
    required this.destinationLat,
    required this.destinationLng,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ridersAsync = ref.watch(vendorRidersProvider);
    final locationsAsync = ref.watch(riderLocationsStreamProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(height: 16),
            Text('Assign a Rider', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Sorted by distance to the delivery address',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
              child: ridersAsync.when(
                loading: () => const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
                error: (e, _) => ErrorStateView(message: e.toString(), onRetry: () => ref.invalidate(vendorRidersProvider)),
                data: (riders) {
                  final available = riders.where((r) => r.status != RiderStatus.suspended).toList();
                  if (available.isEmpty) {
                    return const EmptyStateView(
                      title: 'No riders linked yet',
                      message: 'Add a rider from the Riders screen before assigning deliveries.',
                    );
                  }

                  final locations = locationsAsync.valueOrNull ?? [];
                  final locationByRiderId = {for (final loc in locations) loc.riderId: loc};

                  final entries = available.map((rider) {
                    final loc = locationByRiderId[rider.id];
                    final distanceKm = (loc != null && !loc.isStale)
                        ? LocationService.instance
                            .distanceInKm(destinationLat, destinationLng, loc.latitude, loc.longitude)
                        : null;
                    return (rider: rider, distanceKm: distanceKm);
                  }).toList()
                    ..sort((a, b) {
                      if (a.distanceKm == null && b.distanceKm == null) return 0;
                      if (a.distanceKm == null) return 1;
                      if (b.distanceKm == null) return -1;
                      return a.distanceKm!.compareTo(b.distanceKm!);
                    });

                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return _RiderOption(rider: entry.rider, distanceKm: entry.distanceKm, isNearest: index == 0 && entry.distanceKm != null);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RiderOption extends StatelessWidget {
  final VendorRiderEntity rider;
  final double? distanceKm;
  final bool isNearest;

  const _RiderOption({required this.rider, required this.distanceKm, required this.isNearest});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.of(context).pop(rider.id),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isNearest ? AppColors.success.withValues(alpha: 0.08) : AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(14),
          border: isNearest ? Border.all(color: AppColors.success.withValues(alpha: 0.4)) : null,
        ),
        child: Row(
          children: [
            const CircleAvatar(
              backgroundColor: AppColors.roleRider,
              child: Icon(Icons.two_wheeler_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(rider.fullName, style: Theme.of(context).textTheme.titleSmall),
                      if (isNearest) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.success, borderRadius: BorderRadius.circular(20)),
                          child: const Text('NEAREST', style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ],
                  ),
                  Text('${rider.status.label} · ${rider.totalDeliveries} deliveries',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  distanceKm != null ? distanceKm!.toDistanceLabel() : 'Location unknown',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: distanceKm != null ? AppColors.textPrimary : AppColors.textTertiary,
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.star_rounded, size: 12, color: AppColors.secondary),
                    Text(rider.rating.toStringAsFixed(1), style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
