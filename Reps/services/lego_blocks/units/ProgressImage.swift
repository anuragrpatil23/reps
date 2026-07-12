import UIKit

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
}
