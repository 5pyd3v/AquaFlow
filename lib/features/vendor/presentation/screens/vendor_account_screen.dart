import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/inputs/app_text_field.dart';
import '../../../../shared/widgets/dialogs/confirm_sign_out_dialog.dart';
import '../../../../shared/widgets/loaders/state_views.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';
import '../../domain/entities/vendor_entity.dart';
import '../providers/vendor_providers.dart';

class VendorAccountScreen extends ConsumerWidget {
  const VendorAccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendorAsync = ref.watch(myVendorProvider);
    final profile = ref.watch(authStateProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: vendorAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            ErrorStateView(message: e.toString(), onRetry: () => ref.invalidate(myVendorProvider)),
        data: (vendor) => SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _VendorProfileHero(
                vendor: vendor,
                ownerName: profile?.fullName ?? 'Business Owner',
                contact: profile?.phone ?? profile?.email ?? '',
              ),
              const SizedBox(height: 20),
              const _SectionHeader(
                icon: Icons.badge_rounded,
                label: 'Business Profile',
                subtitle: 'How customers see your store',
              ),
              const SizedBox(height: 12),
              AppCard(child: _BusinessProfileForm(vendor: vendor)),
              const SizedBox(height: 20),
              const _SectionHeader(
                icon: Icons.tune_rounded,
                label: 'Manage',
                subtitle: 'Team & shop settings',
              ),
              const SizedBox(height: 12),
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: Column(
                  children: [
                    _MenuTile(
                      icon: Icons.person_add_alt_1_rounded,
                      tint: AppColors.primary,
                      label: 'Create Customer',
                      subtitle: 'Register a customer and share their PIN',
                      onTap: () => context.pushNamed(RouteNames.vendorCreateCustomer),
                    ),
                    const _TileDivider(),
                    _MenuTile(
                      icon: Icons.two_wheeler_rounded,
                      tint: AppColors.roleRider,
                      label: 'Manage Riders',
                      subtitle: 'Link team members to your business',
                      onTap: () => context.pushNamed(RouteNames.vendorRiders),
                    ),
                    const _TileDivider(),
                    _MenuTile(
                      icon: Icons.map_rounded,
                      tint: AppColors.primary,
                      label: 'Live Riders Map',
                      subtitle: 'See where your riders are right now',
                      onTap: () => context.pushNamed(RouteNames.vendorLiveMap),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: _MenuTile(
                  icon: Icons.logout_rounded,
                  tint: AppColors.error,
                  label: 'Sign Out',
                  subtitle: 'End your session on this device',
                  onTap: () => _confirmSignOut(context, ref),
                ),
              ),
              const SizedBox(height: 24),
              FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snapshot) {
                  final version = snapshot.data?.version ?? AppConfig.appVersion;
                  return Center(
                    child: Text('${AppConfig.appName} v$version',
                        style: const TextStyle(color: AppColors.textTertiary, fontSize: 12)),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmSignOut(BuildContext context, WidgetRef ref) {
    showSignOutConfirmDialog(
      context,
      message: 'You can sign back in with the same email or phone number anytime.',
      onConfirm: () => ref.read(authControllerProvider.notifier).signOut(),
    );
  }
}

class _VendorProfileHero extends StatelessWidget {
  final VendorEntity vendor;
  final String ownerName;
  final String contact;
  const _VendorProfileHero({required this.vendor, required this.ownerName, required this.contact});

  @override
  Widget build(BuildContext context) {
    final businessName =
        vendor.businessName?.isNotEmpty == true ? vendor.businessName! : 'Your Business';
    final verified = vendor.status.label.toLowerCase().contains('active') ||
        vendor.status.label.toLowerCase().contains('approved');

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF9E85FF), Color(0xFF7C5CFF), Color(0xFF5B3EDB)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: AppShadows.brand(color: const Color(0xFF7C5CFF), opacity: 0.32),
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          const Positioned(
            right: -40,
            top: -30,
            child: _Bubble(size: 150, opacity: 0.12),
          ),
          const Positioned(
            left: -20,
            bottom: -30,
            child: _Bubble(size: 100, opacity: 0.08),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1.5),
                    ),
                    child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(businessName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20)),
                        const SizedBox(height: 4),
                        Text('Owner · $ownerName',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  _HeroChip(
                    icon: verified ? Icons.verified_rounded : Icons.hourglass_bottom_rounded,
                    label: vendor.status.label,
                  ),
                  if (contact.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _HeroChip(icon: Icons.phone_iphone_rounded, label: contact),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final double size;
  final double opacity;
  const _Bubble({required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: opacity),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _HeroChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  const _SectionHeader(
      {required this.icon, required this.label, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFF7C5CFF).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.storefront_rounded, size: 18, color: Color(0xFF7C5CFF)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              Text(subtitle,
                  style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
            ],
          ),
        ),
      ],
    );
  }
}

class _TileDivider extends StatelessWidget {
  const _TileDivider();

  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, indent: 62, endIndent: 12, color: AppColors.border);
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.tint,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: tint, size: 20),
      ),
      title: Text(label,
          style: TextStyle(
              color: tint == AppColors.error ? AppColors.error : AppColors.textPrimary,
              fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: const TextStyle(color: AppColors.textTertiary, fontSize: 12)),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
    );
  }
}

class _BusinessProfileForm extends ConsumerStatefulWidget {
  final VendorEntity vendor;
  const _BusinessProfileForm({required this.vendor});

  @override
  ConsumerState<_BusinessProfileForm> createState() => _BusinessProfileFormState();
}

class _BusinessProfileFormState extends ConsumerState<_BusinessProfileForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.vendor.businessName ?? '');
    _addressController = TextEditingController(text: widget.vendor.address ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final result = await ref.read(vendorRepositoryProvider).updateVendorProfile(
          businessName: _nameController.text.trim(),
          address: _addressController.text.trim(),
        );
    if (!mounted) return;
    setState(() => _saving = false);
    result.fold(
      (failure) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failure.message), backgroundColor: AppColors.error),
      ),
      (_) {
        ref.invalidate(myVendorProvider);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Business profile updated')));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            controller: _nameController,
            label: 'Business Name',
            prefixIcon: Icons.storefront_rounded,
            validator: (v) => Validators.required(v, field: 'Business name'),
          ),
          const SizedBox(height: 14),
          AppTextField(
            controller: _addressController,
            label: 'Business Address',
            prefixIcon: Icons.location_on_rounded,
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          PrimaryButton(label: 'Save Changes', isLoading: _saving, onPressed: _save),
        ],
      ),
    );
  }
}
