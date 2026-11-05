/// T35：ホームの泡（六大板块）と、真ん中の球（今の状態）。押すと少し沈む。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/home_snapshot.dart';
import 'water_style.dart';

/// 押している間だけ少し小さくなる（水に沈む感じ）。押し始めに [onPressStart]（波紋を出す）。
class PressableScale extends StatefulWidget {
  const PressableScale({super.key, required this.child, this.onTap, this.onPressStart, this.pressedScale = 0.9});

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onPressStart;
  final double pressedScale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (TapDownDetails _) {
        _set(true);
        widget.onPressStart?.call();
      },
      onTapUp: (TapUpDetails _) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? widget.pressedScale : 1.0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

/// 六大板块の泡。名前・今日の値・示例の印・提醒の点。
class WaterBubble extends StatelessWidget {
  const WaterBubble({super.key, required this.data, this.size = 96, this.onTap, this.onPressStart});

  final BubbleData data;
  final double size;
  final VoidCallback? onTap;
  final VoidCallback? onPressStart;

  @override
  Widget build(BuildContext context) {
    final Color c = boardColor(data.board);
    final String b = data.board.name;
    return Semantics(
      button: true,
      label: '${data.name} ${data.value}${data.demo ? '（示例）' : ''}${data.alert != null ? '，有提醒' : ''}',
      excludeSemantics: true,
      child: PressableScale(
        onTap: onTap,
        onPressStart: onPressStart,
        child: SizedBox.square(
          key: ValueKey<String>('bubble-$b'),
          dimension: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: const Alignment(0, 0.4),
                      radius: 0.8,
                      colors: <Color>[Color.lerp(Colors.white, c, 0.26)!, Colors.white.withValues(alpha: 0.8)],
                    ),
                    border: Border.all(color: Color.lerp(c, Colors.white, 0.3)!, width: 1.5),
                    boxShadow: <BoxShadow>[
                      BoxShadow(color: c.withValues(alpha: 0.28), blurRadius: 22, offset: const Offset(0, 10)),
                    ],
                  ),
                ),
              ),
              const Positioned.fill(child: _Highlight()),
              Padding(
                padding: EdgeInsets.all(size * 0.12),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(boardIcon(data.board), size: 22, color: Color.lerp(c, Colors.black, 0.15)),
                        const SizedBox(height: 2),
                        Text(data.name,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: WaterColors.text)),
                        Text(data.value, style: const TextStyle(fontSize: 11, color: WaterColors.value)),
                        if (data.demo)
                          Text('示例',
                              key: ValueKey<String>('demo-$b'),
                              style: const TextStyle(fontSize: 9.5, color: WaterColors.demo)),
                      ],
                    ),
                  ),
                ),
              ),
              if (data.alert != null)
                Positioned(
                  top: size * 0.06,
                  right: size * 0.1,
                  child: Container(
                    key: ValueKey<String>('alert-dot-$b'),
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: WaterColors.alert,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
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

/// 左上の光（ガラスの球に見せる）。
class _Highlight extends StatelessWidget {
  const _Highlight();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(-0.4, -0.5),
            radius: 0.55,
            colors: <Color>[Colors.white.withValues(alpha: 0.95), Colors.white.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

/// 真ん中の球（ホームボタン）：「现在」・今の状態・続いている時間・今日の提醒の数。
class CoreBubble extends StatelessWidget {
  const CoreBubble({super.key, required this.now, this.footer, this.size = 164, this.onTap, this.onPressStart});

  final NowLine now;

  /// 一番下の小さい文（例：今天没有提醒）。
  final String? footer;
  final double size;
  final VoidCallback? onTap;
  final VoidCallback? onPressStart;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '现在 ${now.title} ${now.sub ?? ''} ${footer ?? ''}',
      excludeSemantics: true,
      child: PressableScale(
        onTap: onTap,
        onPressStart: onPressStart,
        pressedScale: 0.94,
        child: SizedBox.square(
          key: const ValueKey<String>('core-bubble'),
          dimension: size,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      center: Alignment(0, 0.24),
                      radius: 0.75,
                      colors: <Color>[Color(0xFFBEF0FF), Color(0xFF82D7F5), Color(0xFF50B9E6)],
                      stops: <double>[0, 0.6, 1],
                    ),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 2),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                          color: const Color(0xFF28A0D7).withValues(alpha: 0.4), blurRadius: 40, offset: const Offset(0, 14)),
                    ],
                  ),
                ),
              ),
              Positioned.fill(child: ClipOval(child: CustomPaint(painter: _WavePainter()))),
              const Positioned.fill(child: _Highlight()),
              Padding(
                padding: EdgeInsets.all(size * 0.14),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Text('现在',
                            style: TextStyle(fontSize: 12, letterSpacing: 2, color: Color(0xFF1F6F90))),
                        Text(now.title,
                            style: TextStyle(
                                fontSize: now.title.length <= 3 ? 30 : 24,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF06324D))),
                        if (now.sub != null)
                          Text(now.sub!, style: const TextStyle(fontSize: 13, color: Color(0xFF0D4766))),
                        if (footer != null) ...<Widget>[
                          const SizedBox(height: 4),
                          Text(footer!, style: const TextStyle(fontSize: 11, color: Color(0xFF2A7A9C))),
                        ],
                      ],
                    ),
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

/// 球の下の水面（動かない。電池と、テストの pumpAndSettle のため）。
class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    void wave(double baseY, double amp, double phase, Color color) {
      final Path p = Path()..moveTo(0, size.height);
      for (double x = 0; x <= size.width; x += 2) {
        p.lineTo(x, baseY + amp * math.sin(x / size.width * 2 * math.pi * 1.5 + phase));
      }
      p
        ..lineTo(size.width, size.height)
        ..close();
      canvas.drawPath(p, Paint()..color = color);
    }

    wave(size.height * 0.80, 4, 0, Colors.white.withValues(alpha: 0.5));
    wave(size.height * 0.84, 4, 1.4, const Color(0xFF3CB4E6).withValues(alpha: 0.28));
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) => false;
}
