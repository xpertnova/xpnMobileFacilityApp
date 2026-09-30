import Foundation
import XCTest
@testable import mobileFacilityApp

@MainActor
final class LoadTestSeederTests: XCTestCase {
    private let parents = [
        DefectParentNotification(
            id: "000500001", title: "Wartung Aufzug", functionalLocationID: "UN01-ST01-BG01",
            equipmentID: "10004711", startDate: "2026-09-01"
        ),
        DefectParentNotification(
            id: "000500002", title: "Rundgang", functionalLocationID: "UN01-ST01-BG02",
            equipmentID: "", startDate: "2026-09-02"
        )
    ]

    /// The demo master data of the four I3 forms.
    private func instructionSource(
        store: OfflineWorkStore,
        partners: [SAPBriefingPartner]? = nil
    ) -> LoadTestInstructionSource {
        let qualification = ProofOfQualificationSource.demo(workerName: "Alex Morgan")
        let briefing = BriefingWorkflowViewModel.Source.demo(store, workerName: "Alex Morgan")
        return LoadTestInstructionSource(
            contexts: qualification.contexts,
            partners: partners ?? qualification.partners,
            templates: briefing.templates + [qualification.template].compactMap { $0 },
            workerProfile: nil,
            workerName: "Alex Morgan"
        )
    }

    private func makeSeeder(
        parents: [DefectParentNotification]? = nil,
        partners: [SAPBriefingPartner]? = nil
    ) -> (seeder: LoadTestSeeder, store: OfflineWorkStore, photos: InMemoryPhotoAttachmentStore) {
        let store = OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "S50828")
        let instruction = instructionSource(store: store, partners: partners)
        let photos = InMemoryPhotoAttachmentStore()
        let parents = parents ?? self.parents
        let seeder = LoadTestSeeder(
            offlineWorkStore: store,
            photoStore: photos,
            mobileLadderProvider: DemoMobileLadderCreationProvider(),
            subdistributionProvider: DemoSubdistributionCreationProvider(),
            loadDefectParents: { parents },
            loadInstructionSource: { instruction }
        )
        return (seeder, store, photos)
    }

    private func configuration(
        defects: Int = 0, ladders: Int = 0, subdistributions: Int = 0,
        photos: Int = 2, closed: Bool = false
    ) -> LoadTestConfiguration {
        LoadTestConfiguration(
            defectCount: defects, mobileLadderCount: ladders, subdistributionCount: subdistributions,
            photosPerRecord: photos, photoByteCount: 20_000, closesRecords: closed
        )
    }

    func testDraftsAreLocalWorkWithTheirPhotos() async throws {
        let (seeder, store, photos) = makeSeeder()

        let result = try await seeder.generate(configuration(defects: 3, ladders: 2, subdistributions: 2, photos: 4))

        XCTAssertEqual(result.recordCount, 7)
        XCTAssertEqual(result.photoCount, 28)
        XCTAssertFalse(result.wasCancelled)
        XCTAssertEqual(store.defectItems.count, 3)
        XCTAssertEqual(store.mobileLadderItems.count, 2)
        XCTAssertEqual(store.subdistributionItems.count, 2)
        XCTAssertTrue(store.items.filter { $0.type != .photoCollection }.allSatisfy { $0.status == .draft })
        XCTAssertEqual(seeder.inventory, LoadTestInventory(
            defectCount: 3, mobileLadderCount: 2, subdistributionCount: 2, photoCount: 28, draftCount: 7
        ))

        let defect = try XCTUnwrap(store.defectItems.first?.payload.defect)
        XCTAssertTrue(defect.shortText.hasPrefix(LoadTestSeeder.marker))
        XCTAssertLessThanOrEqual(defect.shortText.count, DefectDraftPayload.maximumShortTextLength)
        for id in defect.attachmentIDs {
            let data = try await photos.loadJPEG(id: id)
            XCTAssertFalse(data.isEmpty)
        }
    }

    func testDefectsBelongToTheObjectOfTheirParentNotification() async throws {
        let (seeder, store, _) = makeSeeder()

        _ = try await seeder.generate(configuration(defects: 4, photos: 0))

        let defects = store.defectItems.compactMap(\.payload.defect)
        XCTAssertEqual(defects.count, 4)
        for defect in defects {
            let parent = try XCTUnwrap(parents.first { $0.id == defect.parentNotificationID })
            XCTAssertTrue(parent.belongs(to: defect.technicalObject))
            XCTAssertNotNil(defect.category)
        }
        XCTAssertEqual(Set(defects.compactMap(\.parentNotificationID)), Set(parents.map(\.id)))
    }

    func testFormPhotosStayWithinTheTwentyPhotoLimitAndMatchTheirCollections() async throws {
        let (seeder, store, _) = makeSeeder()

        _ = try await seeder.generate(configuration(ladders: 1, subdistributions: 1, photos: 50))

        let ladder = try XCTUnwrap(store.mobileLadderItems.first?.payload.mobileLadder)
        let subdistribution = try XCTUnwrap(store.subdistributionItems.first?.payload.subdistribution)
        XCTAssertEqual(ladder.photoAttachments.count, LoadTestConfiguration.maximumFormPhotoCount)
        XCTAssertEqual(subdistribution.photoAttachments.count, LoadTestConfiguration.maximumFormPhotoCount)

        // The forms rebuild their attachments from the photo collections, so
        // both have to describe the same photos.
        for (ownerID, attachmentIDs) in [
            (ladder.localDraftID, Set(ladder.photoAttachments.map(\.localAttachmentID))),
            (subdistribution.localDraftID, Set(subdistribution.photoAttachments.map(\.localAttachmentID)))
        ] {
            let collected = store.photoCollectionItems
                .compactMap(\.payload.photoCollection)
                .filter { $0.scope.ownerID == ownerID }
                .flatMap { $0.attachments.map(\.localAttachmentID) }
            XCTAssertEqual(Set(collected), attachmentIDs)
            XCTAssertEqual(collected.count, attachmentIDs.count)
        }
    }

    func testClosedRecordsAreQueuedAndAcceptedByTheUploadBuilders() async throws {
        let (seeder, store, photos) = makeSeeder()

        // No photos asked for: the sub-distribution still gets the one its
        // documentation position needs.
        _ = try await seeder.generate(configuration(defects: 1, ladders: 1, subdistributions: 1, photos: 0, closed: true))

        XCTAssertEqual(store.defectItems.first?.status, .pendingSynchronization)

        let ladderItem = try XCTUnwrap(store.mobileLadderItems.first)
        let ladder = try XCTUnwrap(ladderItem.payload.mobileLadder)
        XCTAssertEqual(ladderItem.status, .pendingSynchronization)
        XCTAssertEqual(ladder.isClosedLocally, true)
        XCTAssertNoThrow(try SAPMobileLadderUploadBuilder.build(
            workItem: ladderItem, draft: ladder, syncUserID: "S50828", photoData: [:]
        ))

        let subdistributionItem = try XCTUnwrap(store.subdistributionItems.first)
        let subdistribution = try XCTUnwrap(subdistributionItem.payload.subdistribution)
        XCTAssertEqual(subdistributionItem.status, .pendingSynchronization)
        XCTAssertTrue(subdistribution.isClosedLocally)
        XCTAssertFalse(subdistribution.photoAttachments.isEmpty)
        var photoData: [String: Data] = [:]
        for attachment in subdistribution.photoAttachments {
            photoData[attachment.localAttachmentID] = try await photos.loadJPEG(id: attachment.localAttachmentID)
        }
        XCTAssertNoThrow(try SAPSubdistributionUploadBuilder.build(
            workItem: subdistributionItem, draft: subdistribution, syncUserID: "S50828", photoData: photoData
        ))
    }

    func testClosingGeneratedDraftsQueuesThemAndLeavesOtherDraftsAlone() async throws {
        let (seeder, store, photos) = makeSeeder()
        let own = try await store.saveDefect(
            payload: DefectDraftPayload(
                technicalObject: TechnicalObjectReference(kind: .equipment, objectID: "10004711"),
                technicalObjectName: "Aufzug", dinGroup: nil, priority: .high,
                shortText: "Tür klemmt", longText: "", attachmentIDs: []
            ),
            status: .draft
        )
        _ = try await seeder.generate(configuration(defects: 2, ladders: 1, subdistributions: 1, photos: 0))
        XCTAssertEqual(seeder.inventory.draftCount, 4)

        let closedCount = try await seeder.closeGeneratedDrafts(photoByteCount: 20_000)

        XCTAssertEqual(closedCount, 4)
        XCTAssertEqual(seeder.inventory.draftCount, 0)
        XCTAssertEqual(store.item(id: own.id)?.status, .draft)
        XCTAssertTrue(
            store.items.filter(LoadTestSeeder.isGenerated).allSatisfy { $0.status == .pendingSynchronization }
        )

        let ladderItem = try XCTUnwrap(store.mobileLadderItems.first)
        let ladder = try XCTUnwrap(ladderItem.payload.mobileLadder)
        XCTAssertEqual(ladder.isClosedLocally, true)
        XCTAssertNoThrow(try SAPMobileLadderUploadBuilder.build(
            workItem: ladderItem, draft: ladder, syncUserID: "S50828", photoData: [:]
        ))

        // The draft had no photo; closing gave its documentation position one.
        let subdistributionItem = try XCTUnwrap(store.subdistributionItems.first)
        let subdistribution = try XCTUnwrap(subdistributionItem.payload.subdistribution)
        XCTAssertTrue(subdistribution.isClosedLocally)
        XCTAssertEqual(subdistribution.photoAttachments.count, 1)
        var photoData: [String: Data] = [:]
        for attachment in subdistribution.photoAttachments {
            photoData[attachment.localAttachmentID] = try await photos.loadJPEG(id: attachment.localAttachmentID)
        }
        XCTAssertNoThrow(try SAPSubdistributionUploadBuilder.build(
            workItem: subdistributionItem, draft: subdistribution, syncUserID: "S50828", photoData: photoData
        ))

        try await seeder.deleteGenerated()
        XCTAssertEqual(store.items.map(\.id), [own.id])
    }

    func testInstructionFormsAreDraftsNamingTheTestPartnerExceptFirePermits() async throws {
        let (seeder, store, _) = makeSeeder()
        var configuration = configuration()
        configuration.briefingCount = 2
        configuration.qualificationCount = 2
        configuration.electricalSafetyCount = 2
        configuration.firePermitCount = 1

        let result = try await seeder.generate(configuration)

        XCTAssertEqual(result.recordCount, 7)
        XCTAssertEqual(store.briefingItems.count, 2)
        XCTAssertEqual(store.proofOfQualificationItems.count, 2)
        XCTAssertEqual(store.electricalSafetyItems.count, 2)
        XCTAssertEqual(store.firePermitItems.count, 1)
        XCTAssertEqual(seeder.inventory.instructionCount, 7)
        // Everything but the fire permit is a draft without a report.
        XCTAssertEqual(seeder.inventory.draftCount, 6)
        XCTAssertTrue(store.briefingItems.allSatisfy { $0.status == .draft && $0.payload.briefing?.pdfData == nil })

        let permitItem = try XCTUnwrap(store.firePermitItems.first)
        let permit = try XCTUnwrap(permitItem.payload.firePermit)
        XCTAssertEqual(permitItem.status, .pendingSynchronization)
        XCTAssertFalse(permit.pdfData.isEmpty)

        let partnerNames = store.proofOfQualificationItems.compactMap(\.payload.proofOfQualification?.partner?.name)
            + store.electricalSafetyItems.compactMap(\.payload.electricalSafety?.partner?.name)
            + [permit.partner?.name].compactMap { $0 }
        XCTAssertEqual(Set(partnerNames), [LoadTestInstructionSource.testPartnerName])
    }

    func testClosedInstructionFormsCarryTheirReport() async throws {
        let (seeder, store, _) = makeSeeder()
        var configuration = configuration(closed: true)
        configuration.briefingCount = 1
        configuration.qualificationCount = 1
        configuration.electricalSafetyCount = 1

        _ = try await seeder.generate(configuration)

        let briefing = try XCTUnwrap(store.briefingItems.first)
        XCTAssertEqual(briefing.status, .pendingSynchronization)
        XCTAssertNotNil(briefing.payload.briefing?.completedAt)
        XCTAssertFalse(briefing.payload.briefing?.pdfData?.isEmpty ?? true)

        let qualification = try XCTUnwrap(store.proofOfQualificationItems.first)
        XCTAssertEqual(qualification.status, .pendingSynchronization)
        XCTAssertNotNil(qualification.payload.proofOfQualification?.completedAt)
        XCTAssertFalse(qualification.payload.proofOfQualification?.pdfData?.isEmpty ?? true)

        let electricalSafety = try XCTUnwrap(store.electricalSafetyItems.first)
        XCTAssertEqual(electricalSafety.status, .pendingSynchronization)
        XCTAssertNotNil(electricalSafety.payload.electricalSafety?.completedAt)
        XCTAssertFalse(electricalSafety.payload.electricalSafety?.pdfData?.isEmpty ?? true)
    }

    func testClosingInstructionDraftsRendersTheirReports() async throws {
        let (seeder, store, _) = makeSeeder()
        var configuration = configuration()
        configuration.briefingCount = 1
        configuration.qualificationCount = 1
        configuration.electricalSafetyCount = 1
        _ = try await seeder.generate(configuration)

        let closedCount = try await seeder.closeGeneratedDrafts(photoByteCount: 20_000)

        XCTAssertEqual(closedCount, 3)
        XCTAssertEqual(seeder.inventory.draftCount, 0)
        XCTAssertFalse(store.briefingItems.first?.payload.briefing?.pdfData?.isEmpty ?? true)
        XCTAssertFalse(store.proofOfQualificationItems.first?.payload.proofOfQualification?.pdfData?.isEmpty ?? true)
        XCTAssertFalse(store.electricalSafetyItems.first?.payload.electricalSafety?.pdfData?.isEmpty ?? true)

        try await seeder.deleteGenerated()
        XCTAssertTrue(store.items.isEmpty)
    }

    func testInstructionFormsNeedTheTestPartner() async throws {
        let other = SAPBriefingPartner(
            id: "2000002", client: "100", function: "Z1", name: "Muster GmbH", contactName: "",
            searchTerm1: "", searchTerm2: "", street: "", houseNumber: "", postalCode: "", city: "",
            country: "DE", email: ""
        )
        let (seeder, store, _) = makeSeeder(partners: [other])
        var configuration = configuration()
        configuration.briefingCount = 2
        configuration.firePermitCount = 2

        let availability = await seeder.availability()
        let result = try await seeder.generate(configuration)

        XCTAssertFalse(availability.hasTestPartner)
        XCTAssertFalse(availability.canGenerateInstructionForms)
        XCTAssertEqual(result.recordCount, 0)
        XCTAssertTrue(store.items.isEmpty)
    }

    func testTestPartnerIsPreferredUnderItsZ1Function() {
        func partner(_ id: String, _ function: String) -> SAPBriefingPartner {
            SAPBriefingPartner(
                id: id, client: "100", function: function, name: LoadTestInstructionSource.testPartnerName,
                contactName: "", searchTerm1: "NICHT BENUTZEN !", searchTerm2: "NICHT BENUTZEN !", street: "",
                houseNumber: "", postalCode: "", city: "", country: "DE", email: ""
            )
        }
        let source = LoadTestInstructionSource(partners: [partner("1", "ZT"), partner("2", "Z1")])

        XCTAssertEqual(source.testPartner?.id, "2")
    }

    func testDeletingRemovesOnlyGeneratedWorkAndItsPhotos() async throws {
        let (seeder, store, photos) = makeSeeder()
        let ownPhotoID = try await photos.saveJPEG(Data([0xFF, 0xD8, 0xFF, 0xD9]))
        let own = try await store.saveDefect(
            payload: DefectDraftPayload(
                technicalObject: TechnicalObjectReference(kind: .equipment, objectID: "10004711"),
                technicalObjectName: "Aufzug", dinGroup: nil, priority: .high,
                shortText: "Tür klemmt", longText: "", attachmentIDs: [ownPhotoID]
            ),
            status: .draft
        )
        _ = try await seeder.generate(configuration(defects: 2, ladders: 1, subdistributions: 1, photos: 3))
        let generatedPhotoID = try XCTUnwrap(
            store.defectItems.compactMap(\.payload.defect).first { $0.shortText.hasPrefix(LoadTestSeeder.marker) }?
                .attachmentIDs.first
        )

        try await seeder.deleteGenerated()

        XCTAssertEqual(store.items.map(\.id), [own.id])
        XCTAssertEqual(seeder.inventory, LoadTestInventory())
        let kept = try await photos.loadJPEG(id: ownPhotoID)
        XCTAssertFalse(kept.isEmpty)
        do {
            _ = try await photos.loadJPEG(id: generatedPhotoID)
            XCTFail("The generated photo should be gone")
        } catch {}
    }

    func testNothingIsGeneratedForAKindTheCacheHasNothingFor() async throws {
        let (seeder, store, _) = makeSeeder(parents: [])

        let availability = await seeder.availability()
        let result = try await seeder.generate(configuration(defects: 5))

        XCTAssertEqual(availability.defectParentCount, 0)
        XCTAssertEqual(availability.mobileLadderContextCount, 1)
        XCTAssertEqual(availability.subdistributionContextCount, 1)
        XCTAssertEqual(result.recordCount, 0)
        XCTAssertTrue(store.items.isEmpty)
    }

    func testGeneratedPhotoIsCloseToTheRequestedSize() {
        let data = LoadTestPhotoFactory.jpeg(approximateByteCount: 200_000)

        XCTAssertEqual(Double(data.count), 200_000, accuracy: 60_000)
        XCTAssertEqual(Array(data.prefix(2)), [0xFF, 0xD8])
    }
}
