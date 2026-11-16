import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'booth_event_theme.dart';

class BoothThemeBackgroundPainter extends CustomPainter {
  const BoothThemeBackgroundPainter({required this.theme, this.animation})
    : super(repaint: animation);

  final BoothEventTheme theme;
  final Animation<double>? animation;

  @override
  void paint(Canvas canvas, Size size) {
    final phase = animation?.value ?? 0;
    if (_isCoffeeTheme) {
      _paintCoffeePattern(canvas, size, phase);
      return;
    }
    final columns = size.width >= size.height ? 6 : 4;
    final rows = size.width >= size.height ? 4 : 6;
    final cellWidth = size.width / columns;
    final cellHeight = size.height / rows;
    final unit = math.min(cellWidth, cellHeight) * 0.68;
    for (var index = 0; index < columns * rows; index++) {
      final row = index ~/ columns;
      final column = index % columns;
      final stagger = row.isEven ? 0.0 : cellWidth * 0.5;
      final baseX = ((column + 0.5) * cellWidth + stagger) % size.width;
      final baseY = (row + 0.5) * cellHeight;
      final drift = math.sin((phase * math.pi * 2) + index * 1.7);
      final x = baseX + drift * cellWidth * 0.035;
      final y = baseY + drift * cellHeight * 0.035;
      final rotation = ((index * 37) % 17 - 8) * math.pi / 90 + drift * 0.035;
      final scale = 1 + math.sin(phase * math.pi * 2 + index) * 0.025;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation);
      canvas.scale(scale);
      switch (theme) {
        case BoothEventTheme.coffeeBeans:
          _drawCoffeeBean(canvas, unit * 0.58);
        case BoothEventTheme.coffeeCup:
          _drawCoffeeCup(canvas, unit, latteArt: false);
        case BoothEventTheme.latteArt:
          _drawCoffeeCup(canvas, unit, latteArt: true);
        case BoothEventTheme.valentines:
        case BoothEventTheme.wedding:
          _drawHeart(canvas, unit * 0.82);
        case BoothEventTheme.holiday:
          _drawSnowflake(canvas, unit * 0.78);
        case BoothEventTheme.birthday:
          _drawBalloon(canvas, unit * 0.8, index.isEven, drift);
        case BoothEventTheme.graduation:
          _drawGraduationCap(canvas, unit * 0.8);
        case BoothEventTheme.summer:
          _drawSun(canvas, unit * 0.82);
        case BoothEventTheme.classic:
          _drawClassicCamera(canvas, unit * 0.78);
      }
      canvas.restore();
    }
  }

  bool get _isCoffeeTheme =>
      theme == BoothEventTheme.coffeeBeans ||
      theme == BoothEventTheme.coffeeCup ||
      theme == BoothEventTheme.latteArt;

  void _paintCoffeePattern(Canvas canvas, Size size, double phase) {
    final columns = size.width >= size.height ? 6 : 4;
    final rows = size.width >= size.height ? 4 : 6;
    final cellWidth = size.width / columns;
    final cellHeight = size.height / rows;
    final unit = math.min(cellWidth, cellHeight) * 0.58;
    var motif = 0;
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final stagger = row.isEven ? 0.0 : cellWidth * 0.5;
        final baseX = ((column + 0.5) * cellWidth + stagger) % size.width;
        final baseY = (row + 0.5) * cellHeight;
        final drift = math.sin(phase * math.pi * 2 + motif * 1.7);
        final x = baseX + drift * cellWidth * 0.035;
        final y = baseY + drift * cellHeight * 0.035;
        final drawBean = switch (theme) {
          BoothEventTheme.coffeeBeans => motif % 3 != 0,
          BoothEventTheme.coffeeCup => motif % 5 == 0,
          BoothEventTheme.latteArt => motif.isEven,
          _ => false,
        };
        final rotation = ((motif * 37) % 17 - 8) * math.pi / 90 + drift * 0.035;
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(rotation);
        canvas.scale(1 + drift * 0.025);
        if (drawBean) {
          _drawCoffeeBean(canvas, unit * 0.58);
        } else {
          _drawCoffeeCup(
            canvas,
            unit,
            latteArt: theme == BoothEventTheme.latteArt,
          );
        }
        canvas.restore();
        motif++;
      }
    }
  }

  void _drawCoffeeBean(Canvas canvas, double size) {
    final beanRect = Rect.fromCenter(
      center: Offset.zero,
      width: size * 0.55,
      height: size,
    );
    final shadow = Paint()
      ..color = const Color(0x14805A3D)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawOval(beanRect.shift(Offset(size * 0.035, size * 0.045)), shadow);
    final fill = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0x18D1A47D), Color(0x32A66B3F), Color(0x16E0B98D)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(beanRect);
    final line = Paint()
      ..color = const Color(0x3D8B5E3C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawOval(beanRect, fill);
    canvas.drawOval(beanRect, line);
    final seam = Path()
      ..moveTo(0, -size * 0.38)
      ..cubicTo(
        -size * 0.2,
        -size * 0.12,
        size * 0.2,
        size * 0.1,
        0,
        size * 0.38,
      );
    canvas.drawPath(seam, line);
  }

  void _drawCoffeeCup(Canvas canvas, double size, {required bool latteArt}) {
    final saucer = Rect.fromCenter(
      center: Offset(0, size * 0.34),
      width: size * 0.82,
      height: size * 0.15,
    );
    canvas.drawOval(
      saucer.shift(Offset(0, size * 0.035)),
      Paint()
        ..color = const Color(0x14805A3D)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    final outline = Paint()
      ..color = const Color(0x3D9B6B46)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    final cupBounds = Rect.fromLTRB(
      -size * 0.34,
      -size * 0.1,
      size * 0.34,
      size * 0.36,
    );
    final cupFill = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0x20FFFFFF), Color(0x19C89B70), Color(0x12A96F48)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(cupBounds);
    final cup = Path()
      ..moveTo(-size * 0.34, -size * 0.1)
      ..lineTo(size * 0.34, -size * 0.1)
      ..lineTo(size * 0.26, size * 0.28)
      ..quadraticBezierTo(0, size * 0.4, -size * 0.26, size * 0.28)
      ..close();
    canvas.drawPath(cup, cupFill);
    canvas.drawPath(cup, outline);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(0, -size * 0.1),
        width: size * 0.68,
        height: size * 0.13,
      ),
      Paint()..color = const Color(0x1FA67854),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size * 0.38, size * 0.06),
        width: size * 0.24,
        height: size * 0.28,
      ),
      outline,
    );
    canvas.drawLine(
      Offset(-size * 0.3, size * 0.35),
      Offset(size * 0.3, size * 0.35),
      outline,
    );

    canvas.drawOval(saucer, outline);
    final steam = Paint()
      ..color = const Color(0x339B6B46)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round;
    for (final x in [-0.16, 0.0, 0.16]) {
      final path = Path()
        ..moveTo(size * x, -size * 0.2)
        ..cubicTo(
          size * (x - 0.08),
          -size * 0.36,
          size * (x + 0.08),
          -size * 0.43,
          size * x,
          -size * 0.56,
        );
      canvas.drawPath(path, steam);
    }

    if (latteArt) {
      final heartPaint = Paint()..color = const Color(0x407D5135);
      final heart = Path()
        ..moveTo(0, size * 0.17)
        ..cubicTo(-size * 0.23, size * 0.02, -size * 0.18, -size * 0.1, 0, 0)
        ..cubicTo(
          size * 0.18,
          -size * 0.1,
          size * 0.23,
          size * 0.02,
          0,
          size * 0.17,
        );
      canvas.drawPath(heart, heartPaint);
    }
  }

  void _drawHeart(Canvas canvas, double size) {
    final fill = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0x1EEA9BA9), Color(0x24D87588), Color(0x16B84966)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTRB(-size, -size, size, size));
    final outline = Paint()
      ..color = const Color(0x45C45F76)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final heart = Path()
      ..moveTo(0, size * 0.42)
      ..cubicTo(
        -size * 0.92,
        -size * 0.08,
        -size * 0.42,
        -size * 0.82,
        0,
        -size * 0.34,
      )
      ..cubicTo(
        size * 0.42,
        -size * 0.82,
        size * 0.92,
        -size * 0.08,
        0,
        size * 0.42,
      )
      ..close();
    canvas.drawPath(heart, fill);
    canvas.drawPath(heart, outline);
  }

  void _drawSnowflake(Canvas canvas, double size) {
    final paint = Paint()
      ..color = const Color(0x4584B7D3)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var branch = 0; branch < 6; branch++) {
      final angle = branch * math.pi / 3;
      final dx = math.cos(angle) * size * 0.42;
      final dy = math.sin(angle) * size * 0.42;
      canvas.drawLine(Offset(-dx, -dy), Offset(dx, dy), paint);
    }
  }

  void _drawBalloon(Canvas canvas, double size, bool alternate, double drift) {
    final balloon = Rect.fromCenter(
      center: Offset(0, -size * 0.12),
      width: size * 0.56,
      height: size * 0.72,
    );
    final fill = Paint()
      ..shader = LinearGradient(
        colors: alternate
            ? const [Color(0x16FFE0E5), Color(0x29E58A9B), Color(0x18B9516B)]
            : const [Color(0x16E5F4FF), Color(0x2D8CB8D8), Color(0x183D78AA)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(balloon);
    final outline = Paint()
      ..color = const Color(0x448B9EB4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawOval(balloon, fill);
    canvas.drawOval(balloon, outline);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-size * 0.12, -size * 0.25),
        width: size * 0.10,
        height: size * 0.23,
      ),
      Paint()..color = const Color(0x3DFFFFFF),
    );
    canvas.drawLine(
      Offset(0, size * 0.24),
      Offset(size * (0.08 + drift * 0.1), size * 0.53),
      outline,
    );
  }

  void _drawGraduationCap(Canvas canvas, double size) {
    final fill = Paint()..color = const Color(0x243E607A);
    final outline = Paint()
      ..color = const Color(0x443E607A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7;
    final cap = Path()
      ..moveTo(-size * 0.5, -size * 0.05)
      ..lineTo(0, -size * 0.32)
      ..lineTo(size * 0.5, -size * 0.05)
      ..lineTo(0, size * 0.2)
      ..close();
    canvas.drawPath(cap, fill);
    canvas.drawPath(cap, outline);
    canvas.drawLine(
      Offset(-size * 0.32, size * 0.02),
      Offset(-size * 0.32, size * 0.28),
      outline,
    );
    canvas.drawLine(
      Offset(-size * 0.32, size * 0.28),
      Offset(size * 0.25, size * 0.28),
      outline,
    );
  }

  void _drawSun(Canvas canvas, double size) {
    final glowPaint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0x2DBA8C42), Color(0x0DBA8C42), Color(0x00BA8C42)],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: size * 0.50));
    canvas.drawCircle(Offset.zero, size * 0.50, glowPaint);
    final paint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0x35FFE4A0), Color(0x3DBA8C42)],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: size * 0.24))
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(Offset.zero, size * 0.22, paint);
    for (var ray = 0; ray < 8; ray++) {
      final angle = ray * math.pi / 4;
      final inner = size * 0.34;
      final outer = size * 0.46;
      canvas.drawLine(
        Offset(math.cos(angle) * inner, math.sin(angle) * inner),
        Offset(math.cos(angle) * outer, math.sin(angle) * outer),
        paint,
      );
    }
  }

  void _drawClassicCamera(Canvas canvas, double size) {
    final outline = Paint()
      ..color = const Color(0x302F3B4B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset.zero,
        width: size * 0.78,
        height: size * 0.52,
      ),
      Radius.circular(size * 0.08),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0x17FFFFFF), Color(0x102F3B4B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(body.outerRect),
    );
    canvas.drawRRect(body, outline);
    canvas.drawCircle(
      Offset.zero,
      size * 0.17,
      Paint()
        ..shader =
            const RadialGradient(
              colors: [Color(0x193B536B), Color(0x0BFFFFFF), Color(0x202F3B4B)],
            ).createShader(
              Rect.fromCircle(center: Offset.zero, radius: size * 0.17),
            ),
    );
    canvas.drawCircle(Offset.zero, size * 0.17, outline);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-size * 0.23, -size * 0.40, size * 0.30, size * 0.12),
        Radius.circular(size * 0.03),
      ),
      outline,
    );
    canvas.drawCircle(
      Offset(size * 0.25, -size * 0.13),
      size * 0.035,
      Paint()..color = const Color(0x302F3B4B),
    );
  }

  @override
  bool shouldRepaint(BoothThemeBackgroundPainter oldDelegate) =>
      oldDelegate.theme != theme;
}
