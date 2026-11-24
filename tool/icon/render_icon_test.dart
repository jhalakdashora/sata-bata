// Renders the launcher icon PNGs from code, so the logo follows the brand
// colors in lib/app/brand.dart.
//
//   flutter test tool/icon/render_icon_test.dart
//   dart run flutter_launcher_icons
//
// Writes assets/icon/icon.png (full icon) and assets/icon/foreground.png
// (transparent glyph for Android adaptive icons).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:split_app/app/brand.dart';

const _size = 1024.0;
final Color _deep = Color.lerp(Brand.seedColor, const Color(0xFF0B2E4A), 0.6)!;

/// Split arrow: one stem splitting into two arrows, plus a gold coin.
/// [scale] shrinks the glyph (adaptive icons crop the outer third).
void _paintGlyph(Canvas canvas, double scale) {
  canvas
    ..save()
    ..translate(_size / 2, _size / 2)
    ..scale(scale)
    ..translate(-_size / 2, -_size / 2);

  final stroke = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = 84
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  const fork = Offset(512, 580);
  const left = Offset(286, 330);
  const right = Offset(738, 330);
  const head = 140.0;
  canvas
    ..drawPath(
      Path()
        ..moveTo(512, 820)
        ..lineTo(fork.dx, fork.dy)
        ..lineTo(left.dx, left.dy)
        ..moveTo(fork.dx, fork.dy)
        ..lineTo(right.dx, right.dy),
      stroke,
    )
    // Arrow heads (open chevrons) at each branch end.
    ..drawPath(
      Path()
        ..moveTo(left.dx, left.dy + head)
        ..lineTo(left.dx, left.dy)
        ..lineTo(left.dx + head, left.dy),
      stroke,
    )
    ..drawPath(
      Path()
        ..moveTo(right.dx - head, right.dy)
        ..lineTo(right.dx, right.dy)
        ..lineTo(right.dx, right.dy + head),
      stroke,
    )
    // Gold coin where the bill splits.
    ..drawCircle(fork, 66, Paint()..color = Brand.proColor)
    ..drawCircle(
      fork,
      66,
      Paint()
        ..color = _deep
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18,
    )
    ..restore();
}

void _paintBackground(Canvas canvas) {
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, _size, _size),
    Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        const Offset(_size, _size),
        [Brand.seedColor, _deep],
      ),
  );
}

Future<void> _write(String path, void Function(Canvas) paint) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder));
  final image = await recorder.endRecording().toImage(
    _size.toInt(),
    _size.toInt(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  testWidgets('render launcher icons', (tester) async {
    await tester.runAsync(() async {
      await _write('assets/icon/icon.png', (c) {
        _paintBackground(c);
        _paintGlyph(c, 0.82);
      });
      // Adaptive icon: the launcher crops to a circle/squircle, so keep the
      // glyph inside the central safe circle.
      await _write('assets/icon/foreground.png', (c) => _paintGlyph(c, 0.64));
      // Preview of a round launcher icon: Android shows the middle 72dp of
      // the 108dp adaptive layers. Not shipped; for eyeballing only.
      await _write('build/icon_preview_round.png', (c) {
        const visible = 72 / 108;
        c
          ..clipPath(
            Path()..addOval(
              Rect.fromCircle(center: const Offset(512, 512), radius: 512),
            ),
          )
          ..translate(512, 512)
          ..scale(1 / visible)
          ..translate(-512, -512)
          ..drawRect(
            const Rect.fromLTWH(0, 0, _size, _size),
            Paint()..color = Brand.seedColor,
          );
        _paintGlyph(c, 0.64);
      });
    });
  });
}
