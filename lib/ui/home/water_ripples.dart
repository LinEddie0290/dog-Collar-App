/// T35：泡を押したときに広がる水の波紋。
///
/// 使い方：`GlobalKey<WaterRipplesState>` を付けて置き、`key.currentState?.add(中心, 色)`。
/// 波紋 1 つにつき 1 つの小さなウィジェット（自分のアニメーションを持つ）。終わったら消える
/// （止まったあとに動き続けるものを残さない）。
library;

import 'package:flutter/material.dart';

class WaterRipples extends StatefulWidget {
  const WaterRipples({super.key, required this.child, this.duration = const Duration(milliseconds: 900)});

  final Widget child;
  final Duration duration;

  @override
  State<WaterRipples> createState() => WaterRipplesState();
}

class _RippleSpec {
  _RippleSpec(this.id, this.center, this.color, this.startRadius, this.spread);

  final int id;
  final Offset center;
  final Color color;
  final double startRadius;
  final double spread;
}

class WaterRipplesState extends State<WaterRipples> {
  final List<_RippleSpec> _specs = <_RippleSpec>[];
  int _next = 0;

  /// 今出ている波紋の数（テスト用）。
  int get activeCount => _specs.length;

  /// [center] はこのウィジェットの中の位置。[startRadius] は泡の半径くらい。
  void add(Offset center, Color color, {double startRadius = 40, double spread = 110}) {
    setState(() => _specs.add(_RippleSpec(_next++, center, color, startRadius, spread)));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        widget.child,
        for (final _RippleSpec s in _specs)
          Positioned.fill(
            child: IgnorePointer(
              child: _RippleView(
                key: ValueKey<int>(s.id),
                spec: s,
                duration: widget.duration,
                onDone: () {
                  if (mounted) setState(() => _specs.remove(s));
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _RippleView extends StatefulWidget {
  const _RippleView({super.key, required this.spec, required this.duration, required this.onDone});

  final _RippleSpec spec;
  final Duration duration;
  final VoidCallback onDone;

  @override
  State<_RippleView> createState() => _RippleViewState();
}

class _RippleViewState extends State<_RippleView> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration)
    ..addStatusListener((AnimationStatus st) {
      if (st == AnimationStatus.completed) widget.onDone();
    })
    ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (BuildContext context, Widget? _) =>
          CustomPaint(painter: _RipplePainter(widget.spec, _c.value)),
    );
  }
}

class _RipplePainter extends CustomPainter {
  _RipplePainter(this.spec, this.t);

  final _RippleSpec spec;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    // 3 つの輪を少しずつずらして広げる。外に行くほど薄く・細く
    for (int k = 0; k < 3; k++) {
      final double tk = ((t - k * 0.18) / 0.64).clamp(0.0, 1.0);
      if (tk <= 0 || tk >= 1) continue;
      final double r = spec.startRadius + spec.spread * Curves.easeOut.transform(tk);
      final double fade = 1 - tk;
      if (k == 0) {
        canvas.drawCircle(spec.center, r, Paint()..color = spec.color.withValues(alpha: 0.10 * fade));
      }
      canvas.drawCircle(
        spec.center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5 + 2.5 * fade
          ..color = spec.color.withValues(alpha: 0.75 * fade),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RipplePainter old) => old.t != t || old.spec != spec;
}
