import 'package:flutter/material.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';

/// 3-box geometric loading animation — converted from CSS keyframes.
/// Clean, smooth, and lightweight.
class NusaLoadingAnimation extends StatefulWidget {
  final String statusText;
  const NusaLoadingAnimation({super.key, this.statusText = 'Menghubungkan ke Google...'});

  @override
  State<NusaLoadingAnimation> createState() => _NusaLoadingAnimationState();
}

class _NusaLoadingAnimationState extends State<NusaLoadingAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    );
    // 1s initial delay then loop
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) _ctrl.repeat();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 112,
          height: 112,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => CustomPaint(
              size: const Size(112, 112),
              painter: _BoxPainter(_ctrl.value),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          widget.statusText,
          style: TextStyle(
            color: isDark ? NusaConfig.darkTextSecondary : Colors.grey.shade500,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Each box at a given time [t] (0..1) returns (x, y, w, h).
typedef _BoxRect = ({double x, double y, double w, double h});

class _BoxPainter extends CustomPainter {
  final double t;
  _BoxPainter(this.t);

  // Approximated from CSS keyframes — each box morphs through positions.
  static _BoxRect _box1(double t) {
    if (t < 0.125) return (x: 0, y: 64, w: 112, h: 48);
    if (t < 0.625) return (x: 0, y: 64, w: 48, h: 48);
    if (t < 0.750) return (x: 0, y: 0, w: 48, h: 112);
    return (x: 0, y: 0, w: 48, h: 48);
  }

  static _BoxRect _box2(double t) {
    if (t < 0.375) return (x: 0, y: 0, w: 48, h: 48);
    if (t < 0.500) return (x: 0, y: 0, w: 112, h: 48);
    return (x: 64, y: 0, w: 48, h: 48);
  }

  static _BoxRect _box3(double t) {
    if (t < 0.125) return (x: 64, y: 0, w: 48, h: 48);
    if (t < 0.250) return (x: 64, y: 0, w: 48, h: 112);
    if (t < 0.375) return (x: 64, y: 64, w: 48, h: 48);
    if (t < 0.875) return (x: 64, y: 64, w: 48, h: 48);
    return (x: 0, y: 64, w: 112, h: 48);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final boxPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..color = const Color(0xFFE63946)
      ..strokeCap = StrokeCap.round;

    for (final fn in [_box1, _box2, _box3]) {
      final r = fn(t);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(r.x, r.y, r.w, r.h),
          topLeft: const Radius.circular(10),
          topRight: const Radius.circular(10),
          bottomLeft: const Radius.circular(10),
          bottomRight: const Radius.circular(10),
        ),
        boxPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BoxPainter old) => t != old.t;
}
