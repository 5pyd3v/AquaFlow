import 'package:equatable/equatable.dart';

class RiderLocationEntity extends Equatable {
  final String riderId;
  final double latitude;
  final double longitude;
  final double? headingDegrees;
  final DateTime updatedAt;

  const RiderLocationEntity({
    required this.riderId,
    required this.latitude,
    required this.longitude,
    this.headingDegrees,
    required this.updatedAt,
  });

  factory RiderLocationEntity.fromJson(Map<String, dynamic> json) {
    final raw = json['updated_at']?.toString() ?? '';
    var parsed = DateTime.tryParse(raw);
    if (parsed != null && !parsed.isUtc) {
      parsed = parsed.toUtc();
    }
    return RiderLocationEntity(
      riderId: json['rider_id'] as String,
      latitude: (json['lat'] as num).toDouble(),
      longitude: (json['lng'] as num).toDouble(),
      headingDegrees: (json['heading'] as num?)?.toDouble(),
      updatedAt: parsed ?? DateTime.now().toUtc(),
    );
  }

  bool get isStale => DateTime.now().toUtc().difference(updatedAt) > const Duration(minutes: 5);

  @override
  List<Object?> get props => [riderId, latitude, longitude, headingDegrees, updatedAt];
}
