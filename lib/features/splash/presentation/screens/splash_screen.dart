import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/routes/route_names.dart';

/// Branded splash — plays a short logo entrance animation while the
/// auth stream resolves. Navigation is owned entirely by the router's
/// redirect (see `app_router.dart`): the redirect holds every route on
/// this splash until the auth stream emits, then routes to
/// onboarding/login/home. The screen only nudges the router once, after
/// a minimum brand-hold, so the animation is never cut off — it does
/// NOT decide the destination itself, which is what previously caused a
/// double-navigation race that could strand users on onboarding.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entrance;
  late final AnimationController _orbit;
  late final AnimationController _pulse;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _wordmarkFade;
  late final Animation<Offset> _wordmarkSlide;
  late final Animation<double> _tagFade;
  late final Animation<Offset> _tagSlide;
  late final Animation<double> _dotsFade;

  @override
  void initState() {
    super.initState();

    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();

    _orbit = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _logoScale = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOutBack),
    );
    _logoFade = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
    );
    _wordmarkFade = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.35, 0.75, curve: Curves.easeOut),
    );
    _wordmarkSlide = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.35, 0.75, curve: Curves.easeOutCubic),
    ));
    _tagFade = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.55, 0.9, curve: Curves.easeOut),
    );
    _tagSlide = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.55, 0.9, curve: Curves.easeOutCubic),
    ));
    _dotsFade = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.75, 1.0, curve: Curves.easeOut),
    );

    // After a minimum brand-hold, re-run the router's redirect by
    // "refreshing" our own location. The redirect (now that the auth
    // stream has had time to emit) picks the real destination.
    Future.delayed(const Duration(milliseconds: 1900), _nudgeRouter);
  }

  void _nudgeRouter() {
    if (!mounted) return;
    context.goNamed(RouteNames.splash);
  }

  @override
  void dispose() {
    _entrance.dispose();
    _orbit.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Deep multi-stop gradient background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF11809E),
                  Color(0xFF0A6E8C),
                  Color(0xFF054F66),
                  Color(0xFF072E3B),
                ],
                stops: [0.0, 0.35, 0.75, 1.0],
              ),
            ),
          ),
          // Ambient light blobs
          const _AmbientBlob(
            top: -80,
            left: -60,
            size: 260,
            color: Color(0x553E9CBB),
          ),
          const _AmbientBlob(
            bottom: -100,
            right: -80,
            size: 320,
            color: Color(0x33FFA531),
          ),
          const _AmbientBlob(
            top: 200,
            right: -120,
            size: 220,
            color: Color(0x2211809E),
          ),
          // Content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                _AnimatedBadge(
                  orbit: _orbit,
                  pulse: _pulse,
                  fade: _logoFade,
                  scale: _logoScale,
                ),
                const SizedBox(height: 32),
                FadeTransition(
                  opacity: _wordmarkFade,
                  child: SlideTransition(
                    position: _wordmarkSlide,
                    child: ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Colors.white, Color(0xFFDBEEF6)],
                      ).createShader(bounds),
                      child: const Text(
                        AppConfig.appName,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 42,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 1.0,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FadeTransition(
                  opacity: _tagFade,
                  child: SlideTransition(
                    position: _tagSlide,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFFB552),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            AppConfig.appTagline,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.9),
                              letterSpacing: 0.4,
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
          // Loading dots anchored to the bottom, independent of the
          // centered content so the badge/wordmark sit at true middle.
          Positioned(
            left: 0,
            right: 0,
            bottom: 56,
            child: Center(
              child: FadeTransition(
                opacity: _dotsFade,
                child: _LoadingDots(controller: _pulse),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AmbientBlob extends StatelessWidget {
  final double? top;
  final double? bottom;
  final double? left;
  final double? right;
  final double size;
  final Color color;
  const _AmbientBlob({
    this.top,
    this.bottom,
    this.left,
    this.right,
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color, color.withValues(alpha: 0)],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedBadge extends StatelessWidget {
  final AnimationController orbit;
  final AnimationController pulse;
  final Animation<double> fade;
  final Animation<double> scale;
  const _AnimatedBadge({
    required this.orbit,
    required this.pulse,
    required this.fade,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: fade,
      child: ScaleTransition(
        scale: scale,
        child: SizedBox(
          width: 180,
          height: 180,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Pulsing halo
              AnimatedBuilder(
                animation: pulse,
                builder: (context, _) {
                  final t = pulse.value;
                  return Container(
                    width: 160 + t * 20,
                    height: 160 + t * 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.06 + (1 - t) * 0.06),
                    ),
                  );
                },
              ),
              // Orbiting ring with two accent dots
              AnimatedBuilder(
                animation: orbit,
                builder: (context, _) {
                  return CustomPaint(
                    size: const Size(150, 150),
                    painter: _OrbitPainter(orbit.value),
                  );
                },
              ),
              // Center water-drop logo
              Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Colors.white, Color(0xFFEAF6FA)],
                  ),
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF054F66).withValues(alpha: 0.35),
                      blurRadius: 30,
                      offset: const Offset(0, 14),
                    ),
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.5),
                      blurRadius: 24,
                      offset: const Offset(0, -6),
                    ),
                  ],
                ),
                child: ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF3E9CBB), Color(0xFF054F66)],
                  ).createShader(bounds),
                  child: const Icon(
                    Icons.water_drop_rounded,
                    color: Colors.white,
                    size: 58,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  final double t;
  _OrbitPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Faint ring
    final ringPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, ringPaint);

    // Bright arc that sweeps around
    final arcPaint = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: 0.55),
          Colors.white.withValues(alpha: 0),
        ],
        stops: const [0.0, 0.5, 1.0],
        transform: GradientRotation(t * math.pi * 2),
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, arcPaint);

    // Two orbiting accent dots
    for (var i = 0; i < 2; i++) {
      final angle = t * math.pi * 2 + i * math.pi;
      final dotPos = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      final glowPaint = Paint()
        ..color = (i == 0 ? const Color(0xFFFFB552) : Colors.white)
            .withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(dotPos, 6, glowPaint);
      final dotPaint = Paint()
        ..color = i == 0 ? const Color(0xFFFFB552) : Colors.white;
      canvas.drawCircle(dotPos, 3.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter old) => old.t != t;
}

class _LoadingDots extends StatelessWidget {
  final AnimationController controller;
  const _LoadingDots({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // Each dot lags by 1/3 of the cycle
            final phase = (controller.value + i / 3) % 1.0;
            final a = 0.25 + (math.sin(phase * math.pi) * 0.75);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: a.clamp(0.25, 1.0)),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}
