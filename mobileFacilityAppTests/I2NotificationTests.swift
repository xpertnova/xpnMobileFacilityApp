import Foundation
import XCTest
@testable import mobileFacilityApp

final class I2NotificationTests: XCTestCase {
    // MARK: - Rules

    func testCategoriesMatchLegacyDialogListAndDefaultCreatesNothing() {
        XCTAssertEqual(I2NotificationCategory.allCases.map(\.code), ["n.a", "001", "002", "003", "005", "006"])
        XCTAssertFalse(I2NotificationCategory.notCreated.createsNotification)
        XCTAssertTrue(I2NotificationCategory.allCases.dropFirst().allSatisfy(\.createsNotification))
    }

    func testNoteAppendsHeaderTextLikeLegacyCandidateLoop() {
        XCTAssertEqual(I2NotificationRules.note(comment: "Lamp broken", headerText: nil), "Lamp broken")
        XCTAssertEqual(
            I2NotificationRules.note(comment: "Lamp broken", headerText: "Treppenhaus"),
            "Lamp broken\n- HEADERTEXT: Treppenhaus"
        )
        XCTAssertEqual(I2NotificationRules.note(comment: "", headerText: "Keller"), "\n- HEADERTEXT: Keller")
    }

    func testHeaderTextIsLastHeaderRowBeforeOperation() {
        let rows: [[String: Any]] = [
            ["VORNR": "0005", "DNAME": "HEADER", "LTXA1": "Außenbereich"],
            ["VORNR": "0010", "DNAME": "POSITION", "LTXA1": "Zaun"],
            ["VORNR": "0015", "DNAME": "U1", "LTXA1": "Untergruppe"],
            ["VORNR": "0020", "DNAME": "HEADER", "LTXA1": "Treppenhaus"],
            ["VORNR": "0030", "DNAME": "POSITION", "LTXA1": "Beleuchtung"]
        ]
        XCTAssertEqual(I2NotificationRules.headerText(operation: "0010", planRows: rows), "Außenbereich")
        XCTAssertEqual(I2NotificationRules.headerText(operation: "0030", planRows: rows), "Treppenhaus")
        XCTAssertNil(I2NotificationRules.headerText(operation: "0005", planRows: rows))
        // Without plan rows (offline snapshot) the checklist group is used.
        XCTAssertEqual(I2NotificationRules.headerText(operation: "0030", planRows: [], groupTitle: "Gruppe"), "Gruppe")
        XCTAssertNil(I2NotificationRules.headerText(operation: "0030", planRows: [], groupTitle: ""))
    }

    func testRequestsOnlyForPositionsWithRealCategory() {
        let candidates = [
            makeCandidate(id: "A", title: "Door"),
            makeCandidate(id: "B", title: "Window"),
            makeCandidate(id: "C", title: "Roof")
        ]
        var counter = 0
        let requests = I2NotificationRules.requests(
            from: candidates,
            categories: ["A": .technical, "B": .notCreated],
            makeID: {
                counter += 1
                return "NEU-\(counter)"
            }
        )
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].id, "NEU-1")
        XCTAssertEqual(requests[0].positionID, "A")
        XCTAssertEqual(requests[0].shortText, "Door")
        XCTAssertEqual(requests[0].category, .technical)
        XCTAssertEqual(requests[0].noteElementID, "TFM1-A-9B")
    }

    func testTemporaryNotificationIDUsesLegacyShape() {
        let id = I2NotificationRules.makeTemporaryNotificationID()
        XCTAssertTrue(id.hasPrefix("NEU-"))
        XCTAssertEqual(id.count, 12)
        XCTAssertTrue(id.dropFirst(4).allSatisfy { "0A1B2C3D4E5F6879".contains($0) })
    }

    func testLongTextIsTrimmedCutAndSplitLikeGetLongTextArray() {
        XCTAssertEqual(I2NotificationRules.longTextLines(for: "  \n "), [])
        XCTAssertEqual(I2NotificationRules.splitToLength("aaa bbb ccc", length: 8), ["aaa bbb", " ccc"])
        XCTAssertEqual(I2NotificationRules.splitToLength("short", length: 128), ["short"])

        let words = Array(repeating: "Mangel", count: 60).joined(separator: " ")
        let lines = I2NotificationRules.longTextLines(for: "  \(words)  ")
        XCTAssertEqual(lines.joined(), String(words.prefix(300)))
        XCTAssertGreaterThan(lines.count, 2)
        XCTAssertTrue(lines.allSatisfy { $0.utf16.count < 128 })
    }

    func testExistingNotificationsMatchPositionTextAndGroupHeader() {
        let plain = SAPI2NotificationSummary(id: "1", shortText: "Sind die Ansprechpartner noch korrekt?")
        let grouped = SAPI2NotificationSummary(
            id: "2",
            shortText: "Sind die Ansprechpartner noch korrekt?",
            longText: "Nummer fehlt- HEADERTEXT: Haus A"
        )
        let otherGroup = SAPI2NotificationSummary(
            id: "3",
            shortText: "Sind die Ansprechpartner noch korrekt?",
            longText: "Nummer fehlt- HEADERTEXT: Haus B"
        )
        let otherPosition = SAPI2NotificationSummary(id: "4", shortText: "Sind die Kontaktdaten noch korrekt?")
        let all = [plain, grouped, otherGroup, otherPosition]

        let segmented = I2NotificationRules.notifications(
            all,
            forPositionTitle: "Sind die Ansprechpartner noch korrekt?",
            groupTitle: "Haus A",
            matchesGroupHeader: true
        )
        XCTAssertEqual(segmented.map(\.id), ["1", "2"])

        let withoutGroup = I2NotificationRules.notifications(
            all,
            forPositionTitle: "Sind die Ansprechpartner noch korrekt?",
            groupTitle: "",
            matchesGroupHeader: true
        )
        XCTAssertEqual(withoutGroup.map(\.id), ["1"])

        let dropdown = I2NotificationRules.notifications(
            all,
            forPositionTitle: "Sind die Ansprechpartner noch korrekt?",
            groupTitle: "",
            matchesGroupHeader: false
        )
        XCTAssertEqual(dropdown.map(\.id), ["1", "2", "3"])
    }

    func testLongTextDisplayBreaksBeforeEveryInnerAsterisk() {
        XCTAssertEqual(I2NotificationRules.displayLongText("*Erste*Zweite"), "*Erste\n*Zweite")
        XCTAssertEqual(I2NotificationRules.displayLongText("Ohne Stern"), "Ohne Stern")
    }

    @MainActor
    func testSelectionStartsOnNotCreatedAndResetsAfterAccept() {
        let selection = I2DefectSelection()
        XCTAssertFalse(selection.present([]))
        XCTAssertFalse(selection.isPresented)

        XCTAssertTrue(selection.present([makeCandidate(id: "A", title: "Door"), makeCandidate(id: "B", title: "Gate")]))
        XCTAssertTrue(selection.isPresented)
        XCTAssertEqual(selection.category(for: "A"), .notCreated)

        selection.setCategory(.cleaning, for: "B")
        let requests = selection.accept()
        XCTAssertEqual(requests.map(\.positionID), ["B"])
        XCTAssertEqual(requests.first?.category, .cleaning)
        XCTAssertFalse(selection.isPresented)
        XCTAssertTrue(selection.candidates.isEmpty)
    }

    // MARK: - Drafts

    func testReviewDraftKeepsRequestsAndDecodesOlderDraftsWithoutThem() throws {
        let request = I2NotificationRequest(
            id: "NEU-0A1B2C3D", positionID: "TFM1-0010-1", shortText: "Door",
            category: .caretaker, note: "Hinge", noteElementID: "TFM1-0010-9B"
        )
        let draft = NotificationReviewDraftPayload(
            notificationID: "100", performedOn: Date(timeIntervalSince1970: 1_700_000_000),
            results: ["TFM1-0010-1": .yes], comments: ["TFM1-0010-1": "Hinge"],
            photoAttachments: [], isClosedLocally: true, i2Requests: [request]
        )
        let decoded = try JSONDecoder().decode(
            NotificationReviewDraftPayload.self, from: JSONEncoder().encode(draft)
        )
        XCTAssertEqual(decoded.i2Requests, [request])

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any])
        object.removeValue(forKey: "i2Requests")
        let older = try JSONDecoder().decode(
            NotificationReviewDraftPayload.self, from: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertTrue(older.i2Requests.isEmpty)

        let inspection = ElevatorInspectionDraftPayload(notificationID: "200")
        var inspectionObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(inspection)) as? [String: Any]
        )
        inspectionObject.removeValue(forKey: "i2Requests")
        let olderInspection = try JSONDecoder().decode(
            ElevatorInspectionDraftPayload.self, from: JSONSerialization.data(withJSONObject: inspectionObject)
        )
        XCTAssertNil(olderInspection.i2Requests)
    }

    // MARK: - Form flow

    @MainActor
    func testWartungsplanOffersDefectsAfterCloseAndStoresChosenNotifications() async throws {
        let detail = SAPNotificationDetail(summary: try makeSummary(control: "TFM1"))
        XCTAssertEqual(detail.inspectionItems.count, 2)
        let workStore = OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "S50828")
        let model = WartungsplanViewModel(
            detail: detail,
            offlineWorkStore: workStore,
            photoStore: InMemoryPhotoAttachmentStore(),
            sapDataStore: makeDataStore()
        )
        await model.load()

        let defect = detail.inspectionItems[1]
        model.results[detail.inspectionItems[0].id] = .no
        model.results[defect.id] = .yes
        model.comments[defect.id] = "Glass cracked"

        let closed = await model.save(closed: true)
        XCTAssertTrue(closed)
        XCTAssertTrue(model.isClosedLocally)
        XCTAssertNil(model.feedback)
        XCTAssertTrue(model.i2Selection.isPresented)
        let candidate = try XCTUnwrap(model.i2Selection.candidates.first)
        XCTAssertEqual(model.i2Selection.candidates.count, 1)
        XCTAssertEqual(candidate.id, defect.id)
        XCTAssertEqual(candidate.number, 2)
        XCTAssertEqual(candidate.resultCode, "X")
        XCTAssertEqual(candidate.note, "Glass cracked\n- HEADERTEXT: Treppenhaus")
        XCTAssertEqual(candidate.noteElementID, "TFM1-0020-9B")

        model.i2Selection.setCategory(.technical, for: defect.id)
        let staysOpen = await model.acceptI2Selection()
        XCTAssertTrue(staysOpen)
        XCTAssertEqual(model.feedback, .i2NotificationsQueued)

        let stored = try XCTUnwrap(workStore.notificationReview(notificationID: detail.summary.id))
        XCTAssertTrue(stored.isClosedLocally)
        XCTAssertEqual(stored.i2Requests.count, 1)
        XCTAssertEqual(stored.i2Requests.first?.category, .technical)
        XCTAssertEqual(stored.i2Requests.first?.shortText, defect.title)
    }

    @MainActor
    func testWartungsplanWithoutI2PermissionClosesNormally() async throws {
        let detail = SAPNotificationDetail(summary: try makeSummary(control: "TFM1"))
        let model = WartungsplanViewModel(
            detail: detail,
            offlineWorkStore: OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "S50828"),
            photoStore: InMemoryPhotoAttachmentStore()
        )
        await model.load()
        for item in detail.inspectionItems {
            model.results[item.id] = .yes
            model.comments[item.id] = "Defect"
        }

        _ = await model.save(closed: true)
        XCTAssertFalse(model.i2Selection.isPresented)
        XCTAssertEqual(model.feedback, .closedLocally)
    }

    @MainActor
    func testAcceptingWithoutCategoryStoresNothing() async throws {
        let detail = SAPNotificationDetail(summary: try makeSummary(control: "TFM3"))
        let workStore = OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "S50828")
        let model = NotificationReviewViewModel(
            detail: detail,
            offlineWorkStore: workStore,
            photoStore: InMemoryPhotoAttachmentStore(),
            sapDataStore: makeDataStore()
        )
        await model.load()
        for item in detail.inspectionItems {
            model.results[item.id] = .yes
            model.comments[item.id] = "Defect"
        }

        await model.save(closed: true)
        XCTAssertTrue(model.i2Selection.isPresented)
        let staysOpen = await model.acceptI2Selection()
        XCTAssertFalse(staysOpen)
        XCTAssertFalse(model.i2Selection.isPresented)
        XCTAssertEqual(workStore.notificationReview(notificationID: detail.summary.id)?.i2Requests, [])
    }

    // MARK: - Upload

    func testBuilderCreatesLegacyI2RowFromTemplateAndCopiesPositionPhotos() throws {
        let now = Date(timeIntervalSince1970: 1_789_000_000)
        let parent: [String: Any] = [
            "MANDT": "100", "QMNUM": "005140058979", "QMART": "I1", "QMTXT": "Wartungsplan",
            "STRNO": "DE-SAF-11152-10", "TPLNR": "INTERNAL-TPLNR", "EQUNR": "", "IWERK": "SAF1",
            "STTXT": "MOFN", "USTXT": "OPEN", "STRMN": "20260901", "PRIOK": "1",
            "T_PLPOD": [["VORNR": "0010"]]
        ]
        let template: [String: Any] = [
            "MANDT": "", "QMART": "", "IWERK": "", "INGRP": "TEMPLATE-GROUP",
            "TEMPLATE_ONLY": "kept", "T_LTXT_QM": []
        ]
        let photo = SAPNotificationOutgoingDocument(
            metadata: [
                "MANDT": "100", "VORGANGSNR": "PROCESS", "DOCID": "DOC-1", "ELEMENTNR": "TFM1-0010-9B",
                "QMNUM": "005140058979", "OBJKY": "005140058979",
                "DMS_CONTENTTYPE": "D_TFM_Wartung", "DMS_DOCID": "TFM005"
            ],
            data: Data([0xFF, 0xD8, 0xFF, 0xD9])
        )
        let otherPhoto = SAPNotificationOutgoingDocument(
            metadata: ["ELEMENTNR": "TFM1-0020-9B", "DOCID": "DOC-2"],
            data: Data([0xFF, 0xD8])
        )
        let requests = [
            I2NotificationRequest(
                id: "NEU-0A1B2C3D", positionID: "TFM1-0010-1", shortText: "Sind die Ansprechpartner noch korrekt?",
                category: .caretaker, note: "Hausmeister fehlt", noteElementID: "TFM1-0010-9B"
            ),
            I2NotificationRequest(
                id: "NEU-SKIPPED", positionID: "TFM1-0020-1", shortText: "Other",
                category: .notCreated, note: "", noteElementID: "TFM1-0020-9B"
            )
        ]

        let output = try SAPI2NotificationUploadBuilder.build(
            requests: requests,
            parentNotification: parent,
            template: template,
            parentDocuments: [photo, otherPhoto],
            syncUserID: "s50828",
            now: now
        )

        XCTAssertEqual(output.notifications.count, 1)
        let row = try XCTUnwrap(output.notifications.first)
        let columns = Set((LegacySQLiteSchema.byName["TO_T0284"]?.columns ?? []).map(\.name))
        XCTAssertTrue(row.keys.allSatisfy(columns.contains))
        XCTAssertEqual(row["QMNUM"], "NEU-0A1B2C3D")
        XCTAssertEqual(row["QMART"], "I2")
        XCTAssertEqual(row["REFNUM"], "005140058979")
        XCTAssertEqual(row["QMTXT"], "Sind die Ansprechpartner noch korrekt?")
        XCTAssertEqual(row["QMCOD"], "001")
        XCTAssertEqual(row["QMGRP"], "ZPMI0001")
        XCTAssertEqual(row["PRIOK"], "3")
        XCTAssertEqual(row["TPLNR"], "DE-SAF-11152-10")
        XCTAssertEqual(row["STRNO"], "DE-SAF-11152-10")
        XCTAssertEqual(row["STTXT"], "")
        XCTAssertEqual(row["STRMN"], "")
        XCTAssertEqual(row["USTXT"], "MTFM")
        XCTAssertEqual(row["QMNAM"], "S50828")
        XCTAssertEqual(row["AENAM"], "S50828")
        XCTAssertEqual(row["MANDT"], "100")
        XCTAssertEqual(row["IWERK"], "SAF1")
        XCTAssertEqual(row["REQID"], "")

        let feldwert = try XCTUnwrap(row["FELDWERT"] ?? nil)
        let object = try XCTUnwrap(SAPLegacyDataExchangeCodec.decodedFeldwertObject(feldwert))
        XCTAssertEqual(object["TEMPLATE_ONLY"] as? String, "kept")
        XCTAssertEqual(object["INGRP"] as? String, "TEMPLATE-GROUP")
        XCTAssertEqual(object["MANDT"] as? String, "100")
        XCTAssertEqual(object["QMCOD"] as? String, "001")
        XCTAssertNil(object["T_PLPOD"])
        let lines = try XCTUnwrap(object["T_LTXT_QM"] as? [[String: Any]])
        XCTAssertEqual(lines.first?["TDLINE"] as? String, "Hausmeister fehlt")
        XCTAssertEqual(lines.first?["TDFORMAT"] as? String, "")

        XCTAssertEqual(output.documents.count, 1)
        let document = try XCTUnwrap(output.documents.first)
        XCTAssertEqual(document.metadata["QMNUM"], "NEU-0A1B2C3D")
        XCTAssertEqual(document.metadata["DOCID"], "DOC-1")
        XCTAssertEqual(document.metadata["VORGANGSNR"], "PROCESS")
        XCTAssertEqual(document.metadata["OBJKY"], "005140058979")
        XCTAssertEqual(document.metadata["DMS_CONTENTTYPE"], "D_TFM_AllgemeineDokumente")
        XCTAssertEqual(document.metadata["DMS_DOCID"], "TFM009")
        XCTAssertEqual(document.data, photo.data)
    }

    func testBuilderWithoutTemplateUsesParentRowAndOmitsEmptyLongText() throws {
        let parent: [String: Any] = ["MANDT": "100", "QMNUM": "4711", "STRNO": "FL-1", "EQUNR": "EQ-1"]
        let output = try SAPI2NotificationUploadBuilder.build(
            requests: [I2NotificationRequest(
                id: "NEU-1", positionID: "P", shortText: "Pump", category: .technical,
                note: "   ", noteElementID: "TFM2-0010-9B"
            )],
            parentNotification: parent,
            template: nil,
            parentDocuments: [],
            syncUserID: "S1"
        )
        let row = try XCTUnwrap(output.notifications.first)
        XCTAssertEqual(row["EQUNR"], "EQ-1")
        XCTAssertEqual(row["QMCOD"], "003")
        let object = try XCTUnwrap(SAPLegacyDataExchangeCodec.decodedFeldwertObject(try XCTUnwrap(row["FELDWERT"] ?? nil)))
        XCTAssertNil(object["T_LTXT_QM"])
        XCTAssertTrue(output.documents.isEmpty)
    }

    func testOutgoingRowsReplaceI2NotificationsOnRetryAndStageThem() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try SQLiteSAPDataCacheRepository(
            databaseURL: directory.appendingPathComponent("cache.sqlite")
        )
        let notification: LegacySAPRow = ["QMNUM": "NEU-1", "QMART": "I2", "REFNUM": "100"]
        let document: LegacySAPRow = ["VORGANGSNR": "PROCESS", "QMNUM": "NEU-1", "DOCID": "DOC"]

        for _ in 0..<2 {
            try await repository.replaceNotificationOutgoingRows(
                processIDs: ["PROCESS"], equipmentIDs: [], headers: [], values: [], documents: [],
                equipment: [], functionalLocations: [], proposals: [],
                i2Notifications: [notification], i2Documents: [document]
            )
        }

        let notificationCount = try await repository.legacyRowCount(in: "TO_T0284")
        let documentCount = try await repository.legacyRowCount(in: "TO_T0285")
        XCTAssertEqual(notificationCount, 1)
        XCTAssertEqual(documentCount, 1)

        let staged = try await repository.stageOutgoing(requestID: "REQUEST")
        XCTAssertEqual(staged.T_0284.first?["QMNUM"], "NEU-1")
        XCTAssertEqual(staged.T_0284.first?["REQID"], "REQUEST")
        XCTAssertEqual(staged.T_0285.first?["DOCID"], "DOC")
        await repository.abortOutgoing(requestID: "REQUEST")
    }

    func testRepositoryReadsDownloadedI2NotificationsOfTheSameObject() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try SQLiteSAPDataCacheRepository(
            databaseURL: directory.appendingPathComponent("cache.sqlite")
        )
        let longText = try SAPLegacyDataExchangeCodec.packedFeldwert([
            ["TDFORMAT": "*", "TDLINE": "*Kontakt "],
            ["TDFORMAT": "", "TDLINE": "fehlt"]
        ])
        try await repository.insertLegacyRows([
            ["MANDT": "100", "QMNUM": "2", "QMART": "I2", "QMTXT": "Door", "TPLNR": "FL-1",
             "EQUNR": "", "STRMN": "2026-09-01", "STRUR": "17:52:41", "QMNAM": "S50828",
             "REFNUM": "005140058979", "STTXT": "MOFN", "FELDWERT": longText],
            ["MANDT": "100", "QMNUM": "1", "QMART": "I2", "QMTXT": "Door", "TPLNR": "FL-1",
             "EQUNR": "", "STRMN": "2022-01-05", "STRUR": "08:18:25", "STTXT": "MMAB"],
            ["MANDT": "200", "QMNUM": "3", "QMART": "I2", "QMTXT": "Door", "TPLNR": "FL-1", "EQUNR": ""],
            ["MANDT": "100", "QMNUM": "4", "QMART": "I1", "QMTXT": "Door", "TPLNR": "FL-1", "EQUNR": ""],
            ["MANDT": "100", "QMNUM": "5", "QMART": "I2", "QMTXT": "Pump", "TPLNR": "FL-1", "EQUNR": "EQ-1"]
        ], into: "FROM_T0271")

        let byLocation = try await repository.loadI2Notifications(
            for: I2NotificationObjectReference(client: "100", equipmentID: "", functionalLocationID: "FL-1")
        )
        XCTAssertEqual(byLocation.map(\.id), ["5", "1", "2"])
        let latest = try XCTUnwrap(byLocation.last)
        XCTAssertEqual(latest.reporter, "S50828")
        XCTAssertEqual(latest.referenceID, "005140058979")
        XCTAssertEqual(latest.systemStatus, "MOFN")
        XCTAssertEqual(latest.longText, "*Kontakt fehlt")

        let byEquipment = try await repository.loadI2Notifications(
            for: I2NotificationObjectReference(client: "100", equipmentID: "EQ-1", functionalLocationID: "FL-1")
        )
        XCTAssertEqual(byEquipment.map(\.id), ["5"])
    }

    // MARK: - Fixtures

    private func makeCandidate(id: String, title: String) -> I2DefectCandidate {
        I2DefectCandidate(
            id: id, number: 1, title: title, resultCode: "X", resultText: "Ja",
            note: "", noteElementID: "TFM1-\(id)-9B"
        )
    }

    @MainActor
    private func makeDataStore() -> SAPDataStore {
        let profile = SAPWorkerProfile(
            personnelNumber: "4711", firstName: "Alex", lastName: "Morgan",
            organizationUnit: "FM", role: "Technician", email: "", isActive: "X", roleCode: ""
        )
        return SAPDataStore(
            repository: InMemorySAPDataCacheRepository(
                seed: SAPCachedData(notifications: [], workerProfile: profile, metadata: nil),
                workerID: "S50828"
            ),
            refreshService: nil,
            localWorkerID: "S50828"
        )
    }

    private func makeSummary(control: String) throws -> SAPNotificationSummary {
        let payload: [String: Any] = [
            "MANDT": "100", "QMNUM": "47100002", "QMART": "I1", "USTXT": "OPEN",
            "STRNO": "FL-1", "TPLNR": "FL-1",
            "T_PLPOD": [
                [
                    "USR00": "POSITION", "DNAME": "POSITION", "STEUS": control, "VORNR": "0010",
                    "LTXA1": "Sind die Ansprechpartner noch korrekt?",
                    "T_PROPS": [["POSNR": "1", "DFVAL": " ;X"]]
                ],
                ["USR00": "HEADER", "DNAME": "HEADER", "STEUS": control, "VORNR": "0015", "LTXA1": "Treppenhaus"],
                [
                    "USR00": "POSITION", "DNAME": "POSITION", "STEUS": control, "VORNR": "0020",
                    "LTXA1": "Sind die Fenster intakt?",
                    "T_PROPS": [["POSNR": "1", "DFVAL": " ;X"]]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return SAPNotificationSummary(
            id: "47100002", client: "100", title: "Wartungsplan",
            functionalLocationID: "FL-1", functionalLocationName: "Building A",
            startDate: "20260910", endDate: "20260910",
            systemStatus: "", userStatus: "OPEN",
            rawPayloadJSON: try XCTUnwrap(String(data: data, encoding: .utf8))
        )
    }
}
