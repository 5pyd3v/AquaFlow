import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/user_role.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../../shared/widgets/inputs/app_text_field.dart';
import '../providers/auth_providers.dart';

/// Shown after the very first OTP/Google login when the `profiles`
/// row exists but is not yet filled in (no name, unverified). This is
/// where the user picks which of the three self-service dashboards
/// they want.
class CompleteProfileScreen extends ConsumerStatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  ConsumerState<CompleteProfileScreen> createState() =>
      _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends ConsumerState<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _vendorIdController = TextEditingController();
  UserRole _selectedRole = UserRole.customer;

  /// Riders and customers must be tied to a vendor, so they have to
  /// provide a phone number (to be identified) and a Vendor ID.
  bool get _needsVendorId =>
      _selectedRole == UserRole.customer || _selectedRole == UserRole.rider;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _vendorIdController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final result =
        await ref.read(authControllerProvider.notifier).completeProfile(
              fullName: _nameController.text.trim(),
              role: _selectedRole,
              email: _emailController.text.trim().isEmpty
                  ? null
                  : _emailController.text.trim(),
              phone: _needsVendorId ? _phoneController.text.trim() : null,
              vendorId: _needsVendorId ? _vendorIdController.text.trim() : null,
            );
    if (!mounted) return;
    result.fold(
      (failure) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(failure.message),
          backgroundColor: AppColors.error,
        ),
      ),
      (_) {
        switch (_selectedRole) {
          case UserRole.vendor:
            context.goNamed(RouteNames.vendorHome);
          case UserRole.rider:
            context.goNamed(RouteNames.riderHome);
          case UserRole.admin:
          case UserRole.superAdmin:
            context.goNamed(RouteNames.adminHome);
          case UserRole.customer:
            context.goNamed(RouteNames.customerHome);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _CompleteProfileHero(role: _selectedRole),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _StepBadge(role: _selectedRole),
                      const SizedBox(height: 16),
                      Text(
                        'Almost there!',
                        style: Theme.of(context)
                            .textTheme
                            .displaySmall
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Just a few more details and we'll set up the right dashboard for you.",
                        style:
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: AppColors.textSecondary,
                                  height: 1.45,
                                ),
                      ),
                      const SizedBox(height: 28),
                      const _SectionLabel(
                        icon: Icons.badge_outlined,
                        label: 'Personal Details',
                      ),
                      const SizedBox(height: 14),
                      AppTextField(
                        controller: _nameController,
                        label: 'Full Name',
                        prefixIcon: Icons.person_outline_rounded,
                        validator: Validators.name,
                      ),
                      const SizedBox(height: 14),
                      AppTextField(
                        controller: _emailController,
                        label: 'Email (optional)',
                        prefixIcon: Icons.alternate_email_rounded,
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) =>
                            v == null || v.isEmpty ? null : Validators.email(v),
                      ),
                      if (_needsVendorId) ...[
                        const SizedBox(height: 14),
                        AppTextField(
                          controller: _phoneController,
                          label: 'Phone Number',
                          hint: '+923001234567',
                          prefixIcon: Icons.phone_iphone_rounded,
                          keyboardType: TextInputType.phone,
                          validator: Validators.phone,
                        ),
                        const SizedBox(height: 14),
                        AppTextField(
                          controller: _vendorIdController,
                          label: 'Vendor ID',
                          hint: 'Get this from your vendor',
                          prefixIcon: Icons.qr_code_rounded,
                          validator: (v) =>
                              Validators.required(v, field: 'Vendor ID'),
                        ),
                      ],
                      const SizedBox(height: 24),
                      const _SectionLabel(
                        icon: Icons.workspace_premium_rounded,
                        label: 'Choose Your Role',
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "You can only pick one — but you'll always be able to switch accounts.",
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppColors.textTertiary,
                                ),
                      ),
                      const SizedBox(height: 14),
                      ...UserRole.selfServiceRoles.map(
                        (role) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _RoleOptionCard(
                            role: role,
                            isSelected: role == _selectedRole,
                            onTap: () => setState(() => _selectedRole = role),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      PrimaryButton(
                        label: 'Complete & Continue',
                        icon: Icons.arrow_forward_rounded,
                        isLoading: authState.isLoading,
                        onPressed: _submit,
                      ),
                      const SizedBox(height: 10),
                      Center(
                        child: Text(
                          'You can update these details later in Settings.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.textTertiary),
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

class _CompleteProfileHero extends StatelessWidget {
  final UserRole role;
  const _CompleteProfileHero({required this.role});

  Color get _tint => switch (role) {
        UserRole.vendor => AppColors.roleVendor,
        UserRole.rider => AppColors.roleRider,
        UserRole.customer => AppColors.primary,
        _ => AppColors.primary,
      };

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _tint,
            Color.lerp(_tint, Colors.black, 0.25) ?? _tint,
          ],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                ),
                child: const Icon(
                  Icons.assignment_ind_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Complete Profile',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_outline,
                        color: Colors.white, size: 14),
                    SizedBox(width: 4),
                    Text(
                      'Step 2 of 2',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            height: 6,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(999),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: 0.8,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.5),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepBadge extends StatelessWidget {
  final UserRole role;
  const _StepBadge({required this.role});

  Color get _tint => switch (role) {
        UserRole.vendor => AppColors.roleVendor,
        UserRole.rider => AppColors.roleRider,
        UserRole.customer => AppColors.primary,
        _ => AppColors.primary,
      };

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _tint.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _tint.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_rounded, size: 14, color: _tint),
            const SizedBox(width: 6),
            Text(
              'FINAL STEP',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: _tint,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: AppColors.primary),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }
}

class _RoleOptionCard extends StatelessWidget {
  final UserRole role;
  final bool isSelected;
  final VoidCallback onTap;

  const _RoleOptionCard({
    required this.role,
    required this.isSelected,
    required this.onTap,
  });

  IconData get _icon => switch (role) {
        UserRole.customer => Icons.shopping_bag_rounded,
        UserRole.vendor => Icons.storefront_rounded,
        UserRole.rider => Icons.two_wheeler_rounded,
        _ => Icons.person_outline,
      };

  Color get _tint => switch (role) {
        UserRole.customer => AppColors.primary,
        UserRole.vendor => AppColors.roleVendor,
        UserRole.rider => AppColors.roleRider,
        _ => AppColors.primary,
      };

  String get _subtitle => switch (role) {
        UserRole.customer => 'Order water bottles for home or office',
        UserRole.vendor => 'Sell and manage your water business',
        UserRole.rider => 'Deliver orders and earn on your schedule',
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected
                ? _tint.withValues(alpha: 0.06)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected ? _tint : AppColors.border,
              width: isSelected ? 1.8 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: _tint.withValues(alpha: 0.16),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : AppShadows.card,
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            _tint,
                            Color.lerp(_tint, Colors.black, 0.15) ?? _tint,
                          ],
                        )
                      : null,
                  color: isSelected ? null : _tint.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: _tint.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  _icon,
                  color: isSelected ? Colors.white : _tint,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      role.label,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isSelected ? _tint : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? _tint : AppColors.border,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check_rounded,
                        color: Colors.white, size: 14)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
