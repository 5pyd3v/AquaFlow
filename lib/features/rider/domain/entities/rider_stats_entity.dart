import 'package:equatable/equatable.dart';

class RiderStatsEntity extends Equatable {
  final int todaysDeliveries;
  final int totalDeliveries;
  final double rating;

  /// Total COD collected across all delivered orders (lifetime)
  final double totalCodCollected;

  /// How much the rider still owes the vendor (collected - verified)
  final double codOutstanding;

  /// How much is pending verification (submitted but not verified)
  final double codPendingVerification;

  const RiderStatsEntity({
    required this.todaysDeliveries,
    required this.totalDeliveries,
    required this.rating,
    this.totalCodCollected = 0,
    this.codOutstanding = 0,
    this.codPendingVerification = 0,
  });

  @override
  List<Object?> get props => [
        todaysDeliveries,
        totalDeliveries,
        rating,
        totalCodCollected,
        codOutstanding,
        codPendingVerification,
      ];
}
