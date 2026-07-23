import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../config/nusa_config.dart';

/// Splash screen — centered SVG logo with bouncing-dots overlay.
///
/// The brand SVG is displayed centered with [BoxFit.contain] so it fits
/// the screen without cropping. Background adapts to the current theme.
/// A 3-dot bouncing animation is layered on top.
/// After ~2.5 seconds, calls [onDone].
class SplashScreen extends StatefulWidget {
  final void Function(BuildContext context) onDone;
  final Duration duration;

  const SplashScreen({
    super.key,
    required this.onDone,
    this.duration = const Duration(milliseconds: 2500),
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  late final List<AnimationController> _dotCtrls;
  late final List<Animation<double>> _dotAnims;

  @override
  void initState() {
    super.initState();

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
    _fadeCtrl.forward();

    // Bouncing dots — staggered loop
    _dotCtrls = List.generate(3, (i) {
      return AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      );
    });
    _dotAnims = List.generate(3, (i) {
      return Tween<double>(begin: 0, end: -12).animate(
        CurvedAnimation(
          parent: _dotCtrls[i],
          curve: const Interval(0, 0.5, curve: Curves.easeOut),
        ),
      );
    });

    for (var i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 150), () {
        _startDotLoop(i);
      });
    }

    Future.delayed(widget.duration, () {
      if (mounted) {
        _fadeCtrl.reverse().then((_) {
          widget.onDone(context);
        });
      }
    });
  }

  void _startDotLoop(int i) {
    if (!mounted) return;
    _dotCtrls[i]
        .forward()
        .then((_) => _dotCtrls[i].reverse())
        .then((_) => _startDotLoop(i));
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    for (final c in _dotCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FadeTransition(
      opacity: _fadeAnim,
      child: Container(
        color: isDark ? NusaConfig.darkBackground : NusaConfig.backgroundColor,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Centered SVG logo — contain ensures no cropping, full visibility
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
                child: SvgPicture.asset(
                  'assets/icons/splash_nusa.svg',
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                ),
              ),
            ),
            // Loading dots overlay at bottom center
            Positioned(
              bottom: 60,
              left: 0,
              right: 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (i) {
                  return AnimatedBuilder(
                    animation: _dotAnims[i],
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(0, _dotAnims[i].value),
                        child: child,
                      );
                    },
                    child: Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        color: NusaConfig.primaryColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Same AnimatedBuilder pattern used elsewhere in the project.
class AnimatedBuilder extends AnimatedWidget {
  final Widget Function(BuildContext, Widget?) builder;
  final Widget? child;

  const AnimatedBuilder({
    super.key,
    required Animation<double> animation,
    required this.builder,
    this.child,
  }) : super(listenable: animation);

  Animation<double> get animation => listenable as Animation<double>;

  @override
  Widget build(BuildContext context) => builder(context, child);
}
