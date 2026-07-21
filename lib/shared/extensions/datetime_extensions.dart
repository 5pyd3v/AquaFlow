import 'package:intl/intl.dart';

extension DateTimeExtensions on DateTime {
  String get toDayMonth => DateFormat('d MMM').format(this);
  String get toDayMonthYear => DateFormat('d MMM, yyyy').format(this);
  String get toTime => DateFormat('h:mm a').format(this);
  String get toFullDateTime => DateFormat('d MMM yyyy, h:mm a').format(this);

  bool get isToday {
    final now = DateTime.now();
    return year == now.year && month == now.month && day == now.day;
  }

  bool get isYesterday {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return year == yesterday.year &&
        month == yesterday.month &&
        day == yesterday.day;
  }

  String get friendlyLabel {
    if (isToday) return 'Today, $toTime';
    if (isYesterday) return 'Yesterday, $toTime';
    return toFullDateTime;
  }
}
