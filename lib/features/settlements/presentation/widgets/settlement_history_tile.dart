import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/extensions/num_extensions.dart';
import '../../domain/entities/settlement_entity.dart';

class SettlementHistoryTile extends StatelessWidget {
  final SettlementEntity settlement;
  const SettlementHistoryTile({super.key, required this.settlement});

  @override
  Widget build(BuildContext context) {
    final isVerified = settlement.status == SettlementStatus.verified;
    final isExpired = settlement.status == SettlementStatus.expired;
    final statusColor = isVerified
        ? const Color(0xFF10B981)
        : isExpired
            ? AppColors.error
            : const Color(0xFFFF8F00);
    final statusLabel = isVerified
        ? 'Verified'
        : isExpired
            ? 'Expired'
            : 'Pending';
    final statusIcon = isVerified
        ? Icons.check_circle_rounded
        : isExpired
            ? Icons.cancel_rounded
            : Icons.hourglass_top_rounded;

    final date = settlement.verifiedAt ?? settlement.createdAt;
    final dateStr = '${date.day}/${date.month}/${date.year}';
    final timeStr =
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(statusIcon, color: statusColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  settlement.amount.toCurrency,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$dateStr  $timeStr',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                color: statusColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
