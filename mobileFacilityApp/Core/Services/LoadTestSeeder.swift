#if DEBUG
import Foundation
import UIKit

/// What the load test panel asks the seeder to create.
struct LoadTestConfiguration: Equatable, Sendable {
    /// TFM5 and TFM7 take at most 20 photos per form; the forms and both
    /// upload builders refuse more.
    static let maximumFormPhotoCount = 20

    var defectCount = 0
    var mobileLadderCount = 0
    var subdistributionCount = 0
    /// The four I3 instruction forms. They carry a report, no photos.
    var briefingCount = 0
    var qualificationCount = 0
    var electricalSafetyCount = 0
    /// Fire permits are always closed: their form keeps no draft.
    var firePermitCount = 0
    var photosPerRecord = 5
    var photoByteCount = 2_000_000
    /// Closed records wait for the next synchronization and reach SAP with
    /// it; drafts stay on the device.
    var closesRecords = false

    var formPhotoCount: Int { min(photosPerRecord, Self.maximumFormPhotoCount) }
    var instructionCount: Int { briefingCount + qualificationCount + electricalSafetyCount + firePermitCount }
    var recordCount: Int { defectCount + mobileLadderCount + subdistributionCount + instructionCount }
    /// Whether generating queues anything for the next synchronization.
    var queuesRecords: Bool { closesRecords || firePermitCount > 0 }
    var photoCount: Int {
        defectCount * photosPerRecord + (mobileLadderCount + subdistributionCount) * formPhotoCount
    }
    var estimatedPhotoByteCount: Int64 { Int64(photoCount) * Int64(photoByteCount) }
}

/// What the SAP cache offers the generated records to hang on.
struct LoadTestAvailability: Equatable, Sendable {
    /// Open I1s; a defect is an I2 under one of them.
    var defectParentCount = 0
    var mobileLadderContextCount = 0
    var subdistributionContextCount = 0
    /// Buildings an I3 form can be created for.
    var instructionContextCount = 0
    /// The SAP test address every generated I3 form names.
    var hasTestPartner = false
    var hasBriefingTemplate = false
    var hasQualificationTemplate = false

    var canGenerateInstructionForms: Bool { instructionContextCount > 0 && hasTestPartner }
}

/// Generated records still on the device.
struct LoadTestInventory: Equatable, Sendable {
    var defectCount = 0
    var mobileLadderCount = 0
    var subdistributionCount = 0
    var photoCount = 0
    /// Generated records that are still drafts and can be closed.
    var draftCount = 0
    var briefingCount = 0
    var qualificationCount = 0
    var electricalSafetyCount = 0
    var firePermitCount = 0

    var instructionCount: Int { briefingCount + qualificationCount + electricalSafetyCount + firePermitCount }
    var recordCount: Int { defectCount + mobileLadderCount + subdistributionCount + instructionCount }
}

struct LoadTestResult: Equatable, Sendable {
    var recordCount = 0
    var photoCount = 0
    /// Writing the records and their photos.
    var generationDuration: TimeInterval = 0
    /// Reading the whole offline queue back afterwards, which is what every
    /// screen showing local work waits for.
    var reloadDuration: TimeInterval = 0
    var wasCancelled = false
}

enum LoadTestSeederError: LocalizedError {
    case photoGenerationFailed
    case reportFailed

    var errorDescription: String? {
        switch self {
        case .photoGenerationFailed: "The test photo could not be generated."
        case .reportFailed: "The report of a generated form could not be rendered."
        }
    }
}

/// Debug-only generator behind the load test panel: I2 defects, mobile
/// ladders (TFM5) and sub-distributions (TFM7) with photos, and the four I3
/// instruction forms, written the way their forms save them so the lists, the
/// forms and the upload builders see ordinary local work.
///
/// Every generated record carries `marker` (defects in the short text, TFM5
/// and TFM7 in their local draft ID, the I3 forms in their task text), which
/// is how `deleteGenerated` tells them from a technician's own work.
@MainActor
final class LoadTestSeeder {
    static let marker = "LOADTEST"

    private let offlineWorkStore: OfflineWorkStore
    private let photoStore: any PhotoAttachmentStore
    private let mobileLadderProvider: any MobileLadderCreationProviding
    private let subdistributionProvider: any SubdistributionCreationProviding
    private let loadDefectParents: @MainActor () async -> [DefectParentNotification]
    private let loadDefectObjects: @MainActor () async -> [DefectObjectOption]
    private let loadInstructionSource: @MainActor () -> LoadTestInstructionSource
    /// Photos written for the record being built. Removed again when the
    /// record itself is not saved.
    private var stagedPhotoIDs: [String] = []

    init(
        offlineWorkStore: OfflineWorkStore,
        photoStore: any PhotoAttachmentStore,
        mobileLadderProvider: any MobileLadderCreationProviding,
        subdistributionProvider: any SubdistributionCreationProviding,
        loadDefectParents: @escaping @MainActor () async -> [DefectParentNotification],
        loadDefectObjects: @escaping @MainActor () async -> [DefectObjectOption] = { [] },
        loadInstructionSource: @escaping @MainActor () -> LoadTestInstructionSource = { LoadTestInstructionSource() }
    ) {
        self.offlineWorkStore = offlineWorkStore
        self.photoStore = photoStore
        self.mobileLadderProvider = mobileLadderProvider
        self.subdistributionProvider = subdistributionProvider
        self.loadDefectParents = loadDefectParents
        self.loadDefectObjects = loadDefectObjects
        self.loadInstructionSource = loadInstructionSource
    }

    func availability() async -> LoadTestAvailability {
        let instruction = loadInstructionSource()
        return LoadTestAvailability(
            defectParentCount: await loadDefectParents().count,
            mobileLadderContextCount: await mobileLadderData()?.contexts.count ?? 0,
            subdistributionContextCount: await subdistributionContexts().count,
            instructionContextCount: instruction.contexts.count,
            hasTestPartner: instruction.testPartner != nil,
            hasBriefingTemplate: instruction.briefingTemplate != nil,
            hasQualificationTemplate: instruction.qualificationTemplate != nil
        )
    }

    var inventory: LoadTestInventory {
        offlineWorkStore.items.reduce(into: LoadTestInventory()) { inventory, item in
            guard Self.isGenerated(item) else { return }
            if item.status == .draft { inventory.draftCount += 1 }
            switch item.payload {
            case let .defect(defect):
                inventory.defectCount += 1
                inventory.photoCount += defect.attachmentIDs.count
            case let .mobileLadder(draft):
                inventory.mobileLadderCount += 1
                inventory.photoCount += draft.photoAttachments.count
            case let .subdistribution(draft):
                inventory.subdistributionCount += 1
                inventory.photoCount += draft.photoAttachments.count
            case .briefing: inventory.briefingCount += 1
            case .proofOfQualification: inventory.qualificationCount += 1
            case .electricalSafety: inventory.electricalSafetyCount += 1
            case .firePermit: inventory.firePermitCount += 1
            default:
                break
            }
        }
    }

    func generate(
        _ configuration: LoadTestConfiguration,
        progress: @escaping @MainActor (_ done: Int, _ total: Int) -> Void = { _, _ in }
    ) async throws -> LoadTestResult {
        let started = Date()
        var result = LoadTestResult()
        let total = configuration.recordCount
        let runTag = Self.runTag(started)

        do {
            var jpeg: Data?
            if configuration.photoCount > 0 {
                let byteCount = configuration.photoByteCount
                // One image for the whole run: the load is the number and
                // size of the files, and a fresh image per photo would only
                // make generating them slow.
                let data = await Task.detached(priority: .userInitiated) {
                    LoadTestPhotoFactory.jpeg(approximateByteCount: byteCount)
                }.value
                guard !data.isEmpty else { throw LoadTestSeederError.photoGenerationFailed }
                jpeg = data
            }

            let parents = configuration.defectCount > 0 ? await loadDefectParents() : []
            let objects = parents.isEmpty ? [] : await loadDefectObjects()
            let objectsByReference = Dictionary(objects.map { ($0.reference, $0) }, uniquingKeysWith: { first, _ in first })
            let ladderData = configuration.mobileLadderCount > 0 ? await mobileLadderData() : nil
            let subdistributions = configuration.subdistributionCount > 0 ? await subdistributionContexts() : []

            func finish(_ items: [OfflineWorkItem], photoCount: Int) async throws {
                try await offlineWorkStore.saveLoadTestItems(items)
                stagedPhotoIDs = []
                result.recordCount += 1
                result.photoCount += photoCount
                progress(result.recordCount, total)
            }

            if !parents.isEmpty {
                for index in 0..<configuration.defectCount {
                    try Task.checkCancellation()
                    let item = try await makeDefect(
                        label: Self.label(runTag, index), index: index,
                        parent: parents[index % parents.count], objectsByReference: objectsByReference,
                        configuration: configuration, jpeg: jpeg
                    )
                    try await finish([item], photoCount: item.payload.defect?.attachmentIDs.count ?? 0)
                }
            }
            if let ladderData, !ladderData.contexts.isEmpty {
                for index in 0..<configuration.mobileLadderCount {
                    try Task.checkCancellation()
                    let items = try await makeMobileLadder(
                        label: Self.label(runTag, index), index: index,
                        context: ladderData.contexts[index % ladderData.contexts.count],
                        catalog: ladderData.catalog, configuration: configuration, jpeg: jpeg
                    )
                    try await finish(items, photoCount: items.first?.payload.mobileLadder?.photoAttachments.count ?? 0)
                }
            }
            if !subdistributions.isEmpty {
                for index in 0..<configuration.subdistributionCount {
                    try Task.checkCancellation()
                    let items = try await makeSubdistribution(
                        label: Self.label(runTag, index), index: index,
                        context: subdistributions[index % subdistributions.count],
                        configuration: configuration, jpeg: jpeg
                    )
                    try await finish(items, photoCount: items.first?.payload.subdistribution?.photoAttachments.count ?? 0)
                }
            }

            let instruction = configuration.instructionCount > 0 ? loadInstructionSource() : nil
            if let instruction, let partner = instruction.testPartner, !instruction.contexts.isEmpty {
                let contexts = instruction.contexts
                let status: OfflineWorkStatus = configuration.closesRecords ? .pendingSynchronization : .draft
                if let template = instruction.briefingTemplate {
                    for index in 0..<configuration.briefingCount {
                        try Task.checkCancellation()
                        var draft = LoadTestInstructionForms.briefing(
                            label: Self.label(runTag, index), context: contexts[index % contexts.count],
                            partner: partner, template: template, source: instruction
                        )
                        if configuration.closesRecords {
                            draft = try await LoadTestInstructionForms.closed(
                                draft, source: instruction, offlineWorkStore: offlineWorkStore
                            )
                        }
                        try await finish([workItem(.briefing, .briefing(draft), status: status)], photoCount: 0)
                    }
                }
                if let template = instruction.qualificationTemplate {
                    for index in 0..<configuration.qualificationCount {
                        try Task.checkCancellation()
                        var draft = LoadTestInstructionForms.qualification(
                            label: Self.label(runTag, index), context: contexts[index % contexts.count],
                            partner: partner, template: template, source: instruction
                        )
                        if configuration.closesRecords {
                            draft = try await LoadTestInstructionForms.closed(draft, offlineWorkStore: offlineWorkStore)
                        }
                        try await finish(
                            [workItem(.proofOfQualification, .proofOfQualification(draft), status: status)],
                            photoCount: 0
                        )
                    }
                }
                for index in 0..<configuration.electricalSafetyCount {
                    try Task.checkCancellation()
                    var draft = LoadTestInstructionForms.electricalSafety(
                        label: Self.label(runTag, index), context: contexts[index % contexts.count],
                        partner: partner, source: instruction
                    )
                    if configuration.closesRecords {
                        draft = try await LoadTestInstructionForms.closed(draft)
                    }
                    try await finish([workItem(.electricalSafety, .electricalSafety(draft), status: status)], photoCount: 0)
                }
                for index in 0..<configuration.firePermitCount {
                    try Task.checkCancellation()
                    let permit = try await LoadTestInstructionForms.firePermit(
                        label: Self.label(runTag, index), context: contexts[index % contexts.count],
                        partner: partner, source: instruction
                    )
                    try await finish(
                        [workItem(.firePermit, .firePermit(permit), status: .pendingSynchronization)],
                        photoCount: 0
                    )
                }
            }
        } catch is CancellationError {
            await discardStagedPhotos()
            result.wasCancelled = true
        } catch {
            await discardStagedPhotos()
            await offlineWorkStore.load()
            throw error
        }

        result.generationDuration = Date().timeIntervalSince(started)
        let reloadStarted = Date()
        await offlineWorkStore.load()
        result.reloadDuration = Date().timeIntervalSince(reloadStarted)
        return result
    }

    /// Closes the generated drafts as their forms would, so they wait for the
    /// next synchronization. Returns how many were closed.
    ///
    /// A sub-distribution cannot be closed while a documentation position has
    /// no photo; such a position gets one of `photoByteCount`.
    func closeGeneratedDrafts(photoByteCount: Int) async throws -> Int {
        await offlineWorkStore.load()
        let drafts = offlineWorkStore.items.filter { Self.isGenerated($0) && $0.status == .draft }
        let instruction = loadInstructionSource()
        var jpeg: Data?
        var closedCount = 0
        do {
            for item in drafts {
                var updated: [OfflineWorkItem] = []
                switch item.payload {
                case .defect:
                    updated = [closed(item, item.payload)]
                case var .mobileLadder(draft):
                    if draft.legacyIdentifiers == nil {
                        draft.legacyIdentifiers = MobileLadderIdentifierFactory.make()
                    }
                    draft.isClosedLocally = true
                    updated = [closed(item, .mobileLadder(draft))]
                case var .subdistribution(draft):
                    let undocumented = draft.inspectionItems.filter { row in
                        row.requiresDocumentation
                            && !draft.photoAttachments.contains { $0.inspectionItemID == row.id }
                    }
                    for row in undocumented {
                        if jpeg == nil {
                            let data = await Task.detached(priority: .userInitiated) {
                                LoadTestPhotoFactory.jpeg(approximateByteCount: photoByteCount)
                            }.value
                            guard !data.isEmpty else { throw LoadTestSeederError.photoGenerationFailed }
                            jpeg = data
                        }
                        let photos = try await savePhotos(1, jpeg: jpeg)
                        draft.photoAttachments += photos.map {
                            SubdistributionPhotoAttachment(
                                localAttachmentID: $0.localAttachmentID, inspectionItemID: row.id,
                                sapElementID: row.commentElementID, capturedAt: $0.capturedAt,
                                sapDocumentID: UUID().uuidString.uppercased()
                            )
                        }
                        // The generator only writes a collection for a row
                        // that has photos, so this row has none yet.
                        updated.append(photoCollection(
                            workflow: .subdistribution, ownerID: draft.localDraftID, rowID: row.id,
                            titleKey: "subdistribution.photos.title", subtitle: row.title, attachments: photos
                        ))
                    }
                    draft.photoAttachments.sort { $0.capturedAt < $1.capturedAt }
                    if draft.legacyIdentifiers == nil {
                        draft.legacyIdentifiers = SubdistributionIdentifierFactory.make()
                    }
                    draft.reportPDF = SubdistributionPDFReport.make(draft: draft)
                    if draft.pdfDocumentID == nil { draft.pdfDocumentID = UUID().uuidString.uppercased() }
                    draft.isClosedLocally = true
                    updated.insert(closed(item, .subdistribution(draft)), at: 0)
                case let .briefing(draft):
                    let report = try await LoadTestInstructionForms.closed(
                        draft, source: instruction, offlineWorkStore: offlineWorkStore
                    )
                    updated = [closed(item, .briefing(report))]
                case let .proofOfQualification(draft):
                    let report = try await LoadTestInstructionForms.closed(draft, offlineWorkStore: offlineWorkStore)
                    updated = [closed(item, .proofOfQualification(report))]
                case let .electricalSafety(draft):
                    updated = [closed(item, .electricalSafety(try await LoadTestInstructionForms.closed(draft)))]
                default:
                    continue
                }
                try await offlineWorkStore.saveLoadTestItems(updated)
                stagedPhotoIDs = []
                closedCount += 1
            }
        } catch {
            await discardStagedPhotos()
            await offlineWorkStore.load()
            throw error
        }
        await offlineWorkStore.load()
        return closedCount
    }

    /// Removes the generated records, their photo collections and photo
    /// files. Anything without the marker is left alone.
    func deleteGenerated() async throws {
        await offlineWorkStore.load()
        let items = offlineWorkStore.items
        let records = items.filter(Self.isGenerated)
        // A defect's photo workspace is owned by its work item ID, a form's
        // by its local draft ID.
        let owners = Set(records.map { record -> String in
            record.payload.mobileLadder?.localDraftID
                ?? record.payload.subdistribution?.localDraftID
                ?? record.id.uuidString
        })
        let collections = items.filter {
            guard let scope = $0.payload.photoCollection?.scope else { return false }
            return owners.contains(scope.ownerID)
        }

        var photoIDs = Set<String>()
        for record in records {
            photoIDs.formUnion(record.payload.defect?.attachmentIDs ?? [])
            photoIDs.formUnion(record.payload.mobileLadder?.photoAttachments.map(\.localAttachmentID) ?? [])
            photoIDs.formUnion(record.payload.subdistribution?.photoAttachments.map(\.localAttachmentID) ?? [])
        }
        for collection in collections {
            photoIDs.formUnion(collection.payload.photoCollection?.attachments.map(\.localAttachmentID) ?? [])
        }

        try await offlineWorkStore.deleteLoadTestItems(ids: (records + collections).map(\.id))
        for id in photoIDs {
            try? await photoStore.delete(id: id)
        }
        await offlineWorkStore.load()
    }

    static func isGenerated(_ item: OfflineWorkItem) -> Bool {
        switch item.payload {
        case let .defect(defect): defect.shortText.hasPrefix(marker)
        case let .mobileLadder(draft): draft.localDraftID.hasPrefix(marker)
        case let .subdistribution(draft): draft.localDraftID.hasPrefix(marker)
        case let .briefing(draft): draft.taskDescription.hasPrefix(marker)
        case let .proofOfQualification(draft): draft.taskDescription.hasPrefix(marker)
        case let .electricalSafety(draft): draft.workDescription.hasPrefix(marker)
        case let .firePermit(draft): draft.workDescription.hasPrefix(marker)
        default: false
        }
    }

    // MARK: - Records

    /// An I2 from the defect form. It needs an open I1 of the same object
    /// (`CREATE_TFM4I2` rejects an empty `REFNUM`), so the object is the
    /// parent's own.
    private func makeDefect(
        label: String,
        index: Int,
        parent: DefectParentNotification,
        objectsByReference: [TechnicalObjectReference: DefectObjectOption],
        configuration: LoadTestConfiguration,
        jpeg: Data?
    ) async throws -> OfflineWorkItem {
        let reference = parent.equipmentID.isEmpty
            ? TechnicalObjectReference(kind: .functionalLocation, objectID: parent.functionalLocationID)
            : TechnicalObjectReference(kind: .equipment, objectID: parent.equipmentID)
        let object = objectsByReference[reference]
        let photos = try await savePhotos(configuration.photosPerRecord, jpeg: jpeg)
        let priorities = DefectPriority.allCases
        let payload = DefectDraftPayload(
            technicalObject: reference,
            technicalObjectName: object?.name ?? reference.objectID,
            dinGroup: object?.dinGroup,
            priority: priorities[index % priorities.count],
            shortText: "\(Self.marker) I2 \(label)",
            longText: "Generated by the load test panel. Not a real defect.",
            attachmentIDs: photos.map(\.localAttachmentID),
            category: .technical,
            parentNotificationID: parent.id,
            parentNotificationTitle: parent.title
        )
        return workItem(
            .defect, .defect(payload),
            status: configuration.closesRecords ? .pendingSynchronization : .draft
        )
    }

    /// The ladder first, then one photo collection per inspection row.
    private func makeMobileLadder(
        label: String,
        index: Int,
        context: MobileLadderCreationContext,
        catalog: MobileLadderCatalog,
        configuration: LoadTestConfiguration,
        jpeg: Data?
    ) async throws -> [OfflineWorkItem] {
        let template = context.legacyContext.template
        var draft = MobileLadderDraftPayload(localDraftID: "\(Self.marker)-\(UUID().uuidString)")
        draft.context = context
        draft.designation = "\(Self.marker) \(label)"
        draft.room = "LT-\(index + 1)"
        draft.factoryNumber = label
        draft.inventoryNumber = label
        draft.rungCount = "7"
        var proposals: [String: String] = [:]
        for field in MobileLadderCatalogField.allCases {
            let templateValues = template.characteristics.first {
                $0.name.caseInsensitiveCompare(field.characteristicName) == .orderedSame
            }?.values.map { $0.title.isEmpty ? $0.value : $0.title } ?? []
            let options = templateValues.isEmpty ? catalog.options(for: field) : templateValues
            // "Pflege durch Admin" needs a proposal to be closable, so it is
            // only taken when the value list offers nothing else.
            if let regular = options.first(where: { !MasterDataProposalRules.isAdmin(text: $0) }) {
                draft.setValue(regular, for: field)
            } else if let admin = options.first {
                draft.setValue(admin, for: field)
                proposals[field.characteristicName] = Self.marker
            } else {
                draft.setValue(Self.marker, for: field)
            }
        }
        draft.proposals = proposals
        draft.inspectionItems = template.inspectionItems.enumerated().map { offset, definition in
            var item = MobileLadderInspectionItem(definition: definition, number: offset + 1)
            item.result = .okay
            return item
        }

        let photos = try await savePhotos(
            draft.inspectionItems.isEmpty ? 0 : configuration.formPhotoCount, jpeg: jpeg
        )
        let rows = Self.distribute(photos, over: draft.inspectionItems.map(\.id))
        var collections: [OfflineWorkItem] = []
        for row in rows {
            guard let item = draft.inspectionItems.first(where: { $0.id == row.rowID }) else { continue }
            draft.photoAttachments += row.attachments.map {
                MobileLadderPhotoAttachment(
                    localAttachmentID: $0.localAttachmentID, inspectionItemID: item.id,
                    sapElementID: item.commentElementID, capturedAt: $0.capturedAt,
                    sapDocumentID: UUID().uuidString.uppercased()
                )
            }
            collections.append(photoCollection(
                workflow: .mobileLadder, ownerID: draft.localDraftID, rowID: item.id,
                titleKey: "mobileLadder.photos.title", subtitle: item.title, attachments: row.attachments
            ))
        }
        draft.photoAttachments.sort { $0.capturedAt < $1.capturedAt }

        if configuration.closesRecords {
            draft.legacyIdentifiers = MobileLadderIdentifierFactory.make()
            draft.isClosedLocally = true
        }
        let ladder = workItem(
            .mobileLadder, .mobileLadder(draft),
            status: configuration.closesRecords ? .pendingSynchronization : .draft
        )
        return [ladder] + collections
    }

    /// The sub-distribution first, then one photo collection per inspection
    /// row.
    private func makeSubdistribution(
        label: String,
        index: Int,
        context: SubdistributionCreationContext,
        configuration: LoadTestConfiguration,
        jpeg: Data?
    ) async throws -> [OfflineWorkItem] {
        let template = context.legacyContext.template
        var draft = SubdistributionDraftPayload(localDraftID: "\(Self.marker)-\(UUID().uuidString)")
        draft.context = context
        for characteristic in template.characteristics {
            var value: String
            switch characteristic.kind {
            case .choice: value = characteristic.values.first?.value ?? ""
            case .numeric: value = "1"
            case .text: value = "\(Self.marker) \(label)"
            }
            if characteristic.maximumLength > 0 {
                value = String(value.prefix(characteristic.maximumLength))
            }
            draft.characteristicValues[characteristic.name] = value
        }
        draft.inspectionItems = template.inspectionItems.enumerated().map { offset, definition in
            var item = SubdistributionInspectionItem(definition: definition, number: offset + 1)
            if item.requiresResult {
                // Code 1 is the SAP value for "in order"; without it the
                // first delivered value is taken, which counts as a defect.
                item.result = item.resultValues.first { $0.value == "1" }?.value ?? item.resultValues.first?.value
            }
            if item.requiresDocumentation {
                item.comment = "\(Self.marker) \(label)"
            }
            return item
        }
        if draft.inspectionItems.contains(where: \.isDefective) {
            draft.defectCloseAction = .close
        }

        // A documentation position cannot be closed without a photo, so
        // those rows are served first and get one even when the panel asks
        // for none.
        let documentationRows = draft.inspectionItems.filter(\.requiresDocumentation).map(\.id)
        let otherRows = draft.inspectionItems.filter { !$0.requiresDocumentation }.map(\.id)
        let photoCount = configuration.closesRecords
            ? max(configuration.formPhotoCount, documentationRows.count)
            : configuration.formPhotoCount
        let photos = try await savePhotos(
            draft.inspectionItems.isEmpty ? 0 : min(photoCount, LoadTestConfiguration.maximumFormPhotoCount),
            jpeg: jpeg
        )
        let rows = Self.distribute(photos, over: documentationRows + otherRows)
        var collections: [OfflineWorkItem] = []
        for row in rows {
            guard let item = draft.inspectionItems.first(where: { $0.id == row.rowID }) else { continue }
            draft.photoAttachments += row.attachments.map {
                SubdistributionPhotoAttachment(
                    localAttachmentID: $0.localAttachmentID, inspectionItemID: item.id,
                    sapElementID: item.commentElementID, capturedAt: $0.capturedAt,
                    sapDocumentID: UUID().uuidString.uppercased()
                )
            }
            collections.append(photoCollection(
                workflow: .subdistribution, ownerID: draft.localDraftID, rowID: item.id,
                titleKey: "subdistribution.photos.title", subtitle: item.title, attachments: row.attachments
            ))
        }
        draft.photoAttachments.sort { $0.capturedAt < $1.capturedAt }

        if configuration.closesRecords {
            draft.legacyIdentifiers = SubdistributionIdentifierFactory.make()
            draft.reportPDF = SubdistributionPDFReport.make(draft: draft)
            draft.pdfDocumentID = UUID().uuidString.uppercased()
            draft.isClosedLocally = true
        }
        let subdistribution = workItem(
            .subdistribution, .subdistribution(draft),
            status: configuration.closesRecords ? .pendingSynchronization : .draft
        )
        return [subdistribution] + collections
    }

    // MARK: - Helpers

    private func mobileLadderData() async -> MobileLadderCreationData? {
        guard let data = try? await mobileLadderProvider.loadMobileLadderCreationData(for: offlineWorkStore.workerID)
        else { return nil }
        // A template without inspection positions cannot be closed.
        return MobileLadderCreationData(
            contexts: data.contexts.filter { !$0.legacyContext.template.inspectionItems.isEmpty },
            catalog: data.catalog
        )
    }

    private func subdistributionContexts() async -> [SubdistributionCreationContext] {
        let data = try? await subdistributionProvider.loadSubdistributionCreationData(for: offlineWorkStore.workerID)
        return (data?.contexts ?? []).filter { !$0.legacyContext.template.inspectionItems.isEmpty }
    }

    private func workItem(
        _ type: OfflineWorkType,
        _ payload: OfflineWorkPayload,
        status: OfflineWorkStatus
    ) -> OfflineWorkItem {
        let now = Date()
        return OfflineWorkItem(
            id: UUID(), workerID: offlineWorkStore.workerID, type: type, status: status,
            payload: payload, createdAt: now, updatedAt: now, syncError: nil
        )
    }

    /// The same work item, queued for the next synchronization.
    private func closed(_ item: OfflineWorkItem, _ payload: OfflineWorkPayload) -> OfflineWorkItem {
        OfflineWorkItem(
            id: item.id, workerID: item.workerID, type: item.type, status: .pendingSynchronization,
            payload: payload, createdAt: item.createdAt, updatedAt: Date(), syncError: nil
        )
    }

    private func photoCollection(
        workflow: LocalPhotoWorkflow,
        ownerID: String,
        rowID: String,
        titleKey: String.LocalizationValue,
        subtitle: String,
        attachments: [LocalPhotoAttachment]
    ) -> OfflineWorkItem {
        workItem(
            .photoCollection,
            .photoCollection(PhotoCollectionDraftPayload(
                scope: LocalPhotoScope(
                    workflow: workflow, ownerID: ownerID, rowID: rowID,
                    displayTitle: String(localized: titleKey, bundle: .appLanguage),
                    displaySubtitle: subtitle
                ),
                attachments: attachments
            )),
            status: .draft
        )
    }

    private func savePhotos(_ count: Int, jpeg: Data?) async throws -> [LocalPhotoAttachment] {
        guard count > 0, let jpeg else { return [] }
        let now = Date()
        var attachments: [LocalPhotoAttachment] = []
        for index in 0..<count {
            let id = try await photoStore.saveJPEG(jpeg)
            stagedPhotoIDs.append(id)
            attachments.append(LocalPhotoAttachment(
                localAttachmentID: id,
                capturedAt: now.addingTimeInterval(Double(index) / 1000)
            ))
        }
        return attachments
    }

    private func discardStagedPhotos() async {
        for id in stagedPhotoIDs {
            try? await photoStore.delete(id: id)
        }
        stagedPhotoIDs = []
    }

    /// Photo `n` goes to row `n % rows`, so every row has one before any has
    /// two.
    private static func distribute(
        _ attachments: [LocalPhotoAttachment],
        over rowIDs: [String]
    ) -> [(rowID: String, attachments: [LocalPhotoAttachment])] {
        guard !rowIDs.isEmpty else { return [] }
        var byRow: [String: [LocalPhotoAttachment]] = [:]
        for (index, attachment) in attachments.enumerated() {
            byRow[rowIDs[index % rowIDs.count], default: []].append(attachment)
        }
        return rowIDs.compactMap { rowID in
            byRow[rowID].map { (rowID, $0) }
        }
    }

    private static func runTag(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HHmmss"
        return formatter.string(from: date)
    }

    private static func label(_ runTag: String, _ index: Int) -> String {
        "\(runTag)-\(String(format: "%04d", index + 1))"
    }
}

/// A JPEG of roughly the requested size. Noise does not compress, so the
/// file size follows the pixel count and can be steered with it.
enum LoadTestPhotoFactory {
    static func jpeg(approximateByteCount target: Int) -> Data {
        var best = Data()
        var pixelCount = Double(max(target, 10_000))
        for _ in 0..<4 {
            let width = max(64, Int((pixelCount * 4 / 3).squareRoot()))
            let height = max(48, width * 3 / 4)
            guard let data = noise(width: width, height: height) else { break }
            best = data
            let ratio = Double(target) / Double(data.count)
            if abs(ratio - 1) < 0.1 { break }
            pixelCount = Double(width * height) * ratio
        }
        return best
    }

    private static func noise(width: Int, height: Int) -> Data? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            arc4random_buf(buffer.baseAddress, buffer.count)
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(
                  width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
              )
        else { return nil }
        // The quality the camera adapter saves with.
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.82)
    }
}
#endif
