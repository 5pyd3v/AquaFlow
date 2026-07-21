import 'package:equatable/equatable.dart';

enum VendorStatus {
  pending,
  approved,
  suspended,
  rejected;

  String get dbValue => name;

  String get label => switch (this) {
        VendorStatus.pending => 'Pending Approval',
        VendorStatus.approved => 'Approved',
        VendorStatus.suspended => 'Suspended',
        VendorStatus.rejected => 'Rejected',
      };

  static VendorStatus fromDbValue(String value) {
    return VendorStatus.values.firstWhere((s) => s.dbValue == value, orElse: () => VendorStatus.pending);
  }
}

class VendorEntity extends Equatable {
  final String id;
  final String profileId;
  final String? businessName;
  final VendorStatus status;
  final double rating;
  final int totalOrders;
  final String? address;
  final double? latitude;
  final double? longitude;
  final double deliveryRadiusKm;

  const VendorEntity({
    required this.id,
    required this.profileId,
    this.businessName,
    required this.status,
    required this.rating,
    required this.totalOrders,
    this.address,
    this.latitude,
    this.longitude,
    required this.deliveryRadiusKm,
  });

  bool get isApproved => status == VendorStatus.approved;

  @override
  List<Object?> get props =>
      [id, profileId, businessName, status, rating, totalOrders, address, latitude, longitude, deliveryRadiusKm];
}
