import 'package:flutter/material.dart';
import 'package:im_client/pages/login_page.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> with TickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final AnimationController _shimmerCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();

    _shimmerCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..repeat();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _shimmerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(flex: 3),

                    // Logo
                    Image.asset('assets/images/logo.png', width: 110, height: 110),
                    const SizedBox(height: 24),

                    // App name
                    const Text(
                      '内部通',
                      style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E), letterSpacing: 4),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '连接生活，无处不在',
                      style: TextStyle(fontSize: 15, color: Color(0xFF9CA3AF), letterSpacing: 2),
                    ),

                    const Spacer(flex: 4),

                    // Shimmer "现在开始" button
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: _ShimmerButton(
                        animation: _shimmerCtrl,
                        onPressed: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage()));
                        },
                      ),
                    ),

                    const SizedBox(height: 50),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShimmerButton extends StatelessWidget {
  final AnimationController animation;
  final VoidCallback onPressed;

  const _ShimmerButton({required this.animation, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(27),
              gradient: const LinearGradient(
                colors: [Color(0xFF0066FF), Color(0xFF00AADD)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0066FF).withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(27),
              child: Stack(
                children: [
                  // Shimmer highlight
                  Positioned.fill(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final w = constraints.maxWidth;
                        final shimmerW = w * 0.4;
                        final dx = animation.value * (w + shimmerW) - shimmerW;
                        return Stack(
                          children: [
                            Positioned(
                              left: dx,
                              top: 0,
                              bottom: 0,
                              width: shimmerW,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.white.withValues(alpha: 0.0),
                                      Colors.white.withValues(alpha: 0.25),
                                      Colors.white.withValues(alpha: 0.0),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  // Button content
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            '现在开始',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.arrow_forward_rounded, color: Colors.white.withValues(alpha: 0.9), size: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent;
  const _SlidingGradientTransform(this.slidePercent);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * slidePercent, 0, 0);
  }
}
