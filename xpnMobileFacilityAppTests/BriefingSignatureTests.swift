import UIKit
import XCTest
@testable import mobileFacilityApp

final class BriefingSignatureTests: XCTestCase {
    func testSignatureRasterizerNormalizesWideAndTallSignaturesToOneCanvas() throws {
        let wide = signatureImage(size: CGSize(width: 700, height: 60))
        let tall = signatureImage(size: CGSize(width: 60, height: 220))

        let wideOutput = try XCTUnwrap(
            BriefingSignatureRasterizer.standardizedPNGData(from: wide)
        )
        let tallOutput = try XCTUnwrap(
            BriefingSignatureRasterizer.standardizedPNGData(from: tall)
        )

        // The rasterizer renders at 2x, so the PNG holds the canvas in
        // points at twice the pixels.
        XCTAssertEqual(try XCTUnwrap(UIImage(data: wideOutput, scale: 2)).size, BriefingSignatureRasterizer.canvasSize)
        XCTAssertEqual(try XCTUnwrap(UIImage(data: tallOutput, scale: 2)).size, BriefingSignatureRasterizer.canvasSize)
    }

    private func signatureImage(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
