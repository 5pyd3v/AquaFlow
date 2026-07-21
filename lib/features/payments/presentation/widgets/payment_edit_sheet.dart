import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/extensions/num_extensions.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../domain/entities/payment_amendment_entity.dart';
import '../../domain/entities/payment_transaction_entity.dart';
import '../providers/payment_providers.dart';

/// Bottom sheet letting a rider correct or remove a payment.
///
/// While the payment is still unsettled the change is applied directly.
/// Once its cash is inside a verified settlement, the same UI instead
/// files an amendment request for the vendor to approve — a reason is
/// always required, and nothing is ever hard-deleted.
class PaymentEditSheet extends ConsumerStatefulWidget {
  final PaymentTransactionEntity payment;
  const PaymentEditSheet({super.key, required this.payment});

  static Future<bool?> show(BuildContext context, PaymentTransactionEntity payment) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PaymentEditSheet(payment: payment),
    );
  }

  @override
  ConsumerState<PaymentEditSheet> createState() => _PaymentEditSheetState();
}

class _PaymentEditSheetState extends ConsumerState<PaymentEditSheet> {
  late final TextEditingController _amountController;
  final _reasonController = TextEditingController();
  bool _delete = false;
  bool _busy = false;

  bool get _settled => widget.payment.settled;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(text: widget.payment.amount.toString());
  }

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A reason is required'), backgroundColor: AppColors.error),
      );
      return;
    }
    final newAmount = int.tryParse(_amountController.text.trim()) ?? 0;
    setState(() => _busy = true);
    final controller = ref.read(paymentControllerProvider.notifier);

    final result = await () {
      if (_settled) {
        return controller.requestAmendment(
          transactionId: widget.payment.id,
          action: _delete ? AmendmentAction.delete : AmendmentAction.edit,
          amount: _delete ? null : newAmount,
          reason: reason,
        );
      }
      return _delete
          ? controller.deletePayment(transactionId: widget.payment.id, reason: reason)
          : controller.editPayment(
              transactionId: widget.payment.id, newAmount: newAmount, reason: reason);
    }();

    if (!mounted) return;
    setState(() => _busy = false);
    result.fold(
      (f) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(f.message), backgroundColor: AppColors.error),
      ),
      (_) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_settled
                ? 'Amendment request sent to vendor'
                : _delete
                    ? 'Payment deleted'
                    : 'Payment updated'),
            backgroundColor: AppColors.success,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 18),
          Text(_delete ? 'Delete payment' : 'Edit payment',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Current: ${widget.payment.amount.toCurrency}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          if (_settled) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: AppColors.warning),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This payment is already settled. Your change will be sent to the vendor for approval.',
                      style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (!_delete) ...[
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'New amount',
                prefixText: 'Rs. ',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _reasonController,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Reason (required)',
              hintText: 'e.g. customer disputed the amount',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Delete this payment instead'),
            value: _delete,
            onChanged: (v) => setState(() => _delete = v),
          ),
          const SizedBox(height: 8),
          PrimaryButton(
            label: _settled
                ? 'Request approval'
                : _delete
                    ? 'Delete payment'
                    : 'Save changes',
            isLoading: _busy,
            onPressed: _busy ? null : _submit,
            backgroundColor: _delete ? AppColors.error : null,
          ),
        ],
      ),
    );
  }
}
