/// A rider's shift/availability status. Shared by the rider feature
/// (a rider's own profile) and the vendor feature (a vendor's view of
/// a rider it manages) — both map the same `riders.status` DB column,
/// so this lives once in `core/constants` instead of as two identical
/// enums that would silently drift apart.
enum RiderStatus {
  offline,
  available,
  onDelivery,
  suspended;

  String get dbValue => switch (this) {
        RiderStatus.offline => 'offline',
        RiderStatus.available => 'available',
        RiderStatus.onDelivery => 'on_delivery',
        RiderStatus.suspended => 'suspended',
      };

  String get label => switch (this) {
        RiderStatus.offline => 'Offline',
        RiderStatus.available => 'Available',
        RiderStatus.onDelivery => 'On Delivery',
        RiderStatus.suspended => 'Suspended',
      };

  static RiderStatus fromDbValue(String value) {
    return RiderStatus.values.firstWhere((s) => s.dbValue == value, orElse: () => RiderStatus.offline);
  }
}
