import Foundation
import XCTest
@testable import mobileFacilityApp

/// The point of these tests is the round trip: a code generated on the detail
/// screen has to be one the app's own scanner resolves, so every payload is
/// fed straight back through the production decoder.
final class TechnicalObjectQRCodeTests: XCTestCase {
    func testFunctionalLocationPayloadDecodesAsALocationOnlyCode() throws {
        let location = try XCTUnwrap(SAPTechnicalObjectMapper.functionalLocation(from: [
            "STRNO": "SITE-BLDG-420-Z", "TPLMA": "SITE-BLDG-420", "PLTXT": "Heating plant"
        ]))

        let payload = try XCTUnwrap(TechnicalObjectQRCode.payload(for: location))

        // `EQUNR: "%"` has to decode to "no equipment", which is what makes
        // the scan match the notifications of the place itself.
        XCTAssertEqual(
            try LegacyQRCodeCodec.decode(payload),
            .mtfm(controlKey: nil, functionalLocationID: "SITE-BLDG-420-Z", equipmentID: nil)
        )
    }

    func testEquipmentPayloadCarriesBothItsLocationAndItsNumber() throws {
        let equipment = try XCTUnwrap(SAPTechnicalObjectMapper.equipment(from: [
            "EQUNR": "EQ-2", "STRNO": "SITE-BLDG-420-Z", "EQKTX": "Pump"
        ]))

        let payload = try XCTUnwrap(TechnicalObjectQRCode.payload(for: equipment))

        XCTAssertEqual(
            try LegacyQRCodeCodec.decode(payload),
            .mtfm(controlKey: nil, functionalLocationID: "SITE-BLDG-420-Z", equipmentID: "EQ-2")
        )
    }

    func testPayloadMatchesTheLegacyPrinterFormat() throws {
        let location = try XCTUnwrap(SAPTechnicalObjectMapper.functionalLocation(from: [
            "STRNO": "SITE-BLDG-420-Z", "PLTXT": "Heating plant"
        ]))

        let payload = try XCTUnwrap(TechnicalObjectQRCode.payload(for: location))
        let data = try XCTUnwrap(Data(base64Encoded: payload))
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: String]
        )

        // `QrPrintList.controller.js` base64-encodes exactly these three keys.
        XCTAssertEqual(object, ["STEUS": "", "STRNO": "SITE-BLDG-420-Z", "EQUNR": "%"])
    }

    func testNoPayloadForEquipmentWithoutAFunctionalLocation() throws {
        let equipment = try XCTUnwrap(SAPTechnicalObjectMapper.equipment(from: [
            "EQUNR": "EQ-2", "EQKTX": "Pump"
        ]))

        XCTAssertNil(TechnicalObjectQRCode.payload(for: equipment))
    }

    func testGeneratedBitmapIsSquareAndScaledByWholeModules() throws {
        let location = try XCTUnwrap(SAPTechnicalObjectMapper.functionalLocation(from: [
            "STRNO": "SITE-BLDG-420-Z", "PLTXT": "Heating plant"
        ]))
        let payload = try XCTUnwrap(TechnicalObjectQRCode.payload(for: location))

        let image = try XCTUnwrap(QRCodeImageRenderer.image(for: payload))

        XCTAssertEqual(image.size.width, image.size.height)
        XCTAssertEqual(
            image.size.width.truncatingRemainder(dividingBy: QRCodeImageRenderer.moduleScale),
            0,
            accuracy: 0.001
        )
    }

    func testLabelIsASinglePDFPage() throws {
        let location = try XCTUnwrap(SAPTechnicalObjectMapper.functionalLocation(from: [
            "STRNO": "SITE-BLDG-420-Z", "PLTXT": "Heating plant"
        ]))
        let payload = try XCTUnwrap(TechnicalObjectQRCode.payload(for: location))

        let data = try XCTUnwrap(TechnicalObjectQRCode.labelPDF(for: location, payload: payload))
        let document = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: data as CFData)!))

        XCTAssertEqual(document.numberOfPages, 1)
        XCTAssertEqual(TechnicalObjectQRCode.labelFileName(for: location), "QR-SITE-BLDG-420-Z.pdf")
    }

    func testIdentifierSegmentsNameTheAncestorsTheyBelongTo() throws {
        let site = try XCTUnwrap(SAPTechnicalObjectMapper.functionalLocation(from: [
            "STRNO": "SITE", "PLTXT": "Main site"
        ]))
        let building = try XCTUnwrap(SAPTechnicalObjectMapper.functionalLocation(from: [
            "STRNO": "SITE-BLDG", "TPLMA": "SITE", "PLTXT": "Office building"
        ]))

        let segments = TechnicalObjectIdentifierSegment.segments(
            of: "SITE-BLDG-420-Z",
            breadcrumbs: [site, building]
        )

        XCTAssertEqual(segments.map(\.value), ["SITE", "BLDG", "420", "Z"])
        XCTAssertEqual(segments.map(\.position), [1, 2, 3, 4])
        // Only the segments whose prefix is a loaded ancestor get a name; the
        // rest stay unnamed instead of borrowing the prototype's labels.
        XCTAssertEqual(segments.map(\.objectName), ["Main site", "Office building", nil, nil])
    }

    func testREFXIdentifierSegmentsNameTheirLevels() {
        let segments = TechnicalObjectIdentifierSegment.segments(
            of: "DE-ESS-10004-06-330-002",
            breadcrumbs: [.structurePlaceholder("DE", cityName: ""), .structurePlaceholder("DE-ESS", cityName: "Essen")],
            isStructured: true
        )
        XCTAssertEqual(segments.map(\.level), [.country, .city, .businessEntity, .building, .costGroup, .finalObject])
        // A placeholder without a name of its own does not repeat its code.
        XCTAssertEqual(segments.prefix(2).map(\.objectName), [nil, "Essen"])
    }

    func testIdentifierWithoutSeparatorsHasNoSegmentsToShow() {
        XCTAssertTrue(TechnicalObjectIdentifierSegment.segments(of: "EQ100040", breadcrumbs: []).isEmpty)
    }
}
