import ImageIO
import UIKit
import Vision

enum OCRError: Error {
    case invalidImage
}

struct OCR {
    static func recognize(_ image: UIImage, mode: ImageMode) async throws -> String {
        let processed = try await ImagePrep.process(image, mode: mode)

        guard let cgImage = processed.cgImage else {
            throw OCRError.invalidImage
        }

        let orientation = processed.imageOrientation.cgOrientation
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false

            let supported = try request.supportedRecognitionLanguages()
            let preferred = ["tr-TR", "en-US"]
            let languages = preferred.filter(supported.contains)

            if !languages.isEmpty {
                request.recognitionLanguages = languages
            }

#if DEBUG
            print("OCR - Vision request revision: \(request.revision)")
            print("OCR - Supported recognition languages: \(supported)")
            print("OCR - Recognition languages in use: \(request.recognitionLanguages)")
#endif

            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: orientation,
                options: [:]
            )

            try handler.perform([request])
            try Task.checkCancellation()

            return request.results?
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n") ?? ""
        }

        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

private extension UIImage.Orientation {
    var cgOrientation: CGImagePropertyOrientation {
        switch self {
        case .up:
            return .up
        case .upMirrored:
            return .upMirrored
        case .down:
            return .down
        case .downMirrored:
            return .downMirrored
        case .left:
            return .left
        case .leftMirrored:
            return .leftMirrored
        case .right:
            return .right
        case .rightMirrored:
            return .rightMirrored
        @unknown default:
            return .up
        }
    }
}
