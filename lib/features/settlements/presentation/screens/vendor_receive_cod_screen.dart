import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../shared/extensions/num_extensions.dart';
import '../../../vendor/presentation/providers/vendor_providers.dart';
import '../providers/settlement_providers.dart';

class VendorReceiveCodScreen extends ConsumerStatefulWidget {
  const VendorReceiveCodScreen({super.key});

  @override
  ConsumerState<VendorReceiveCodScreen> createState() =>
      _VendorReceiveCodScreenState();
}

class _VendorReceiveCodScreenState
    extends ConsumerState<VendorReceiveCodScreen> {
  final _codeController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  _VerifyResult? _result;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter a valid 6-digit code');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final vendor = await ref.read(myVendorProvider.future);
    final result = await ref
        .read(settlementControllerProvider.notifier)
        .verify(code: code, vendorId: vendor.id);

    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _isLoading = false;
        _error = failure.message;
      }),
      (data) => setState(() {
        _isLoading = false;
        _result = _VerifyResult(
          riderName: data.riderName,
          amount: data.amount,
          outstandingBefore: data.outstandingBefore,
          outstandingAfter: data.outstandingAfter,
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text(
          'Receive COD',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: _result != null
              ? _SuccessView(result: _result!)
              : _CodeEntryView(
                  controller: _codeController,
                  isLoading: _isLoading,
                  error: _error,
                  onVerify: _verify,
                ),
        ),
      ),
    );
  }
}

class _VerifyResult {
  final String riderName;
  final double amount;
  final double outstandingBefore;
  final double outstandingAfter;

  _VerifyResult({
    required this.riderName,
    required this.amount,
    required this.outstandingBefore,
    required this.outstandingAfter,
  });
}

class _CodeEntryView extends StatelessWidget {
  final TextEditingController controller;
  final bool isLoading;
  final String? error;
  final VoidCallback onVerify;

  const _CodeEntryView({
    required this.controller,
    required this.isLoading,
    required this.error,
    required this.onVerify,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 20),
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF7C5CFF), Color(0xFF5B3EDB)],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: AppShadows.brand(color: const Color(0xFF7C5CFF), opacity: 0.3),
          ),
          child: const Icon(Icons.qr_code_scanner_rounded,
              color: Colors.white, size: 36),
        ),
        const SizedBox(height: 24),
        Text(
          'Enter Settlement Code',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Ask the rider for their 6-digit settlement code to receive cash.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 32),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: 8,
          ),
          decoration: InputDecoration(
            counterText: '',
            hintText: '000000',
            hintStyle: TextStyle(
              color: AppColors.textTertiary.withValues(alpha: 0.4),
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: 8,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
            errorText: error,
            contentPadding: const EdgeInsets.symmetric(vertical: 20),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: isLoading ? null : onVerify,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            child: isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Verify & Receive'),
          ),
        ),
      ],
    );
  }
}

class _SuccessView extends StatelessWidget {
  final _VerifyResult result;
  const _SuccessView({required this.result});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF10B981), size: 52),
            ),
            const SizedBox(height: 20),
            const Text(
              'Cash Received!',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  _DetailRow(label: 'Rider', value: result.riderName),
                  const Divider(height: 24),
                  _DetailRow(
                      label: 'Amount', value: result.amount.toCurrency, bold: true),
                  const Divider(height: 24),
                  _DetailRow(
                      label: 'Balance Before',
                      value: result.outstandingBefore.toCurrency),
                  const Divider(height: 24),
                  _DetailRow(
                      label: 'Balance After',
                      value: result.outstandingAfter.toCurrency),
                ],
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => context.pop(),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Done',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _DetailRow({required this.label, required this.value, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            fontSize: bold ? 18 : 14,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
