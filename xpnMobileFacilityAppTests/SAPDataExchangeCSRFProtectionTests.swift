import Foundation
import XCTest
@testable import mobileFacilityApp

final class SAPDataExchangeCSRFProtectionTests: XCTestCase {
    func testDataExchangeRequestUsesDataExchangeServiceRoot() throws {
        let mobileRoot = try XCTUnwrap(URL(string: "https://mobile.example.test"))
        let serviceRoot = try XCTUnwrap(SAPDataExchangeEndpoint.serviceRoot(
            backendURL: mobileRoot,
            destinationPath: "/qa/sap/opu/odata/ezo/daex4tu/"
        ))
        let provider = SAPDataExchangeCSRFTokenURLProvider(
            mobileServicesRoot: mobileRoot,
            dataExchangeServiceRoot: serviceRoot
        )
        let requestURL = serviceRoot.appendingPathComponent("DATAEXCHANGESet")

        XCTAssertEqual(provider.csrfTokenURL(for: requestURL), serviceRoot)
    }

    func testOtherMobileServicesRequestUsesMobileServicesRoot() throws {
        let mobileRoot = try XCTUnwrap(URL(string: "https://mobile.example.test"))
        let serviceRoot = try XCTUnwrap(SAPDataExchangeEndpoint.serviceRoot(
            backendURL: mobileRoot,
            destinationPath: "qa/sap/opu/odata/ezo/daex4tu"
        ))
        let provider = SAPDataExchangeCSRFTokenURLProvider(
            mobileServicesRoot: mobileRoot,
            dataExchangeServiceRoot: serviceRoot
        )
        let requestURL = try XCTUnwrap(URL(string: "https://mobile.example.test/mobileservices/log"))

        XCTAssertEqual(provider.csrfTokenURL(for: requestURL), mobileRoot)
    }

    func testEmptyDestinationPathIsRejected() throws {
        let mobileRoot = try XCTUnwrap(URL(string: "https://mobile.example.test"))

        XCTAssertNil(SAPDataExchangeEndpoint.serviceRoot(
            backendURL: mobileRoot,
            destinationPath: " /// "
        ))
    }
}
