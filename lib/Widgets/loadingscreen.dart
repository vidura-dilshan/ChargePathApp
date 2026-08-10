import 'dart:math' as math;

import 'package:flutter/material.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with TickerProviderStateMixin {
  // Brand colors
  static const Color _primaryBlue = Color(0xFF0253A4);
  static const Color _lightBlue = Color(0xFF2196F3);
  static const Color _bgColor = Color(0xFFF0F6FF);

  // Animation controllers
  late final AnimationController _entranceCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _chargeCtrl;
  late final AnimationController _rotateCtrl;

  // Entrance animations
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

    // Entrance animation
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _logoFade = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(
      CurvedAnimation(
        parent: _entranceCtrl,
        curve: const Interval(
          0.0,
          0.4,
          curve: Curves.easeOut,
        ),
      ),
    );

    _logoScale = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _entranceCtrl,
        curve: const Interval(
          0.0,
          0.5,
          curve: Curves.elasticOut,
        ),
      ),
    );

    _textFade = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(
      CurvedAnimation(
        parent: _entranceCtrl,
        curve: const Interval(
          0.4,
          0.75,
          curve: Curves.easeOut,
        ),
      ),
    );

    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entranceCtrl,
        curve: const Interval(
          0.4,
          0.75,
          curve: Curves.easeOut,
        ),
      ),
    );

    _barFade = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(
      CurvedAnimation(
        parent: _entranceCtrl,
        curve: const Interval(
          0.65,
          1.0,
          curve: Curves.easeOut,
        ),
      ),
    );

    // Pulse animation
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _pulse = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(
      CurvedAnimation(
        parent: _pulseCtrl,
        curve: Curves.easeOut,
      ),
    );

    // Charging bar animation
    _chargeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

    _charge = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(
      CurvedAnimation(
        parent: _chargeCtrl,
        curve: Curves.easeInOut,
      ),
    );

    // Rotating outer ring
    _rotateCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();

    _rotate = Tween<double>(
      begin: 0,
      end: 2 * math.pi,
    ).animate(_rotateCtrl);

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
      // Prevent the keyboard from shrinking the loading screen.
      resizeToAvoidBottomInset: false,
      backgroundColor: _bgColor,
      body: Stack(
        children: [
          // Background dot pattern
          const Positioned.fill(
            child: _DotGrid(),
          ),

          // Main content
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bool isShortHeight =
                    constraints.maxHeight < 600;

                final double logoAreaSize =
                isShortHeight ? 110 : 140;

                final double pulseSize =
                isShortHeight ? 92 : 120;

                final double arcSize =
                isShortHeight ? 90 : 118;

                final double logoSize =
                isShortHeight ? 72 : 90;

                return Center(
                  child: SingleChildScrollView(
                    physics:
                    const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: isShortHeight ? 10 : 20,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Logo area
                        FadeTransition(
                          opacity: _logoFade,
                          child: ScaleTransition(
                            scale: _logoScale,
                            child: SizedBox(
                              width: logoAreaSize,
                              height: logoAreaSize,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  // Pulse ring
                                  AnimatedBuilder(
                                    animation: _pulse,
                                    builder: (_, __) {
                                      final double scale =
                                          0.7 +
                                              (_pulse.value * 0.9);

                                      final double opacity =
                                      (1 - _pulse.value)
                                          .clamp(
                                        0.0,
                                        0.6,
                                      );

                                      return Transform.scale(
                                        scale: scale,
                                        child: Container(
                                          width: pulseSize,
                                          height: pulseSize,
                                          decoration:
                                          BoxDecoration(
                                            shape:
                                            BoxShape.circle,
                                            border: Border.all(
                                              color:
                                              _primaryBlue
                                                  .withOpacity(
                                                opacity,
                                              ),
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
                                    builder: (_, __) {
                                      return Transform.rotate(
                                        angle: _rotate.value,
                                        child: CustomPaint(
                                          size: Size(
                                            arcSize,
                                            arcSize,
                                          ),
                                          painter:
                                          _DashedArcPainter(
                                            color:
                                            _primaryBlue
                                                .withOpacity(
                                              0.25,
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),

                                  // Main logo circle
                                  Container(
                                    width: logoSize,
                                    height: logoSize,
                                    decoration:
                                    BoxDecoration(
                                      shape:
                                      BoxShape.circle,
                                      gradient:
                                      const LinearGradient(
                                        colors: [
                                          _lightBlue,
                                          _primaryBlue,
                                        ],
                                        begin:
                                        Alignment.topLeft,
                                        end: Alignment
                                            .bottomRight,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color:
                                          _primaryBlue
                                              .withOpacity(
                                            0.35,
                                          ),
                                          blurRadius:
                                          isShortHeight
                                              ? 16
                                              : 24,
                                          offset:
                                          const Offset(
                                            0,
                                            8,
                                          ),
                                        ),
                                        BoxShadow(
                                          color:
                                          _lightBlue
                                              .withOpacity(
                                            0.2,
                                          ),
                                          blurRadius:
                                          isShortHeight
                                              ? 24
                                              : 40,
                                          spreadRadius:
                                          isShortHeight
                                              ? 2
                                              : 4,
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      Icons
                                          .ev_station_rounded,
                                      color: Colors.white,
                                      size:
                                      isShortHeight
                                          ? 36
                                          : 44,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        SizedBox(
                          height:
                          isShortHeight ? 16 : 32,
                        ),

                        // Brand text
                        FadeTransition(
                          opacity: _textFade,
                          child: SlideTransition(
                            position: _textSlide,
                            child: Column(
                              children: [
                                RichText(
                                  text: TextSpan(
                                    children: [
                                      TextSpan(
                                        text: 'charge',
                                        style:
                                        TextStyle(
                                          fontSize:
                                          isShortHeight
                                              ? 26
                                              : 32,
                                          fontWeight:
                                          FontWeight
                                              .w300,
                                          color:
                                          const Color(
                                            0xFF1A2B3C,
                                          ),
                                          letterSpacing:
                                          1.5,
                                        ),
                                      ),
                                      TextSpan(
                                        text: 'Path',
                                        style:
                                        TextStyle(
                                          fontSize:
                                          isShortHeight
                                              ? 26
                                              : 32,
                                          fontWeight:
                                          FontWeight
                                              .w800,
                                          color:
                                          _primaryBlue,
                                          letterSpacing:
                                          1.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                SizedBox(
                                  height:
                                  isShortHeight
                                      ? 4
                                      : 6,
                                ),

                                Text(
                                  'Powering your journey',
                                  style: TextStyle(
                                    fontSize:
                                    isShortHeight
                                        ? 11
                                        : 13,
                                    fontWeight:
                                    FontWeight.w400,
                                    color: Colors
                                        .grey.shade500,
                                    letterSpacing:
                                    isShortHeight
                                        ? 1.5
                                        : 2.0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        SizedBox(
                          height:
                          isShortHeight ? 20 : 52,
                        ),

                        // Charging bar
                        FadeTransition(
                          opacity: _barFade,
                          child: Column(
                            children: [
                              SizedBox(
                                width:
                                isShortHeight
                                    ? 150
                                    : 180,
                                child: AnimatedBuilder(
                                  animation: _charge,
                                  builder: (_, __) {
                                    return Container(
                                      height: 6,
                                      decoration:
                                      BoxDecoration(
                                        color:
                                        _primaryBlue
                                            .withOpacity(
                                          0.12,
                                        ),
                                        borderRadius:
                                        BorderRadius
                                            .circular(
                                          3,
                                        ),
                                      ),
                                      child: Stack(
                                        children: [
                                          // Fill
                                          FractionallySizedBox(
                                            widthFactor:
                                            _charge
                                                .value,
                                            child:
                                            Container(
                                              decoration:
                                              BoxDecoration(
                                                gradient:
                                                const LinearGradient(
                                                  colors: [
                                                    _lightBlue,
                                                    _primaryBlue,
                                                  ],
                                                ),
                                                borderRadius:
                                                BorderRadius
                                                    .circular(
                                                  3,
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color:
                                                    _primaryBlue.withOpacity(
                                                      0.5,
                                                    ),
                                                    blurRadius:
                                                    8,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),

                                          // Shimmer
                                          FractionallySizedBox(
                                            widthFactor:
                                            _charge
                                                .value,
                                            child:
                                            ClipRRect(
                                              borderRadius:
                                              BorderRadius
                                                  .circular(
                                                3,
                                              ),
                                              child:
                                              _ShimmerSweep(
                                                progress:
                                                _charge
                                                    .value,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),

                              SizedBox(
                                height:
                                isShortHeight
                                    ? 10
                                    : 14,
                              ),

                              // Connecting text
                              AnimatedBuilder(
                                animation:
                                _chargeCtrl,
                                builder: (_, __) {
                                  final String dots =
                                      '.' *
                                          ((_chargeCtrl
                                              .value *
                                              3)
                                              .floor() +
                                              1);

                                  return Text(
                                    'Connecting$dots',
                                    style: TextStyle(
                                      fontSize:
                                      isShortHeight
                                          ? 10
                                          : 12,
                                      color: Colors
                                          .grey.shade400,
                                      letterSpacing:
                                      1.5,
                                      fontWeight:
                                      FontWeight
                                          .w500,
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── HELPER PAINTERS & WIDGETS ────────────────────────────────────────────────

class _DashedArcPainter extends CustomPainter {
  final Color color;

  _DashedArcPainter({
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final Offset center = Offset(
      size.width / 2,
      size.height / 2,
    );

    final double radius = size.width / 2;

    const int dashCount = 16;
    const double dashAngle = math.pi / dashCount;
    const double gapAngle = dashAngle * 0.6;

    for (int i = 0; i < dashCount * 2; i++) {
      final double startAngle =
          i * (dashAngle + gapAngle / dashCount);

      canvas.drawArc(
        Rect.fromCircle(
          center: center,
          radius: radius,
        ),
        startAngle,
        dashAngle * 0.6,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(
      _DashedArcPainter oldDelegate,
      ) {
    return oldDelegate.color != color;
  }
}

class _ShimmerSweep extends StatelessWidget {
  final double progress;

  const _ShimmerSweep({
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (rect) {
        return LinearGradient(
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
        ).createShader(rect);
      },
      child: Container(
        color: Colors.white,
      ),
    );
  }
}

class _DotGrid extends StatelessWidget {
  const _DotGrid();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DotGridPainter(),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color =
      const Color(0xFF0253A4).withOpacity(0.06)
      ..style = PaintingStyle.fill;

    const double spacing = 28;

    for (
    double x = 0;
    x < size.width;
    x += spacing
    ) {
      for (
      double y = 0;
      y < size.height;
      y += spacing
      ) {
        canvas.drawCircle(
          Offset(x, y),
          1.5,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(
      _DotGridPainter oldDelegate,
      ) {
    return false;
  }
}