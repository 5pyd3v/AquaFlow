import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../shared/extensions/num_extensions.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../domain/entities/payment_amendment_entity.dart';
import '../../domain/entities/payment_transaction_entity.dart';
import '../providers/payment_providers.dart';

class RefundScreen extends ConsumerStatefulWidget {
  final PaymentTransactionEntity payment;
  const RefundScreen({super.key, required this.payment});

  @override
  ConsumerState<RefundScreen> createState() => _RefundScreenState();
}

class _RefundScreenState extends ConsumerState<RefundScreen> {
  late final TextEditingController _amountController;
  final _reasonController = TextEditingController();
  bool _submitting = false;

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

  int get _refundAmount => int.tryParse(_amountController.text.trim()) ?? 0;
  bool get _isSettled => widget.payment.settled;
  bool get _canSubmit =>
      !_submitting &&
      _refundAmount > 0 &&
      _refundAmount <= widget.payment.amount &&
      _reasonController.text.trim().isNotEmpty;

  Future<void> _submit() async {
    setState(() => _submitting = true);
    final controller = ref.read(paymentControllerProvider.notifier);

    if (_isSettled) {
      final result = await controller.requestAmendment(
        transactionId: widget.payment.id,
        action: AmendmentAction.refund,
        amount: _refundAmount,
        reason: _reasonController.text.trim(),
      );
      if (!mounted) return;
      setState(() => _submitting = false);
      result.fold(
        (failure) => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(failure.message), backgroundColor: AppColors.error),
        ),
        (_) {
          Navigator.of(context).pop(true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Refund request sent to vendor for approval'),
              backgroundColor: AppColors.info,
            ),
          );
        },
      );
    } else {
      final result = await controller.processRefund(
        transactionId: widget.payment.id,
        amount: _refundAmount,
        reason: _reasonController.text.trim(),
      );
      if (!mounted) return;
      setState(() => _submitting = false);
      result.fold(
        (failure) => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(failure.message), backgroundColor: AppColors.error),
        ),
        (_) {
          Navigator.of(context).pop(true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${_refundAmount.toCurrency} refunded to customer wallet'),
              backgroundColor: AppColors.success,
            ),
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Refund Payment')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _paymentSummary(),
            const SizedBox(height: 16),
            if (_isSettled) _settledBanner(),
            if (_isSettled) const SizedBox(height: 16),
            _amountField(),
            const SizedBox(height: 16),
            _reasonField(),
            const SizedBox(height: 24),
            PrimaryButton(
              label: _isSettled
                  ? (_submitting ? 'Sending…' : 'Request Vendor Approval')
                  : (_submitting ? 'Processing…' : 'Refund Now'),
              isLoading: _submitting,
              onPressed: _canSubmit ? _submit : null,
              icon: _isSettled ? Icons.send_rounded : Icons.reply_rounded,
            ),
          ],
        ),
      ),
    );
  }

  Widget _paymentSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Payment Details',
              style: Theme.of(context).textTheme.titleSmall),
          const Divider(height: 20),
          _row('Order', '#${widget.payment.orderNumber ?? widget.payment.orderId.substring(0, 8)}'),
          _row('Amount Paid', widget.payment.amount.toCurrency),
          _row('Type', widget.payment.type.name.toUpperCase()),
          _row('Status', _isSettled ? 'Settled' : 'Unsettled'),
        ],
      ),
    );
  }

  Widget _settledBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFFF57C00), size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'This payment is already settled. Your refund request will be sent to the vendor for approval.',
              style: TextStyle(color: Color(0xFFE65100), fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _amountField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Refund Amount', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        TextField(
          controller: _amountController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixText: 'Rs. ',
            filled: true,
            fillColor: AppColors.surface,
            helperText: 'Maximum: ${widget.payment.amount.toCurrency}',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ActionChip(
              label: const Text('Full'),
              onPressed: () {
                _amountController.text = widget.payment.amount.toString();
                setState(() {});
              },
            ),
            ActionChip(
              label: const Text('Half'),
              onPressed: () {
                _amountController.text = (widget.payment.amount ~/ 2).toString();
                setState(() {});
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _reasonField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Reason', style: Theme.of(context).textTheme.titleSmall),
            const Text(' *', style: TextStyle(color: AppColors.error)),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _reasonController,
          maxLines: 3,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'e.g. Customer returned damaged goods',
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: AppColors.textTertiary, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
