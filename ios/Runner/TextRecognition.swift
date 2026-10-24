import Flutter
import UIKit
import Vision

/// On-device text recognition, using Apple's Vision framework.
///
/// Vision rather than a third-party OCR package: it is part of iOS, so it
/// adds nothing to the download, runs entirely on the device, and — unlike
/// ML Kit's binaries — builds for the arm64 simulator, which is what keeps
/// the whole test and screenshot loop working.
enum TextRecognition {
  static let channelName = "paws_log/ocr"

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "recognize" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let path = arguments["path"] as? String
      else {
        result(
          FlutterError(
            code: "bad_arguments",
            message: "recognize needs a file path",
            details: nil
          )
        )
        return
      }
      recognize(path: path, result: result)
    }
  }

  private static func recognize(path: String, result: @escaping FlutterResult) {
    guard
      let image = UIImage(contentsOfFile: path),
      let cgImage = image.cgImage
    else {
      result(
        FlutterError(
          code: "unreadable",
          message: "Could not read an image at \(path)",
          details: nil
        )
      )
      return
    }

    // Off the main thread: recognition on a full-page scan is slow enough to
    // drop frames if it runs where the UI does.
    DispatchQueue.global(qos: .userInitiated).async {
      let request = VNRecognizeTextRequest { request, error in
        if let error = error {
          DispatchQueue.main.async {
            result(
              FlutterError(
                code: "failed",
                message: error.localizedDescription,
                details: nil
              )
            )
          }
          return
        }

        let observations =
          request.results as? [VNRecognizedTextObservation] ?? []
        // One line per observation, in reading order, which is what a
        // prescription parser expects to walk through.
        let lines = observations.compactMap {
          $0.topCandidates(1).first?.string
        }
        DispatchQueue.main.async {
          result(lines.joined(separator: "\n"))
        }
      }

      // Accurate over fast: a prescription is read once and then relied on.
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true

      let handler = VNImageRequestHandler(
        cgImage: cgImage,
        orientation: image.cgImagePropertyOrientation,
        options: [:]
      )
      do {
        try handler.perform([request])
      } catch {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "failed",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      }
    }
  }
}

private extension UIImage {
  /// Vision works on the raw pixels and ignores a UIImage's orientation, so
  /// a photo taken in portrait would be read sideways without this.
  var cgImagePropertyOrientation: CGImagePropertyOrientation {
    switch imageOrientation {
    case .up: return .up
    case .down: return .down
    case .left: return .left
    case .right: return .right
    case .upMirrored: return .upMirrored
    case .downMirrored: return .downMirrored
    case .leftMirrored: return .leftMirrored
    case .rightMirrored: return .rightMirrored
    @unknown default: return .up
    }
  }
}
