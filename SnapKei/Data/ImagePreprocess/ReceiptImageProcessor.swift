import Foundation
#if canImport(UIKit)
import UIKit
#endif

public enum ReceiptImageProcessor {
    #if canImport(UIKit)
    public static func jpegData(from image: UIImage, maxDimension: CGFloat = 1600, compressionQuality: CGFloat = 0.82) throws -> Data {
        let resized = resize(image, maxDimension: maxDimension)
        guard let data = resized.jpegData(compressionQuality: compressionQuality) else {
            throw AIServiceError.invalidResponse("failed to encode jpeg")
        }
        return data
    }

    private static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let largest = max(image.size.width, image.size.height)
        guard largest > maxDimension else { return image }
        let scale = maxDimension / largest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
    #endif
}
