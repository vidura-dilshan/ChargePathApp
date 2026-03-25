import 'package:flutter/material.dart';
import 'dart:math' as math;

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with TickerProviderStateMixin {
  // Brand Colors
  static const Color _primaryBlue = Color(0xFF0253A4);
  static const Color _lightBlue = Color(0xFF2196F3);
  static const Color _bgColor = Color(0xFFF0F6FF);

  // Controllers
  late final AnimationController _entranceCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _chargeCtrl;
  late final AnimationController _rotateCtrl;

  // Entrance animations (staggered)
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _textFade;
  late final Animation<Offset> _textSlide;
  late final Animation<double> _barFade;

  // Continuous animations
  late final Animation<double> _pulse;
  late final Animation<double> _charge;
  late final Animation<double> _rotate;

  @override
  void initState() {
    super.initState();

    // --- ENTRANCE (runs once, 1.2s total) ---
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _logoFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _entranceCtrl, curve: const Interval(0.0, 0.4, curve: Curves.easeOut)),
    );
    _logoScale = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _entranceCtrl, curve: const Interval(0.0, 0.5, curve: Curves.elasticOut)),
    );
    _textFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _entranceCtrl, curve: const Interval(0.4, 0.75, curve: Curves.easeOut)),
    );
    _textSlide = Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(
      CurvedAnimation(parent: _entranceCtrl, curve: const Interval(0.4, 0.75, curve: Curves.easeOut)),
    );
    _barFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _entranceCtrl, curve: const Interval(0.65, 1.0, curve: Curves.easeOut)),
    );

    // --- PULSE (repeats, rings radiating out from logo) ---
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _pulse = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut),
    );

    // --- CHARGING BAR (repeats, simulates energy filling) ---
    _chargeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: false);
    _charge = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _chargeCtrl, curve: Curves.easeInOut),
    );

    // --- ROTATE (subtle continuous spin on outer ring) ---
    _rotateCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();
    _rotate = Tween<double>(begin: 0, end: 2 * math.pi).animate(_rotateCtrl);

    _entranceCtrl.forward();
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _pulseCtrl.dispose();
    _chargeCtrl.dispose();
    _rotateCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: Stack(
        children: [
          // Subtle background dot grid
          Positioned.fill(child: _DotGrid()),

          // Main content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── LOGO AREA ──────────────────────────────────────
                FadeTransition(
                  opacity: _logoFade,
                  child: ScaleTransition(
                    scale: _logoScale,
                    child: SizedBox(
                      width: 140,
                      height: 140,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Pulse ring (radiates outward)
                          AnimatedBuilder(
                            animation: _pulse,
                            builder: (_, __) {
                              final scale = 0.7 + (_pulse.value * 0.9);
                              final opacity = (1 - _pulse.value).clamp(0.0, 0.6);
                              return Transform.scale(
                                scale: scale,
                                child: Container(
                                  width: 120,
                                  height: 120,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: _primaryBlue.withOpacity(opacity),
                                      width: 2.5,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),

                          // Rotating dashed arc
                          AnimatedBuilder(
                            animation: _rotate,
                            builder: (_, __) => Transform.rotate(
                              angle: _rotate.value,
                              child: CustomPaint(
                                size: const Size(118, 118),
                                painter: _DashedArcPainter(color: _primaryBlue.withOpacity(0.25)),
                              ),
                            ),
                          ),

                          // Main logo circle
                          Container(
                            width: 90,
                            height: 90,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [_lightBlue, _primaryBlue],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: _primaryBlue.withOpacity(0.35),
                                  blurRadius: 24,
                                  offset: const Offset(0, 8),
                                ),
                                BoxShadow(
                                  color: _lightBlue.withOpacity(0.2),
                                  blurRadius: 40,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.ev_station_rounded,
                              color: Colors.white,
                              size: 44,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // ── BRAND TEXT ─────────────────────────────────────
                FadeTransition(
                  opacity: _textFade,
                  child: SlideTransition(
                    position: _textSlide,
                    child: Column(
                      children: [
                        RichText(
                          text: const TextSpan(
                            children: [
                              TextSpan(
                                text: 'charge',
                                style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w300,
                                  color: Color(0xFF1A2B3C),
                                  letterSpacing: 1.5,
                                ),
                              ),
                              TextSpan(
                                text: 'Path',
                                style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w800,
                                  color: _primaryBlue,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Powering your journey',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: Colors.grey.shade500,
                            letterSpacing: 2.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 52),

                // ── CHARGING BAR ───────────────────────────────────
                FadeTransition(
                  opacity: _barFade,
                  child: Column(
                    children: [
                      // The animated bar
                      SizedBox(
                        width: 180,
                        child: AnimatedBuilder(
                          animation: _charge,
                          builder: (_, __) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Bar shell
                                Container(
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: _primaryBlue.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Stack(
                                    children: [
                                      // Glowing fill
                                      FractionallySizedBox(
                                        widthFactor: _charge.value,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              colors: [_lightBlue, _primaryBlue],
                                            ),
                                            borderRadius: BorderRadius.circular(3),
                                            boxShadow: [
                                              BoxShadow(
                                                color: _primaryBlue.withOpacity(0.5),
                                                blurRadius: 8,
                                                offset: const Offset(0, 0),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      // Shimmer sweep
                                      FractionallySizedBox(
                                        widthFactor: _charge.value,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(3),
                                          child: _ShimmerSweep(progress: _charge.value),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 14),

                      // "Connecting..." text
                      AnimatedBuilder(
                        animation: _chargeCtrl,
                        builder: (_, __) {
                          final dots = '.' * ((_chargeCtrl.value * 3).floor() + 1);
                          return Text(
                            'Connecting$dots',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade400,
                              letterSpacing: 1.5,
                              fontWeight: FontWeight.w500,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── HELPER PAINTERS & WIDGETS ─────────────────────────────────────────────────

/// Dashed arc that rotates around the logo
class _DashedArcPainter extends CustomPainter {
  final Color color;
  _DashedArcPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const dashCount = 16;
    const dashAngle = math.pi / dashCount;
    const gapAngle = dashAngle * 0.6;

    for (int i = 0; i < dashCount * 2; i++) {
      final startAngle = i * (dashAngle + gapAngle / dashCount);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        dashAngle * 0.6,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedArcPainter old) => old.color != color;
}

/// Subtle shimmer sweep inside the charge bar
class _ShimmerSweep extends StatelessWidget {
  final double progress;
  const _ShimmerSweep({required this.progress});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (rect) => LinearGradient(
        stops: [
          (progress - 0.2).clamp(0.0, 1.0),
          progress.clamp(0.0, 1.0),
          (progress + 0.1).clamp(0.0, 1.0),
        ],
        colors: [
          Colors.white.withOpacity(0),
          Colors.white.withOpacity(0.45),
          Colors.white.withOpacity(0),
        ],
      ).createShader(rect),
      child: Container(color: Colors.white),
    );
  }
}

/// Subtle background dot grid for depth
class _DotGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _DotGridPainter());
  }
}

class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0253A4).withOpacity(0.06)
      ..style = PaintingStyle.fill;

    const spacing = 28.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.5, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter old) => false;
}