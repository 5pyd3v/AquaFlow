import '../../domain/entities/address_entity.dart';

/// `addresses.location` is a PostGIS `geography(Point,4326)` column.
/// Supabase returns it as GeoJSON when selected as `location`, or as
/// WKB hex if selected raw — we ask for it via an RPC-free approach by
/// selecting `st_x(location::geometry)`/`st_y(...)` aliases instead, so
/// the client never has to parse PostGIS binary formats.
class AddressModel extends AddressEntity {
  const AddressModel({
    required super.id,
    required super.label,
    required super.fullAddress,
    required super.latitude,
    required super.longitude,
    super.landmark,
    required super.isDefault,
  });

  factory AddressModel.fromJson(Map<String, dynamic> json) {
    return AddressModel(
      id: json['id'] as String,
      label: AddressLabel.fromDbValue(json['label'] as String? ?? 'other'),
      fullAddress: json['full_address'] as String? ?? '',
      latitude: (json['lat'] as num?)?.toDouble() ?? 0,
      longitude: (json['lng'] as num?)?.toDouble() ?? 0,
      landmark: json['landmark'] as String?,
      isDefault: json['is_default'] as bool? ?? false,
    );
  }
}
