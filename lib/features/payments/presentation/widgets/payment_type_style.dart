import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/payment_transaction_entity.dart';

/// Single source of truth for how each [PaymentType] is colored/iconed —
/// identical in every payment-timeline UI (vendor customer ledger,
/// customer order tracking), so those two never drift out of sync.
///
/// Deliberately does NOT include the label text: the two existing call
/// sites use slightly different wording for `PaymentType.credit`
/// ("Credit applied" vs "Wallet credit applied") and this extraction
/// must not silently change either screen's copy, so labels stay
/// defined locally at each call site.
extension PaymentTypeStyle on PaymentType {
  Color get color => switch (this) {
        PaymentType.full => AppColors.success,
        PaymentType.partial => AppColors.warning,
        PaymentType.over => AppColors.info,
        PaymentType.credit => const Color(0xFF7C3AED),
        PaymentType.refund => AppColors.error,
        PaymentType.adjustment => AppColors.textSecondary,
      };

  IconData get icon => switch (this) {
        PaymentType.full => Icons.check_circle_rounded,
        PaymentType.partial => Icons.pie_chart_rounded,
        PaymentType.over => Icons.account_balance_wallet_rounded,
        PaymentType.credit => Icons.card_giftcard_rounded,
        PaymentType.refund => Icons.reply_rounded,
        PaymentType.adjustment => Icons.tune_rounded,
      };
}
