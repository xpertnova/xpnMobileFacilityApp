import CoreGraphics
import UIKit

/// Turns a payload string into a scannable QR code bitmap.
///
/// The modules come from `QRCodeMatrix` and are drawn straight onto a bitmap,
/// with no CoreImage anywhere: `CIFilter.qrCodeGenerator()` was measured at
/// 7.5 s on its first use in a process on an iPad, and it blocks the main
/// thread from the inside while it builds, so no amount of moving the call to
/// another thread hid it. This takes microseconds.
///
/// One pixel per module would leave the card scaling the bitmap by a fraction
/// and the modules unequal in width, so the bitmap is enlarged by a whole
/// number instead. Draw it with nearest-neighbour sampling
/// (`interpolation(.none)`) to keep the modules square.
enum QRCodeImageRenderer {
    /// Pixels per QR module in the returned bitmap. Enough that a code shown
    /// at roughly 200 pt on an iPad still has whole pixels per module after
    /// the view scales it down.
    static let moduleScale: CGFloat = 12

    static func image(for payload: String) -> UIImage? {
        guard let matrix = QRCodeMatrix.encode(payload) else { return nil }
        let scale = Int(moduleScale)
        let dimension = matrix.size * scale
        guard let context = CGContext(
            data: nil,
            width: dimension,
            height: dimension,
            bitsPerComponent: 8,
            bytesPerRow: dimension,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: dimension, height: dimension))
        context.setFillColor(gray: 0, alpha: 1)
        for row in 0..<matrix.size {
            for column in 0..<matrix.size where matrix[column, row] {
                // A bitmap's origin is at the bottom; the matrix's is at the top.
                context.fill(CGRect(
                    x: column * scale,
                    y: (matrix.size - 1 - row) * scale,
                    width: scale,
                    height: scale
                ))
            }
        }
        return context.makeImage().map(UIImage.init(cgImage:))
    }
}
