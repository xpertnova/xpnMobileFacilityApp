import XCTest
@testable import mobileFacilityApp

/// The app generates its own QR codes instead of asking CoreImage for them,
/// so these tests stand in for the reference implementation that used to do
/// the work. The fixture below is the code Apple's own generator produces for
/// a real functional location at error-correction level M, taken module by
/// module: a code that has to be scannable by the same readers.
final class QRCodeMatrixTests: XCTestCase {
    /// `{"EQUNR":"%","STEUS":"","STRNO":"DE-NIZ-11143-03-440-001"}`, base64
    /// encoded — the legacy MTFM payload for a real functional location.
    private let payload = "eyJFUVVOUiI6IiUiLCJTVEVVUyI6IiIsIlNUUk5PIjoiREUtTklaLTExMTQzLTAzLTQ0MC0wMDEifQ=="

    private let expected = [
        "1111111001000000101001001001001111111",
        "1000001011010011100010100000001000001",
        "1011101010001011001001101011101011101",
        "1011101010101101100111000000101011101",
        "1011101001001010001111100000101011101",
        "1000001001111101110010001000101000001",
        "1111111010101010101010101010101111111",
        "0000000010110101001000010010100000000",
        "1000001010100111100101100111111001110",
        "1100110010010100110101100100000110101",
        "0011101111011111110011001011111001111",
        "0011010111000010001010100000111111011",
        "0100101011100011110111010100001011110",
        "0001110000010111100011000100100100111",
        "0111001011101111101011101101101111111",
        "1101100001100000100110010010111101111",
        "0001011110010110011001100010011011000",
        "1111010011011000100011000000101101010",
        "1110001101111000110111111011110000101",
        "1010000000001001100010100010011011011",
        "1100101001111010000010010010011000011",
        "0000000110101110010100000111001111100",
        "0111111100110001000010000011110011111",
        "1101010110000100000000100000001101010",
        "1100111110001111001010111100001100100",
        "1010000000011110000010100111111101000",
        "1001101110110001100010101101100000011",
        "1011010101000000100000111010011111101",
        "1011101011000011110101111011111110101",
        "0000000011100010111010000010100011000",
        "1111111001011011010101111101101010101",
        "1000001000110100100000010001100011000",
        "1011101001110101001100100011111110000",
        "1011101000111100011001010010001111111",
        "1011101001010000011011000010010101011",
        "1000001001110001100110101000011011001",
        "1111111011011010001110010100111010101",
    ]

    func testCodeMatchesTheReferenceGeneratorForARealIdentifier() throws {
        let matrix = try XCTUnwrap(QRCodeMatrix.encode(payload))
        let quiet = QRCodeMatrix.quietZone

        XCTAssertEqual(matrix.version, 5)
        XCTAssertEqual(matrix.size - quiet * 2, expected.count)

        for (row, line) in expected.enumerated() {
            let modules = Array(line).map { $0 == "1" }
            let ours = (0..<modules.count).map { matrix[$0 + quiet, row + quiet] }
            XCTAssertEqual(ours, modules, "row \(row) differs from the reference code")
        }
    }

    func testTheQuietZoneSurroundsTheCode() throws {
        let matrix = try XCTUnwrap(QRCodeMatrix.encode(payload))
        let quiet = QRCodeMatrix.quietZone

        for index in 0..<matrix.size {
            for offset in 0..<quiet {
                XCTAssertFalse(matrix[index, offset], "top quiet zone is not clear")
                XCTAssertFalse(matrix[index, matrix.size - 1 - offset], "bottom quiet zone is not clear")
                XCTAssertFalse(matrix[offset, index], "leading quiet zone is not clear")
                XCTAssertFalse(matrix[matrix.size - 1 - offset, index], "trailing quiet zone is not clear")
            }
        }
    }

    /// The version a payload lands on decides whether a scanner sees the same
    /// code the reference generator would have produced, so the boundaries are
    /// pinned. Each of these was checked against CoreImage's generator.
    func testVersionFollowsThePayloadLength() throws {
        for (length, version) in [(1, 1), (100, 6), (1200, 29), (1700, 34), (2331, 40)] {
            let matrix = try XCTUnwrap(
                QRCodeMatrix.encode(String(repeating: "a", count: length)),
                "\(length) bytes should still fit a code"
            )
            XCTAssertEqual(matrix.version, version, "\(length) bytes landed on the wrong version")
            XCTAssertEqual(matrix.size, version * 4 + 17 + QRCodeMatrix.quietZone * 2)
        }
    }

    func testPayloadsThatCannotBeEncodedHaveNoCode() {
        XCTAssertNil(QRCodeMatrix.encode(""))
        // One byte past the largest code at this error-correction level.
        XCTAssertNil(QRCodeMatrix.encode(String(repeating: "a", count: 2332)))
    }
}
