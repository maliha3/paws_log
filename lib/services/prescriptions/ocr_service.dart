import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Reads text off an image, on the device.
///
/// An interface so the prescription flow, its parser and its tests never
/// touch a platform channel. It is also what lets the engine change without
/// anything above it noticing — which already happened once.
abstract interface class OcrService {
  /// The recognised text of the image at [path], one line per line found, in
  /// reading order. Empty when nothing could be read.
  Future<String> recognise(String path);
}

/// Apple's Vision framework, through a method channel.
///
/// Vision rather than ML Kit: it ships with iOS, so it costs nothing in app
/// size, and its frameworks build for the arm64 simulator. ML Kit's do not,
/// which would have made the simulator — and with it every integration test
/// and screenshot — unusable for the whole app.
class VisionOcrService implements OcrService {
  const VisionOcrService();

  static const MethodChannel _channel = MethodChannel('paws_log/ocr');

  @override
  Future<String> recognise(String path) async {
    try {
      final text = await _channel.invokeMethod<String>('recognize', {
        'path': path,
      });
      return text ?? '';
    } on PlatformException catch (error) {
      // An unreadable page is not a crash. The owner still has the image,
      // and can fill the fields in by hand.
      debugPrint('Could not read text from $path: ${error.message}');
      return '';
    } on MissingPluginException {
      // Android, or a test host. Same answer: no text, nothing broken.
      return '';
    }
  }
}

/// Returns whatever it was given. For tests and for platforms with no engine.
@visibleForTesting
class FixedOcrService implements OcrService {
  const FixedOcrService(this.text);

  final String text;

  @override
  Future<String> recognise(String path) async => text;
}
