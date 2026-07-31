import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/constants/user_role.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/buttons/back_icon_button.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../../shared/widgets/inputs/app_text_field.dart';
import '../providers/auth_providers.dart';

class EmailSignUpScreen extends ConsumerStatefulWidget {
  const EmailSignUpScreen({super.key});

  @override
  ConsumerState<EmailSignUpScreen> createState() => _EmailSignUpScreenState();
}

class _EmailSignUpScreenState extends ConsumerState<EmailSignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _vendorIdController = TextEditingController();
  final _businessNameController = TextEditingController();

  // Fixed per app build — see core/config/app_flavor.dart.
  // No in-app role picker anymore: each build (customer/vendor/rider)
  // only ever shows its own fields.
  final UserRole _selectedRole = AppConfig.fixedRole;
  bool _obscure = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _vendorIdController.dispose();
    _businessNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final result = await ref.read(authControllerProvider.notifier).signUpWithEmail(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          fullName: _nameController.text.trim(),
          phone: _phoneController.text.trim(),
          role: _selectedRole,
          vendorId: _needsVendorId ? _vendorIdController.text.trim() : null,
          businessName: _selectedRole == UserRole.vendor
              ? _businessNameController.text.trim()
              : null,
        );
    if (!mounted) return;
    result.fold(
      (failure) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failure.message), backgroundColor: AppColors.error),
      ),
      (outcome) {
        final needsApproval =
            _selectedRole == UserRole.vendor || _selectedRole == UserRole.rider;
        if (needsApproval) {
          _showApprovalPendingDialog();
          return;
        }
        final target = switch (_selectedRole) {
          UserRole.vendor => RouteNames.vendorHome,
          UserRole.rider => RouteNames.riderHome,
          UserRole.admin || UserRole.superAdmin => RouteNames.adminHome,
          UserRole.customer => RouteNames.customerHome,
        };
        context.goNamed(target);
      },
    );
  }

  void _showApprovalPendingDialog() {
    final message = _selectedRole == UserRole.rider
        ? 'Your account has been created. Your vendor will need to '
            'approve your account before you can log in.'
        : 'Your account has been submitted for review. '
            'You can log in once approved.';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(_selectedRole == UserRole.rider
            ? 'Request sent'
            : 'Account submitted'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.pop();
            },
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  bool get _needsVendorId =>
      _selectedRole == UserRole.customer || _selectedRole == UserRole.rider;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const _AuthTopBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: AppShadows.brand(opacity: 0.3),
                        ),
                        child: const Icon(
                          Icons.person_add_alt_1_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Create your\naccount',
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                              letterSpacing: -0.5,
                            ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Join thousands ordering fresh water every day.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                      const SizedBox(height: 28),
                      // Role selector removed: each app build is fixed to
                      // one role via AppConfig.fixedRole, so there's
                      // nothing for the user to choose here anymore.
                      AppTextField(
                        controller: _nameController,
                        label: 'Full Name',
                        prefixIcon: Icons.person_outline_rounded,
                        validator: Validators.name,
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        controller: _emailController,
                        label: 'Email',
                        prefixIcon: Icons.alternate_email_rounded,
                        keyboardType: TextInputType.emailAddress,
                        validator: Validators.email,
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
                      if (_selectedRole == UserRole.vendor) ...[
                        const SizedBox(height: 16),
                        AppTextField(
                          controller: _businessNameController,
                          label: 'Business Name',
                          prefixIcon: Icons.storefront_rounded,
                          validator: (v) =>
                              Validators.required(v, field: 'Business name'),
                        ),
                      ],
                      if (_needsVendorId) ...[
                        const SizedBox(height: 16),
                        AppTextField(
                          controller: _vendorIdController,
                          label: 'Vendor ID',
                          hint: 'Get this from your vendor',
                          prefixIcon: Icons.qr_code_rounded,
                          validator: (v) =>
                              Validators.required(v, field: 'Vendor ID'),
                        ),
                      ],
                      const SizedBox(height: 16),
                      AppTextField(
                        controller: _passwordController,
                        label: 'Password',
                        obscureText: _obscure,
                        prefixIcon: Icons.lock_outline_rounded,
                        validator: Validators.password,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                            color: AppColors.textTertiary,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        controller: _confirmController,
                        label: 'Confirm Password',
                        obscureText: _obscure,
                        prefixIcon: Icons.lock_outline_rounded,
                        validator: (v) =>
                            Validators.confirmPassword(v, _passwordController.text),
                      ),
                      const SizedBox(height: 32),
                      PrimaryButton(
                        label: 'Create Account',
                        icon: Icons.arrow_forward_rounded,
                        isLoading: authState.isLoading,
                        onPressed: _submit,
                      ),
                      const SizedBox(height: 18),
                      Center(
                        child: Text.rich(
                          TextSpan(
                            text: 'Already have an account? ',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                            children: [
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: GestureDetector(
                                  onTap: () => context.pop(),
                                  child: const Text(
                                    'Sign in',
                                    style: TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthTopBar extends StatelessWidget {
  const _AuthTopBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
      child: Row(
        children: [
          BackIconButton(onPressed: () => Navigator.of(context).maybePop()),
        ],
      ),
    );
  }
}