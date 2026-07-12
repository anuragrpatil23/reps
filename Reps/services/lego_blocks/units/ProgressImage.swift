import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Progress pics only need enough detail to compare a silhouette over time,
/// not a 3 MB 12 MP original. We downscale to a sane max dimension and
/// JPEG-compress, which also drops the original's EXIF/GPS metadata (privacy +
/// size). Typical output: ~100–250 KB.
enum ProgressImage {
    static let maxDimension: CGFloat = 1280
    static let quality: CGFloat = 0.7

    /// Downscale + compress to JPEG bytes for the vault.
    static func encode(_ image: UIImage,
                       maxDimension: CGFloat = maxDimension,
                       quality: CGFloat = quality) -> Data? {
        downscaled(image, maxDimension: maxDimension).jpegData(compressionQuality: quality)
    }

    /// Fit within `maxDimension` on the longest edge, normalizing orientation.
    /// Renders at 1:1 pixel scale so the output is exactly the pixel size we want.
    static func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: (image.size.width * scale).rounded(),
                            height: (image.size.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true   // no alpha → smaller JPEG
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// A heavily-blurred, illegible thumbnail for the locked state. We downscale
    /// hard first so the blur is cheap and the source detail is gone before the
    /// pixels ever reach the view tree — a screenshot of this shows only a smear.
    static func blurredThumb(_ data: Data,
                             maxDimension: CGFloat = 220,
                             radius: Double = 16) -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        let small = downscaled(image, maxDimension: maxDimension)
        guard let input = CIImage(image: small) else { return nil }

        let filter = CIFilter.gaussianBlur()
        filter.inputImage = input.clampedToExtent()   // avoid transparent edges
        filter.radius = Float(radius)
        guard let output = filter.outputImage else { return nil }

        let context = CIContext()
        guard let cg = context.createCGImage(output, from: input.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
