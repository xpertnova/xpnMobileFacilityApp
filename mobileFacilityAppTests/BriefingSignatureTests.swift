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

        XCTAssertEqual(try XCTUnwrap(UIImage(data: wideOutput)).size, BriefingSignatureRasterizer.canvasSize)
        XCTAssertEqual(try XCTUnwrap(UIImage(data: tallOutput)).size, BriefingSignatureRasterizer.canvasSize)
    }

    private func signatureImage(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
