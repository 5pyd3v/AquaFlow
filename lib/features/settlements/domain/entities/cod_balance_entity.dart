import 'package:equatable/equatable.dart';

class CodBalanceEntity extends Equatable {
  final double outstanding;
  final double pending;
  final double totalSubmitted;
  final double totalVerified;
  final double totalCollected;

  const CodBalanceEntity({
    required this.outstanding,
    required this.pending,
    required this.totalSubmitted,
    required this.totalVerified,
    required this.totalCollected,
  });

  @override
  List<Object?> get props => [outstanding, pending, totalSubmitted, totalVerified, totalCollected];
}
