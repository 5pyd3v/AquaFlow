import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../shared/extensions/num_extensions.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../domain/repositories/payment_repository.dart';
import '../providers/payment_providers.dart';

/// Arguments passed from the rider delivery flow after the PIN has been
/// verified (order NOT yet delivered — this screen commits it).
class PaymentCollectionArgs {
  final String orderId;
  final String orderNumber;
  final String otp;
  final String vendorId;
  final int outstanding;
  final bool isCod;
  final String? customerProfileId;
  final int customerTotalDebt;

  const PaymentCollectionArgs({
    required this.orderId,
    required this.orderNumber,
    required this.otp,
    required this.vendorId,
    required this.outstanding,
    this.isCod = true,
    this.customerProfileId,
    this.customerTotalDebt = 0,
  });
}

/// Premium payment-collection sheet. Handles full / partial / over
/// payment, mandatory receipt capture (camera + gallery) for COD, and
/// commits everything atomically via `complete_delivery_with_payment`.
class PaymentCollectionScreen extends ConsumerStatefulWidget {
  final PaymentCollectionArgs args;
  const PaymentCollectionScreen({super.key, required this.args});

  @override
  ConsumerState<PaymentCollectionScreen> createState() => _PaymentCollectionScreenState();
}

class _PaymentCollectionScreenState extends ConsumerState<PaymentCollectionScreen> {
  late final TextEditingController _amountController;
  final _notesController = TextEditingController();

  Uint8List? _receiptBytes;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(text: widget.args.outstanding.toString());
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  int get _enteredAmount => int.tryParse(_amountController.text.trim()) ?? 0;
  int get _outstanding => widget.args.outstanding;
  int get _remaining => (_outstanding - _enteredAmount).clamp(0, _outstanding);
  int get _excess => (_enteredAmount - _outstanding).clamp(0, _enteredAmount);

  bool get _receiptRequired => widget.args.isCod;
  bool get _canConfirm =>
      !_submitting &&
      _enteredAmount >= 0 &&
      (!_receiptRequired || _receiptBytes != null);

  Future<void> _pickReceipt(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(source: source, imageQuality: 80);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      setState(() => _receiptBytes = bytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load image: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  Future<(double?, double?)> _captureGps() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return (null, null);
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return (null, null);
      }
      final pos = await Geolocator.getCurrentPosition();
      return (pos.latitude, pos.longitude);
    } catch (_) {
      return (null, null);
    }
  }

  Future<void> _confirm() async {
    setState(() => _submitting = true);
    final controller = ref.read(paymentControllerProvider.notifier);

    String? receiptUrl;
    ReceiptMeta? meta;

    // 1. Upload receipt (if any) + build fraud-prevention metadata
    if (_receiptBytes != null) {
      final upload = await controller.uploadReceipt(
        orderId: widget.args.orderId,
        bytes: _receiptBytes!,
      );
      final failure = upload.failureOrNull;
      if (failure != null) {
        if (!mounted) return;
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(failure.message), backgroundColor: AppColors.error),
        );
        return;
      }
      receiptUrl = upload.dataOrNull;
      final hash = sha256.convert(_receiptBytes!).toString();
      final (lat, lng) = await _captureGps();
      meta = ReceiptMeta(
        receiptType: 'cash',
        imageHash: hash,
        gpsLat: lat,
        gpsLng: lng,
        deviceTime: DateTime.now(),
      );
    }

    // 2. Commit payment + delivery atomically
    final result = await controller.completeWithPayment(
      orderId: widget.args.orderId,
      otp: widget.args.otp,
      amount: _enteredAmount,
      receiptUrl: receiptUrl,
      receiptMeta: meta,
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    result.fold(
      (failure) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failure.message), backgroundColor: AppColors.error),
      ),
      (res) {
        Navigator.of(context).pop(true);
        final msg = res.excessCredit > 0
            ? 'Payment recorded • ${res.excessCredit.toCurrency} credited to customer'
            : res.outstandingAfter > 0
                ? 'Partial payment recorded • ${res.outstandingAfter.toCurrency} outstanding'
                : 'Payment complete • delivered';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppColors.success),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Collect Payment')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _summaryCard(),
            if (widget.args.customerTotalDebt > 0) ...[
              const SizedBox(height: 12),
              _customerDebtBanner(),
            ],
            const SizedBox(height: 16),
            _amountField(),
            const SizedBox(height: 12),
            _breakdownCard(),
            const SizedBox(height: 16),
            _receiptSection(),
            const SizedBox(height: 16),
            _notesField(),
            const SizedBox(height: 24),
            PrimaryButton(
              label: _submitting ? 'Processing…' : 'Confirm & Complete Delivery',
              isLoading: _submitting,
              onPressed: _canConfirm ? _confirm : null,
              icon: Icons.check_circle_rounded,
            ),
            if (_receiptRequired && _receiptBytes == null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'A payment receipt is required to complete a COD delivery.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppShadows.brand(opacity: 0.25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Order #${widget.args.orderNumber}',
              style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Outstanding', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
          Text(
            _outstanding.toCurrency,
            style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _customerDebtBanner() {
    final debt = widget.args.customerTotalDebt;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFFF57C00), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Customer also owes ${debt.toCurrency} from previous orders',
              style: const TextStyle(
                color: Color(0xFFE65100),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
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
        Text('Amount received', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        TextField(
          controller: _amountController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixText: 'Rs. ',
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            _quickChip('Full', _outstanding),
            _quickChip('Half', (_outstanding / 2).round()),
            _quickChip('Nothing', 0),
          ],
        ),
      ],
    );
  }

  Widget _quickChip(String label, int value) {
    return ActionChip(
      label: Text(label),
      onPressed: () {
        _amountController.text = value.toString();
        setState(() {});
      },
    );
  }

  Widget _breakdownCard() {
    final (label, color) = _excess > 0
        ? ('Overpayment → customer credit', AppColors.info)
        : _remaining > 0
            ? ('Remaining (stays outstanding)', AppColors.warning)
            : ('Fully paid', AppColors.success);
    final value = _excess > 0 ? _excess : _remaining;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(
            _excess > 0
                ? Icons.account_balance_wallet_rounded
                : _remaining > 0
                    ? Icons.schedule_rounded
                    : Icons.check_circle_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
          Text(value.toCurrency, style: TextStyle(color: color, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _receiptSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Payment receipt', style: Theme.of(context).textTheme.titleSmall),
            if (_receiptRequired)
              const Text(' *', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 8),
        if (_receiptBytes != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              children: [
                Image.memory(_receiptBytes!, height: 160, width: double.infinity, fit: BoxFit.cover),
                Positioned(
                  top: 6,
                  right: 6,
                  child: CircleAvatar(
                    backgroundColor: Colors.black54,
                    radius: 16,
                    child: IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16, color: Colors.white),
                      onPressed: () => setState(() => _receiptBytes = null),
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickReceipt(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_rounded, size: 18),
                  label: const Text('Camera'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickReceipt(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_rounded, size: 18),
                  label: const Text('Gallery'),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _notesField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Notes (optional)', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        TextField(
          controller: _notesController,
          maxLines: 2,
          decoration: InputDecoration(
            hintText: 'e.g. paid Rs. 200 short, will settle next delivery',
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ],
    );
  }
}
