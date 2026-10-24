import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:paws_log/services/prescriptions/ocr_service.dart';

/// Proves the OCR engine actually reads text on this platform.
///
/// Nothing else can: the unit tests feed the parser a string, and a mocked
/// engine would only prove the mock works. This renders real text to a real
/// image and asks the real recogniser what it says.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Draws [lines] onto a white page and writes it out as a PNG.
  Future<String> renderPage(List<String> lines) async {
    const width = 1000.0;
    const lineHeight = 70.0;
    final height = 120 + lines.length * lineHeight;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..drawRect(
        Rect.fromLTWH(0, 0, width, height),
        Paint()..color = const Color(0xFFFFFFFF),
      );

    for (var index = 0; index < lines.length; index++) {
      final painter = TextPainter(
        text: TextSpan(
          text: lines[index],
          style: const TextStyle(
            color: Color(0xFF000000),
            fontSize: 40,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width - 120);
      painter.paint(canvas, Offset(60, 60 + index * lineHeight));
    }

    final image = await recorder.endRecording().toImage(
      width.toInt(),
      height.toInt(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/ocr-page.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    return file.path;
  }

  testWidgets('the device reads text off an image', (tester) async {
    const service = VisionOcrService();
    final path = await renderPage([
      'Riverside Veterinary Practice',
      'Amoxicillin 50mg',
      'Give twice daily for 7 days',
    ]);

    final text = await service.recognise(path);
    debugPrint('OCR RESULT >>>\n$text\n<<<');

    expect(text, isNotEmpty, reason: 'the engine read nothing at all');
    expect(text.toLowerCase(), contains('amoxicillin'));
    expect(text.toLowerCase(), contains('twice daily'));
    expect(text.toLowerCase(), contains('7 days'));
  });

  testWidgets('an unreadable path fails softly rather than throwing', (
    tester,
  ) async {
    // The owner still has the image and can fill the fields in by hand; an
    // OCR failure must never take the flow down.
    const service = VisionOcrService();

    expect(await service.recognise('/not/a/real/file.png'), isEmpty);
  });
}
