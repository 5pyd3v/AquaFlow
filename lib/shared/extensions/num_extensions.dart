import 'package:intl/intl.dart';

extension NumExtensions on num {
  String get toCurrency =>
      NumberFormat.currency(locale: 'en_PK', symbol: 'Rs. ', decimalDigits: 0)
          .format(this);

  String get toCompact => NumberFormat.compact().format(this);

  String toDistanceLabel() {
    if (this < 1) return '${(this * 1000).round()} m';
    return '${toStringAsFixed(1)} km';
  }
}
