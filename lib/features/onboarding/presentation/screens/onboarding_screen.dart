import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';

class _OnboardingPage {
  final IconData icon;
  final String title;
  final String description;
  final LinearGradient gradient;
  final Color accent;
  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.description,
    required this.gradient,
    required this.accent,
  });
}

const _pages = [
  _OnboardingPage(
    icon: Icons.local_shipping_rounded,
    title: 'Water, delivered\nin minutes',
    description:
        'Order mineral and purified water bottles from trusted local vendors and track your rider live on the map.',
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF11809E), Color(0xFF0A6E8C), Color(0xFF054F66)],
    ),
    accent: Color(0xFF3E9CBB),
  ),
  _OnboardingPage(
    icon: Icons.repeat_rounded,
    title: 'Never run out\nagain',
    description:
        'Set up weekly or monthly recurring deliveries, and let AquaFlow handle scheduling automatically.',
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFFB552), Color(0xFFFFA531), Color(0xFFE0870F)],
    ),
    accent: Color(0xFFFFCB70),
  ),
  _OnboardingPage(
    icon: Icons.storefront_rounded,
    title: 'Built for the\nwhole business',
    description:
        'Vendors manage inventory and staff, riders navigate optimized routes, and admins see everything in real time.',
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF9E7BFF), Color(0xFF7C5CFF), Color(0xFF5A3BE0)],
    ),
    accent: Color(0xFFB198FF),
  ),
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final _controller = PageController();
  late final AnimationController _float;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _float = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    _float.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await StorageService.instance.setSeenOnboarding();
    if (mounted) context.goNamed(RouteNames.login);
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _index == _pages.length - 1;
    final page = _pages[_index];
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(onSkip: _finish, isLast: isLast),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => _OnboardingPageView(
                  page: _pages[i],
                  float: _float,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SmoothPageIndicator(
              controller: _controller,
              count: _pages.length,
              effect: ExpandingDotsEffect(
                activeDotColor: page.accent,
                dotColor: AppColors.border,
                dotHeight: 8,
                dotWidth: 8,
                expansionFactor: 3.5,
                spacing: 6,
              ),
            ),
            const SizedBox(height: 24),
            _AnimatedCta(
              accent: page.accent,
              gradient: page.gradient,
              isLast: isLast,
              onPressed: () {
                if (isLast) {
                  _finish();
                } else {
                  _controller.nextPage(
                    duration: const Duration(milliseconds: 380),
                    curve: Curves.easeOutCubic,
                  );
                }
              },
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final VoidCallback onSkip;
  final bool isLast;
  const _TopBar({required this.onSkip, required this.isLast});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: AppShadows.brand(opacity: 0.25),
                ),
                child: const Icon(Icons.water_drop_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              const Text(
                'AquaFlow',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: isLast ? 0 : 1,
            child: TextButton(
              onPressed: isLast ? null : onSkip,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              child: const Text(
                'Skip',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingPageView extends StatelessWidget {
  final _OnboardingPage page;
  final AnimationController float;
  const _OnboardingPageView({required this.page, required this.float});

  @override
  Widget build(BuildContext context) {
    final shortScreen = MediaQuery.sizeOf(context).height < 700;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          SizedBox(height: shortScreen ? 8 : 16),
          _IllustrationHero(page: page, float: float, short: shortScreen),
          SizedBox(height: shortScreen ? 20 : 28),
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -0.8,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            page.description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              color: AppColors.textSecondary,
              height: 1.5,
              letterSpacing: -0.1,
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _IllustrationHero extends StatelessWidget {
  final _OnboardingPage page;
  final AnimationController float;
  final bool short;
  const _IllustrationHero({
    required this.page,
    required this.float,
    required this.short,
  });

  @override
  Widget build(BuildContext context) {
    final size = short ? 180.0 : 220.0;
    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Outer soft glow ring
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    page.accent.withValues(alpha: 0.18),
                    page.accent.withValues(alpha: 0.0),
                  ],
                  stops: const [0.5, 1.0],
                ),
              ),
            ),
            // Rotating dashed orbit
            AnimatedBuilder(
              animation: float,
              builder: (context, _) => Transform.rotate(
                angle: float.value * math.pi * 0.4,
                child: CustomPaint(
                  size: Size(size * 0.86, size * 0.86),
                  painter: _DashedRingPainter(color: page.accent.withValues(alpha: 0.35)),
                ),
              ),
            ),
            // Floating decoration bubbles
            _FloatingBubble(
              float: float,
              offset: const Offset(-90, -80),
              size: 22,
              color: page.accent.withValues(alpha: 0.55),
              phase: 0,
            ),
            _FloatingBubble(
              float: float,
              offset: const Offset(95, -60),
              size: 14,
              color: page.accent.withValues(alpha: 0.4),
              phase: 0.3,
            ),
            _FloatingBubble(
              float: float,
              offset: const Offset(80, 90),
              size: 18,
              color: page.accent.withValues(alpha: 0.5),
              phase: 0.6,
            ),
            _FloatingBubble(
              float: float,
              offset: const Offset(-80, 85),
              size: 10,
              color: page.accent.withValues(alpha: 0.45),
              phase: 0.9,
            ),
            // Inner colored circle
            Container(
              width: size * 0.62,
              height: size * 0.62,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: page.gradient,
                boxShadow: [
                  BoxShadow(
                    color: page.accent.withValues(alpha: 0.4),
                    blurRadius: 40,
                    spreadRadius: -4,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
            ),
            // Icon
            Icon(page.icon, size: size * 0.28, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

class _FloatingBubble extends StatelessWidget {
  final AnimationController float;
  final Offset offset;
  final double size;
  final Color color;
  final double phase;
  const _FloatingBubble({
    required this.float,
    required this.offset,
    required this.size,
    required this.color,
    required this.phase,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: float,
      builder: (context, _) {
        final t = (float.value + phase) % 1.0;
        final dy = math.sin(t * math.pi * 2) * 8;
        return Transform.translate(
          offset: Offset(offset.dx, offset.dy + dy),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.5),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DashedRingPainter extends CustomPainter {
  final Color color;
  _DashedRingPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    const totalDashes = 40;
    const dashArc = math.pi * 2 / totalDashes * 0.55;
    const gapArc = math.pi * 2 / totalDashes * 0.45;

    double startAngle = 0;
    for (int i = 0; i < totalDashes; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        dashArc,
        false,
        paint,
      );
      startAngle += dashArc + gapArc;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRingPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _AnimatedCta extends StatelessWidget {
  final Color accent;
  final LinearGradient gradient;
  final bool isLast;
  final VoidCallback onPressed;
  const _AnimatedCta({
    required this.accent,
    required this.gradient,
    required this.isLast,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        height: 58,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.45),
              blurRadius: 22,
              offset: const Offset(0, 12),
              spreadRadius: -6,
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(18),
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    isLast ? 'Get Started' : 'Continue',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isLast
                        ? Icons.rocket_launch_rounded
                        : Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 20,
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
