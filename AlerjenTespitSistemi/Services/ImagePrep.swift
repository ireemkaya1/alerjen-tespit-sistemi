import CoreImage
import UIKit

enum ImageMode: String, CaseIterable, Identifiable {
    case original
    case grayscale
    case enhanced

    var id: Self { self }

    var title: String {
        switch self {
        case .original:
            return "Orijinal"
        case .grayscale:
            return "Gri Tonlama"
        case .enhanced:
            return "İyileştirilmiş"
        }
    }
}

enum ImagePrepError: Error {
    case invalidImage
    case processingFailed
}

struct ImagePrep {
    nonisolated private static let context = CIContext()

    static func process(_ image: UIImage, mode: ImageMode) async throws -> UIImage {
        guard mode != .original else { return image }
        guard let cgImage = image.cgImage else {
            throw ImagePrepError.invalidImage
        }

        let scale = image.scale
        let orientation = image.imageOrientation

        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()

            let input = CIImage(cgImage: cgImage)
            let output: CIImage

            switch mode {
            case .original:
                output = input
            case .grayscale:
                guard let filter = CIFilter(name: "CIColorControls") else {
                    throw ImagePrepError.processingFailed
                }
                filter.setValue(input, forKey: kCIInputImageKey)
                filter.setValue(0.0, forKey: kCIInputSaturationKey)
                filter.setValue(1.0, forKey: kCIInputContrastKey)
                guard let result = filter.outputImage else {
                    throw ImagePrepError.processingFailed
                }
                output = result
            case .enhanced:
                guard let contrast = CIFilter(name: "CIColorControls"),
                      let sharpen = CIFilter(name: "CISharpenLuminance") else {
                    throw ImagePrepError.processingFailed
                }

                contrast.setValue(input, forKey: kCIInputImageKey)
                contrast.setValue(1.15, forKey: kCIInputContrastKey)

                guard let contrasted = contrast.outputImage else {
                    throw ImagePrepError.processingFailed
                }

                sharpen.setValue(contrasted, forKey: kCIInputImageKey)
                sharpen.setValue(0.4, forKey: kCIInputSharpnessKey)

                guard let result = sharpen.outputImage else {
                    throw ImagePrepError.processingFailed
                }
                output = result
            }

            try Task.checkCancellation()

            guard let result = context.createCGImage(output, from: input.extent) else {
                throw ImagePrepError.processingFailed
            }

            try Task.checkCancellation()
            return UIImage(cgImage: result, scale: scale, orientation: orientation)
        }

        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
