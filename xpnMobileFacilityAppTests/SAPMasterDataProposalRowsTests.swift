import XCTest
@testable import mobileFacilityApp

/// `insertSaveProcessVorschlag` / `type4T0211`: one `TO_T0211` row per
/// "Pflege durch Admin" proposal.
final class SAPMasterDataProposalRowsTests: XCTestCase {
    private func rows(_ proposals: [String: String]) -> [LegacySAPRow] {
        SAPMasterDataProposalRows.rows(
            proposals: proposals,
            processID: "V-1",
            notificationID: "Q-1",
            equipmentID: "E-1",
            functionalLocationID: "F-1",
            userID: "S50828",
            date: "20260930",
            time: "101500"
        )
    }

    func testNoProposalsBuildNoRows() {
        XCTAssertTrue(rows([:]).isEmpty)
    }

    func testBlankProposalsAreSkipped() {
        let result = rows(["FSA_HERSTELLER": "   ", "FSA_TYP": "\n", "FSA_BAUJAHR": "1999"])

        XCTAssertEqual(result.map { $0["ELEMENTNR"] ?? nil }, ["FSA_BAUJAHR"])
    }

    func testRowsAreSortedByElementAndCarryTheTrimmedProposal() {
        let result = rows(["FSA_TYP": "  Typ B ", "FSA_HERSTELLER": "Schindler"])

        XCTAssertEqual(result.map { $0["ELEMENTNR"] ?? nil }, ["FSA_HERSTELLER", "FSA_TYP"])
        XCTAssertEqual(result.map { $0["FELDWERT"] ?? nil }, ["Schindler", "Typ B"])
    }

    func testProposalIsCutToTheInputMaximumLength() {
        let result = rows(["FSA_TYP": String(repeating: "x", count: 100)])

        XCTAssertEqual((result.first?["FELDWERT"] ?? nil)?.count, MasterDataProposalRules.maximumLength)
    }

    func testRowFollowsTheLegacyT0211Layout() throws {
        let row = try XCTUnwrap(rows(["FSA_TYP": "Typ B"]).first)

        XCTAssertEqual(row, [
            "MANDT": "", "REQID": "", "VORGANGSNR": "V-1",
            "ELEMENTNR": "FSA_TYP", "QMNUM": "Q-1",
            "STRNO": "F-1", "EQUNR": "E-1",
            "CREATEDBY": "S50828", "CREATEDDATE": "20260930", "CREATEDTIME": "101500",
            "MODIFIEDDATE": "20260930", "MODIFIEDTIME": "101500", "MODIFIEDBY": "S50828",
            "FELDWERT": "Typ B", "AKTIV": "X"
        ])
    }
}
