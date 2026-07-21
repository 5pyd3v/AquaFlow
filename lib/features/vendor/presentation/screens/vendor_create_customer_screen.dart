import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../../shared/widgets/inputs/app_text_field.dart';
import '../../../../shared/widgets/loaders/state_views.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';
import '../providers/vendor_providers.dart';

/// Vendor-facing screen to register a customer on their behalf. The
/// vendor enters the customer's name + phone; the backend provisions a
/// PIN-login account tied to this vendor and returns a 6-digit PIN the
/// vendor hands over. The customer then logs in with phone + PIN.
class VendorCreateCustomerScreen extends ConsumerStatefulWidget {
  const VendorCreateCustomerScreen({super.key});

  @override
  ConsumerState<VendorCreateCustomerScreen> createState() =>
      _VendorCreateCustomerScreenState();
}

class _VendorCreateCustomerScreenState
    extends ConsumerState<VendorCreateCustomerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit(String vendorId) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final result =
        await ref.read(authControllerProvider.notifier).createCustomerAccount(
              vendorId: vendorId,
              phone: _phoneController.text.trim(),
              fullName: _nameController.text.trim(),
            );
    if (!mounted) return;
    setState(() => _submitting = false);
    result.fold(
      (failure) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failure.message), backgroundColor: AppColors.error),
      ),
      (pin) => _showPinDialog(pin),
    );
  }

  void _showPinDialog(String pin) {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Customer created'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Share this login PIN with $name. They sign in with their '
              'phone number and this PIN.',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: Center(
                child: Text(
                  pin,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 10,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(phone, style: const TextStyle(color: AppColors.textTertiary)),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: pin));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('PIN copied')),
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy PIN'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _nameController.clear();
              _phoneController.clear();
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vendorAsync = ref.watch(myVendorProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Create Customer')),
      body: vendorAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorStateView(
          message: e.toString(),
          onRetry: () => ref.invalidate(myVendorProvider),
        ),
        data: (vendor) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: AppShadows.brand(opacity: 0.3),
                    ),
                    child: const Icon(Icons.person_add_alt_1_rounded,
                        color: Colors.white, size: 30),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Register a customer',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Add a customer to your store. We generate a 6-digit PIN '
                    'they use with their phone number to log in.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 28),
                  AppTextField(
                    controller: _nameController,
                    label: 'Customer Name',
                    prefixIcon: Icons.person_outline_rounded,
                    validator: Validators.name,
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    controller: _phoneController,
                    label: 'Phone Number',
                    hint: '+923001234567',
                    prefixIcon: Icons.phone_iphone_rounded,
                    keyboardType: TextInputType.phone,
                    validator: Validators.phone,
                  ),
                  const SizedBox(height: 32),
                  PrimaryButton(
                    label: 'Create & Generate PIN',
                    icon: Icons.vpn_key_rounded,
                    isLoading: _submitting,
                    onPressed: () => _submit(vendor.id),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
