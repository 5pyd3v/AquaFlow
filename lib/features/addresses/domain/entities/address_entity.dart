import 'package:equatable/equatable.dart';

enum AddressLabel {
  home,
  office,
  other;

  String get dbValue => name;
  String get display => switch (this) {
        AddressLabel.home => 'Home',
        AddressLabel.office => 'Office',
        AddressLabel.other => 'Other',
      };

  static AddressLabel fromDbValue(String value) {
    return AddressLabel.values.firstWhere(
      (l) => l.dbValue == value,
      orElse: () => AddressLabel.other,
    );
  }
}

class AddressEntity extends Equatable {
  final String id;
  final AddressLabel label;
  final String fullAddress;
  final double latitude;
  final double longitude;
  final String? landmark;
  final bool isDefault;

  const AddressEntity({
    required this.id,
    required this.label,
    required this.fullAddress,
    required this.latitude,
    required this.longitude,
    this.landmark,
    required this.isDefault,
  });

  @override
  List<Object?> get props =>
      [id, label, fullAddress, latitude, longitude, landmark, isDefault];
}
