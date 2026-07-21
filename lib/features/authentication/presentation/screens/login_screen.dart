import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../providers/auth_providers.dart';

/// Entry hub: phone OTP (primary, matches the Pakistani-market use
/// case), email/password, and Google — all wired, none stubbed.
class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);

    ref.listen(authControllerProvider, (previous, next) {
      next.whenOrNull(
        error: (error, _) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error.toString()),
              backgroundColor: AppColors.error,
            ),
          );
        },
      );
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        top: false,
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final screenH = constraints.maxHeight;
            final isShort = screenH < 700;
            final heroHeight = isShort
                ? (screenH * 0.28).clamp(160.0, 220.0)
                : (screenH * 0.38).clamp(260.0, 340.0);

            return Column(
              children: [
                _LoginHero(height: heroHeight, compact: isShort),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(24, isShort ? 14 : 24, 24, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SignInMethod(
                          icon: Icons.pin_rounded,
                          label: 'Login with PIN',
                          subtitle: 'Customer PIN from your vendor',
                          isPrimary: true,
                          isLoading: authState.isLoading,
                          compact: isShort,
                          onTap: () => context.pushNamed(RouteNames.pinLogin),
                        ),
                        SizedBox(height: isShort ? 8 : 14),
                        _SignInMethod(
                          icon: Icons.alternate_email_rounded,
                          label: 'Continue with Email',
                          subtitle: 'Use your email and password',
                          compact: isShort,
                          onTap: () => context.pushNamed(RouteNames.emailSignIn),
                        ),
                        SizedBox(height: isShort ? 8 : 14),
                        _SignInMethod(
                          icon: Icons.g_mobiledata_rounded,
                          label: 'Continue with Google',
                          subtitle: 'One tap sign-in',
                          isLoading: authState.isLoading,
                          compact: isShort,
                          onTap: () async {
                            final result = await ref
                                .read(authControllerProvider.notifier)
                                .signInWithGoogle();
                            if (!context.mounted) return;
                            result.fold((_) {}, (profile) {
                              if (!profile.isVerified) {
                                context.goNamed(RouteNames.completeProfile);
                              }
                            });
                          },
                        ),
                        if (!isShort) ...[
                          const SizedBox(height: 28),
                          const _RolePreviewStrip(),
                        ],
                        SizedBox(height: isShort ? 14 : 28),
                        Center(
                          child: Text.rich(
                            TextSpan(
                              text: 'By continuing, you agree to our ',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.textTertiary),
                              children: const [
                                TextSpan(
                                  text: 'Terms',
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                TextSpan(text: ' and '),
                                TextSpan(
                                  text: 'Privacy Policy',
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LoginHero extends StatelessWidget {
  final double height;
  final bool compact;
  const _LoginHero({required this.height, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: _HeroClipper(),
      child: Container(
        height: height,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF11809E),
              Color(0xFF0A6E8C),
              Color(0xFF054F66),
            ],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              top: -60,
              right: -50,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              top: 60,
              right: 40,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              bottom: 30,
              left: -40,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFA531).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(28, compact ? 24 : 40, 28, compact ? 36 : 60),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Container(
                        width: compact ? 48 : 64,
                        height: compact ? 48 : 64,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(compact ? 14 : 20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.18),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.water_drop_rounded,
                            color: AppColors.primary, size: 34),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            AppConfig.appName,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Text(
                            AppConfig.appTagline,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.85),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (!compact) ...[
                    SizedBox(height: compact ? 14 : 26),
                    Text(
                      'Welcome back',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: compact ? 22 : 30,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.5,
                        height: 1.1,
                      ),
                    ),
                    SizedBox(height: compact ? 4 : 8),
                    Text(
                      'Sign in to order water, manage deliveries,\nor run your vendor business.',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w500,
                        height: 1.45,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path()
      ..lineTo(0, size.height - 40)
      ..quadraticBezierTo(
        size.width * 0.5,
        size.height + 20,
        size.width,
        size.height - 40,
      )
      ..lineTo(size.width, 0)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _SignInMethod extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool isPrimary;
  final bool isLoading;
  final bool compact;
  final VoidCallback onTap;
  const _SignInMethod({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.isPrimary = false,
    this.isLoading = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final onPrimaryColor = isPrimary ? Colors.white : AppColors.textPrimary;
    final onPrimarySecondary =
        isPrimary ? Colors.white.withValues(alpha: 0.85) : AppColors.textTertiary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(compact ? 14 : 18),
        child: Ink(
          decoration: BoxDecoration(
            gradient: isPrimary ? AppColors.primaryGradient : null,
            color: isPrimary ? null : AppColors.surface,
            borderRadius: BorderRadius.circular(compact ? 14 : 18),
            border: isPrimary
                ? null
                : Border.all(color: AppColors.border, width: 1.2),
            boxShadow: isPrimary
                ? AppShadows.brand(opacity: 0.32)
                : AppShadows.card,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 14 : 18,
              vertical: compact ? 12 : 16,
            ),
            child: Row(
              children: [
                Container(
                  width: compact ? 38 : 46,
                  height: compact ? 38 : 46,
                  decoration: BoxDecoration(
                    color: isPrimary
                        ? Colors.white.withValues(alpha: 0.22)
                        : AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(compact ? 10 : 13),
                  ),
                  child: Icon(
                    icon,
                    color: isPrimary ? Colors.white : AppColors.primary,
                    size: compact ? 20 : 24,
                  ),
                ),
                SizedBox(width: compact ? 10 : 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: onPrimaryColor,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (!compact) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: onPrimarySecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (isLoading)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation(
                        isPrimary ? Colors.white : AppColors.primary,
                      ),
                    ),
                  )
                else
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 15,
                    color: isPrimary
                        ? Colors.white.withValues(alpha: 0.9)
                        : AppColors.textTertiary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RolePreviewStrip extends StatelessWidget {
  const _RolePreviewStrip();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Row(
          children: [
            Expanded(child: Divider(color: AppColors.border, thickness: 1)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'BUILT FOR EVERYONE',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textTertiary,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            Expanded(child: Divider(color: AppColors.border, thickness: 1)),
          ],
        ),
        SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _RoleChip(
                icon: Icons.person_rounded,
                label: 'Customer',
                color: AppColors.primary,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _RoleChip(
                icon: Icons.storefront_rounded,
                label: 'Vendor',
                color: AppColors.roleVendor,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _RoleChip(
                icon: Icons.two_wheeler_rounded,
                label: 'Rider',
                color: AppColors.roleRider,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RoleChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _RoleChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
