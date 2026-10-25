import 'package:flutter/material.dart';

/// The app's mark: a paw, drawn rather than shipped as an image.
///
/// Drawn so it is crisp at any size, takes the colour it is given, and can
/// animate — none of which a PNG does. The geometry matches the app icon in
/// `tool/make_icon.py`, so the mark and the icon are the same paw.
class PawMark extends StatelessWidget {
  const PawMark({required this.size, this.color, super.key});

  final double size;

  /// Defaults to the theme's primary.
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _PawPainter(color ?? Theme.of(context).colorScheme.primary),
    ),
  );
}

/// The mark, arriving: toes spring in one after another, then the pad.
///
/// Plays once. Nothing in this app loops forever — a looping animation keeps
/// a widget test awake and an owner's eye busy for no reason.
class AnimatedPawMark extends StatefulWidget {
  const AnimatedPawMark({required this.size, this.color, super.key});

  final double size;
  final Color? color;

  @override
  State<AnimatedPawMark> createState() => _AnimatedPawMarkState();
}

class _AnimatedPawMarkState extends State<AnimatedPawMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.size,
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        painter: _PawPainter(
          widget.color ?? Theme.of(context).colorScheme.primary,
          progress: _controller.value,
        ),
      ),
    ),
  );
}

/// One pad and four toes, in fractions of the canvas.
///
/// The toes sit clear of the pad rather than touching it: merged, the shape
/// reads as a blob at small sizes instead of a paw.
const _pad = (cx: 0.50, cy: 0.70, rx: 0.235, ry: 0.185, rot: 0.0);
const _toes = [
  (cx: 0.215, cy: 0.395, rx: 0.082, ry: 0.108, rot: -0.46),
  (cx: 0.405, cy: 0.275, rx: 0.084, ry: 0.118, rot: -0.16),
  (cx: 0.595, cy: 0.275, rx: 0.084, ry: 0.118, rot: 0.16),
  (cx: 0.785, cy: 0.395, rx: 0.082, ry: 0.108, rot: 0.46),
];

class _PawPainter extends CustomPainter {
  _PawPainter(this.color, {this.progress = 1});

  final Color color;

  /// 0 is nothing drawn, 1 is the finished mark.
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;

    // Toes first, each one a little behind the last, then the pad lands.
    for (var index = 0; index < _toes.length; index++) {
      final start = index * 0.11;
      _drawEllipse(
        canvas,
        size,
        paint,
        _toes[index],
        _eased(progress, start, start + 0.45),
      );
    }
    _drawEllipse(canvas, size, paint, _pad, _eased(progress, 0.3, 0.9));
  }

  /// [progress] remapped to 0..1 across [start]..[end], then eased with a
  /// slight overshoot so the shape arrives with a bit of life.
  double _eased(double progress, double start, double end) {
    final t = ((progress - start) / (end - start)).clamp(0.0, 1.0);
    return Curves.easeOutBack.transform(t);
  }

  void _drawEllipse(
    Canvas canvas,
    Size size,
    Paint paint,
    ({double cx, double cy, double rx, double ry, double rot}) shape,
    double scale,
  ) {
    if (scale <= 0) {
      return;
    }
    final centre = Offset(shape.cx * size.width, shape.cy * size.height);

    canvas
      ..save()
      ..translate(centre.dx, centre.dy)
      ..rotate(shape.rot)
      ..scale(scale)
      ..drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: shape.rx * 2 * size.width,
          height: shape.ry * 2 * size.height,
        ),
        paint,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_PawPainter old) =>
      old.color != color || old.progress != progress;
}

/// The wordmark: the paw beside the name.
class PawLogo extends StatelessWidget {
  const PawLogo({this.size = 40, this.animate = false, super.key});

  final double size;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (animate)
          AnimatedPawMark(size: size)
        else
          PawMark(size: size),
        SizedBox(width: size * 0.3),
        Text(
          'Paws Log',
          style: theme.textTheme.displaySmall?.copyWith(
            fontSize: size * 0.82,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }
}

