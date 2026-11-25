import XCTest
@testable import mobileFacilityApp

/// End-to-end probe: does a closed briefing actually persist the documents of
/// the positions answered "Ja"?
final class BriefingDocumentEndToEndTests: XCTestCase {

    private func template() -> SAPBriefingTemplate {
        let options = [
            SAPBriefingAnswerOption(key: "NO", title: "Nein"),
            SAPBriefingAnswerOption(key: "YES", title: "Ja")
        ]
        return SAPBriefingTemplate(
            id: "TFMINSTRUC|I3|A|TFMB_001",
            equipmentType: "TFMINSTRUC", plannerGroup: "I3", planType: "A",
            planNumber: "TFMB_001",
            sections: [
                SAPBriefingTemplateSection(
                    id: "0010", title: "Abschnitt", isOptional: false,
                    items: [
                        SAPBriefingTemplateItem(
                            id: "0010-01", orderIdentifier: "0010", rowType: .position,
                            title: "Handout ausgehändigt", answerOptions: options,
                            documentSymbolID: "2", warningSymbolID: nil
                        )
                    ]
                )
            ]
        )
    }

    @MainActor
    func testClosedBriefingStoresTheAnsweredDocument() async throws {
        let store = OfflineWorkStore(
            repository: InMemoryOfflineWorkRepository(), workerID: "test"
        )
        let model = BriefingWorkflowViewModel(
            source: .init(
                isDemo: false,
                contexts: [.init(
                    businessEntityID: "11152", businessEntityTitle: "WE",
                    buildingCode: "10", buildingTitle: "GE"
                )],
                partners: [],
                templates: [template()],
                workerProfile: nil,
                workerName: "Test User",
                offlineWorkStore: store
            )
        )
        model.selectedBusinessEntityID = "11152"
        model.selectedBuildingCode = "10"
        model.answerKeysByItemID["0010-01"] = "YES"

        let closed = await model.markPendingSynchronization(using: store)
        XCTAssertTrue(closed)

        let saved = store.briefingItems.first?.payload.briefing
        XCTAssertEqual(saved?.additionalDocumentSymbolIDs, ["2"])
    }

    /// A position answered "Nein" hands over nothing.
    @MainActor
    func testBriefingAnsweredNoStoresNoDocument() async throws {
        let store = OfflineWorkStore(
            repository: InMemoryOfflineWorkRepository(), workerID: "test"
        )
        let model = BriefingWorkflowViewModel(
            source: .init(
                isDemo: false,
                contexts: [.init(
                    businessEntityID: "11152", businessEntityTitle: "WE",
                    buildingCode: "10", buildingTitle: "GE"
                )],
                partners: [], templates: [template()], workerProfile: nil,
                workerName: "Test User", offlineWorkStore: store
            )
        )
        model.selectedBusinessEntityID = "11152"
        model.selectedBuildingCode = "10"
        model.answerKeysByItemID["0010-01"] = "NO"

        let closed = await model.markPendingSynchronization(using: store)
        XCTAssertTrue(closed)

        XCTAssertEqual(store.briefingItems.first?.payload.briefing?.additionalDocumentSymbolIDs, [])
    }
}
