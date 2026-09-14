import Foundation
import Observation

@MainActor
@Observable
final class SubdistributionCreationViewModel {
    enum State: Equatable { case loading, ready, unavailable }

    enum Feedback: Identifiable {
        case validation
        case queued
        case failed(String)

        var id: String {
            switch self {
            case .validation: "validation"
            case .queued: "queued"
            case let .failed(message): "failed-\(message)"
            }
        }
    }

    private let provider: any SubdistributionCreationProviding
    private let offlineWorkStore: OfflineWorkStore
    private let photoStore: any PhotoAttachmentStore
    private let isDemo: Bool
    private(set) var workItemID: UUID?
    private(set) var itemStatus: OfflineWorkStatus?
    private(set) var state: State = .loading
    private(set) var contexts: [SubdistributionCreationContext] = []
    var draft: SubdistributionDraftPayload
    var selectedBusinessEntity: String?
    var selectedBuilding: String?
    var selectedParentLocation: String?
    var feedback: Feedback?
    private(set) var isSaving = false

    init(
        provider: any SubdistributionCreationProviding,
        offlineWorkStore: OfflineWorkStore,
        photoStore: any PhotoAttachmentStore = UnavailablePhotoAttachmentStore(),
        isDemo: Bool,
        item: OfflineWorkItem?
    ) {
        self.provider = provider
        self.offlineWorkStore = offlineWorkStore
        self.photoStore = photoStore
        self.isDemo = isDemo
        workItemID = item?.id
        itemStatus = item?.status
        draft = item?.payload.subdistribution ?? SubdistributionDraftPayload()
        selectedBusinessEntity = draft.context?.businessEntity
        selectedBuilding = draft.context?.building
        selectedParentLocation = draft.context?.parentLocation
    }

    var businessEntities: [String] { contexts.map(\.businessEntity).uniquedAndSorted() }
    var businessEntityItems: [BriefingBusinessEntityItem] {
        let grouped = Dictionary(grouping: contexts, by: \.businessEntity)
        return grouped.map { entityTitle, matchingContexts in
            let buildingCount = Set(matchingContexts.map(\.building)).count
            let code = matchingContexts.first?.legacyContext.businessEntity
            return BriefingBusinessEntityItem(
                id: entityTitle,
                title: entityTitle,
                code: (code?.isEmpty == false && code != entityTitle) ? code : nil,
                buildingCount: buildingCount
            )
        }.sorted { $0.title < $1.title }
    }
    var buildings: [String] {
        contexts.filter { selectedBusinessEntity == nil || $0.businessEntity == selectedBusinessEntity }
            .map(\.building).uniquedAndSorted()
    }
    var parentLocations: [String] {
        contexts.filter {
            (selectedBusinessEntity == nil || $0.businessEntity == selectedBusinessEntity)
                && (selectedBuilding == nil || $0.building == selectedBuilding)
        }.map(\.parentLocation).uniquedAndSorted()
    }
    var template: SubdistributionLegacyTemplate? { draft.context?.legacyContext.template }
    /// The SAP schema is already available after the cache is loaded, even
    /// before a parent place is selected. Keep its fields visible so a
    /// technician understands what the form requires; edits remain locked
    /// until the selected context supplies the final template snapshot.
    var masterDataTemplate: SubdistributionLegacyTemplate? {
        template ?? contexts.first?.legacyContext.template
    }
    var isContextSelected: Bool { draft.context != nil }
    var isReadOnly: Bool {
        if draft.isClosedLocally { return true }
        guard let itemStatus else { return false }
        return itemStatus != .draft
    }
    var totalPhotoCount: Int { draft.photoAttachments.count }
    var hasDefect: Bool { !draft.isOutOfOperation && draft.inspectionItems.contains(where: \.isDefective) }
    var needsDefectResolution: Bool { hasDefect && draft.defectCloseAction == nil }
    /// Enables the close action once all form content is complete. A defect
    /// still needs its verified `MIAR`/`MMAB` decision after the technician
    /// confirms that they want to close the notification.
    var isReadyForCloseAction: Bool {
        !isReadOnly && draft.context != nil && !isSaving && draft.photoAttachments.count <= 20
            && requiredCharacteristicsAreValid
            && hasEquipmentDesignation
            && (draft.isOutOfOperation || draft.inspectionItems.allSatisfy { !isInspectionItemIncomplete($0) })
    }
    var isReadyToClose: Bool {
        isReadyForCloseAction
            && (!hasDefect || draft.defectCloseAction != nil)
    }

    func load() async {
        await offlineWorkStore.load()
        itemStatus = offlineWorkStore.subdistributionItem(id: workItemID)?.status ?? itemStatus
        do {
            let data = try await provider.loadSubdistributionCreationData(for: offlineWorkStore.workerID)
            contexts = data.contexts
            if let context = draft.context {
                applyTemplate(context.legacyContext.template)
                state = .ready
            } else {
                state = contexts.isEmpty ? .unavailable : .ready
            }
            synchronizePhotoAttachments()
        } catch is CancellationError {
            return
        } catch {
            // A persisted draft carries a complete SAP schema snapshot and
            // remains usable offline. A new production draft does not.
            if let context = draft.context {
                applyTemplate(context.legacyContext.template)
                state = .ready
                synchronizePhotoAttachments()
            } else {
                state = .unavailable
            }
        }
    }

    func selectBusinessEntity(_ value: String) {
        guard !isReadOnly else { return }
        selectedBusinessEntity = value
        selectedBuilding = nil
        selectedParentLocation = nil
        draft.context = nil
    }

    func selectBuilding(_ value: String) {
        guard !isReadOnly else { return }
        selectedBuilding = value
        selectedParentLocation = nil
        draft.context = nil
    }

    func selectParentLocation(_ value: String) {
        guard !isReadOnly else { return }
        selectedParentLocation = value
        guard let context = selectedContext else { return }
        draft.context = context
        draft.defectCloseAction = nil
        applyTemplate(context.legacyContext.template)
    }

    func setCharacteristicValue(_ value: String, for characteristic: SubdistributionCharacteristic) {
        guard !isReadOnly else { return }
        var normalized = value
        if characteristic.kind == .numeric { normalized = String(value.filter(\.isNumber)) }
        if characteristic.maximumLength > 0 { normalized = String(normalized.prefix(characteristic.maximumLength)) }
        draft.characteristicValues[characteristic.name] = normalized
    }

    func markEverythingOkay() {
        guard !isReadOnly, !draft.isOutOfOperation else { return }
        for index in draft.inspectionItems.indices where draft.inspectionItems[index].requiresResult {
            // Code 1 is Cordova's SAP result for Alles OK.  Do not invent it
            // if SAP did not deliver that value in the production value help.
            if draft.inspectionItems[index].resultValues.contains(where: { $0.value == "1" }) {
                draft.inspectionItems[index].result = "1"
            }
        }
        draft.defectCloseAction = nil
    }

    func selectDefectCloseAction(_ action: SubdistributionCloseAction) {
        guard !isReadOnly else { return }
        draft.defectCloseAction = action
    }

    func photoScope(for item: SubdistributionInspectionItem) -> LocalPhotoScope {
        LocalPhotoScope(
            workflow: .subdistribution, ownerID: draft.localDraftID, rowID: item.id,
            displayTitle: String(localized: "subdistribution.photos.title"), displaySubtitle: item.title
        )
    }

    func outOfOperationPhotoScope() -> LocalPhotoScope {
        LocalPhotoScope(
            workflow: .subdistribution,
            ownerID: draft.localDraftID,
            rowID: SubdistributionDraftPayload.statusRowID,
            displayTitle: String(localized: "subdistribution.photos.title"),
            displaySubtitle: String(localized: "subdistribution.outOfOperation")
        )
    }

    func remainingPhotoCapacity(excluding itemID: String) -> Int {
        let otherCount = draft.photoAttachments.filter { $0.inspectionItemID != itemID }.count
        return max(0, 20 - otherCount)
    }

    func photoCount(for itemID: String) -> Int {
        draft.photoAttachments.filter { $0.inspectionItemID == itemID }.count
    }

    /// Uses the same visible rule as the close action. A photo-documentation
    /// position is complete only after it has both its JPEG evidence and the
    /// linked comment; ordinary positions require the SAP result selector.
    func isInspectionItemIncomplete(_ item: SubdistributionInspectionItem) -> Bool {
        guard !draft.isOutOfOperation else { return false }
        let resultMissing = item.requiresResult && item.result == nil
        let documentationMissing = item.requiresDocumentation
            && (photoCount(for: item.id) == 0
                || item.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        return resultMissing || documentationMissing
    }

    func refreshPhotos() { synchronizePhotoAttachments() }

    /// `aBet` uses `INAK` and must not retain regular checklist outcomes or
    /// their evidence.  This mirrors the explicit destructive Cordova toggle.
    func confirmOutOfOperationChange(to value: Bool) async -> Bool {
        guard !isReadOnly, !isSaving, value != draft.isOutOfOperation else { return false }
        isSaving = true
        defer { isSaving = false }
        if value {
            let regularCollections = offlineWorkStore.photoCollectionItems.compactMap { item -> PhotoCollectionDraftPayload? in
                guard let payload = item.payload.photoCollection,
                      payload.scope.workflow == .subdistribution,
                      payload.scope.ownerID == draft.localDraftID,
                      payload.scope.rowID != SubdistributionDraftPayload.statusRowID else { return nil }
                return payload
            }
            let photoIDs = Set(
                draft.photoAttachments
                    .filter { $0.inspectionItemID != SubdistributionDraftPayload.statusRowID }
                    .map(\.localAttachmentID)
                    + regularCollections.flatMap { $0.attachments.map(\.localAttachmentID) }
            )
            do {
                for collection in regularCollections {
                    _ = try await offlineWorkStore.savePhotoCollection(scope: collection.scope, attachments: [])
                }
            } catch {
                feedback = .failed(error.localizedDescription)
                return false
            }
            for id in photoIDs { try? await photoStore.delete(id: id) }
            draft.photoAttachments.removeAll { $0.inspectionItemID != SubdistributionDraftPayload.statusRowID }
            for index in draft.inspectionItems.indices {
                draft.inspectionItems[index].result = nil
                draft.inspectionItems[index].action = nil
                draft.inspectionItems[index].comment = ""
            }
        } else {
            let statusCollections = offlineWorkStore.photoCollectionItems.compactMap { item -> PhotoCollectionDraftPayload? in
                guard let payload = item.payload.photoCollection,
                      payload.scope.workflow == .subdistribution,
                      payload.scope.ownerID == draft.localDraftID,
                      payload.scope.rowID == SubdistributionDraftPayload.statusRowID else { return nil }
                return payload
            }
            let photoIDs = Set(
                draft.photoAttachments
                    .filter { $0.inspectionItemID == SubdistributionDraftPayload.statusRowID }
                    .map(\.localAttachmentID)
                    + statusCollections.flatMap { $0.attachments.map(\.localAttachmentID) }
            )
            do {
                for collection in statusCollections {
                    _ = try await offlineWorkStore.savePhotoCollection(scope: collection.scope, attachments: [])
                }
            } catch {
                feedback = .failed(error.localizedDescription)
                return false
            }
            for id in photoIDs { try? await photoStore.delete(id: id) }
            draft.photoAttachments.removeAll { $0.inspectionItemID == SubdistributionDraftPayload.statusRowID }
            draft.outOfOperationComment = nil
        }
        draft.isOutOfOperation = value
        draft.defectCloseAction = value ? .leaveOpen : nil
        return true
    }

    func saveTemporarily() async -> Bool {
        await save(status: .draft, successFeedback: nil)
    }

    func close() async -> Bool {
        guard !isReadOnly else { return false }
        synchronizePhotoAttachments()
        guard isReadyToClose else {
            feedback = .validation
            return false
        }
        if !isDemo, draft.legacyIdentifiers == nil {
            draft.legacyIdentifiers = SubdistributionIdentifierFactory.make()
        }
        if draft.reportPDF == nil { draft.reportPDF = SubdistributionPDFReport.make(draft: draft) }
        if draft.pdfDocumentID == nil { draft.pdfDocumentID = UUID().uuidString.uppercased() }
        let previousClosed = draft.isClosedLocally
        draft.isClosedLocally = !isDemo
        // Demo proves the UX but never enters SAP's outgoing queue.
        let status: OfflineWorkStatus = isDemo ? .draft : .pendingSynchronization
        let didSave = await save(status: status, successFeedback: .queued, allowsClosedPayload: true)
        if !didSave { draft.isClosedLocally = previousClosed }
        return didSave
    }

    private var selectedContext: SubdistributionCreationContext? {
        guard let selectedBusinessEntity, let selectedBuilding, let selectedParentLocation else { return nil }
        return contexts.first {
            $0.businessEntity == selectedBusinessEntity && $0.building == selectedBuilding
                && $0.parentLocation == selectedParentLocation
        }
    }

    private var requiredCharacteristicsAreValid: Bool {
        guard let template else { return false }
        return template.characteristics.allSatisfy { characteristic in
            let value = draft.characteristicValues[characteristic.name, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !characteristic.required || !value.isEmpty else { return false }
            if characteristic.kind == .numeric, !value.isEmpty, Int(value) == nil { return false }
            return characteristic.maximumLength == 0 || value.count <= characteristic.maximumLength
        }
    }

    private var hasEquipmentDesignation: Bool {
        ["TFMUNTERVERT_BEZUNTERVERT", "TFMSCHUTZSCH_UNTERVERTEILUNG"].contains { name in
            !draft.characteristicValues[name, default: ""].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func applyTemplate(_ template: SubdistributionLegacyTemplate) {
        let oldItems = Dictionary(uniqueKeysWithValues: draft.inspectionItems.map { ($0.id, $0) })
        draft.inspectionItems = template.inspectionItems.enumerated().map { index, definition in
            var item = SubdistributionInspectionItem(definition: definition, number: index + 1)
            if let existing = oldItems[item.id] {
                item.result = existing.result
                item.action = existing.action
                item.comment = existing.comment
            }
            return item
        }
        let allowedNames = Set(template.characteristics.map(\.name))
        draft.characteristicValues = draft.characteristicValues.filter { allowedNames.contains($0.key) }
    }

    private func synchronizePhotoAttachments() {
        let existingByLocalID = Dictionary(uniqueKeysWithValues: draft.photoAttachments.map { ($0.localAttachmentID, $0) })
        var updated: [SubdistributionPhotoAttachment] = []
        for item in offlineWorkStore.photoCollectionItems {
            guard let collection = item.payload.photoCollection,
                  collection.scope.workflow == .subdistribution,
                  collection.scope.ownerID == draft.localDraftID,
                  let rowID = collection.scope.rowID else { continue }
            let sapElementID: String
            if rowID == SubdistributionDraftPayload.statusRowID {
                sapElementID = SubdistributionDraftPayload.outOfOperationCommentElementID
            } else if let inspection = draft.inspectionItems.first(where: { $0.id == rowID }) {
                sapElementID = inspection.commentElementID
            } else {
                continue
            }
            for attachment in collection.attachments {
                updated.append(SubdistributionPhotoAttachment(
                    localAttachmentID: attachment.localAttachmentID, inspectionItemID: rowID,
                    sapElementID: sapElementID, capturedAt: attachment.capturedAt,
                    sapDocumentID: existingByLocalID[attachment.localAttachmentID]?.sapDocumentID ?? UUID().uuidString.uppercased()
                ))
            }
        }
        draft.photoAttachments = updated.sorted { $0.capturedAt < $1.capturedAt }
    }

    private func save(
        status: OfflineWorkStatus,
        successFeedback: Feedback?,
        allowsClosedPayload: Bool = false
    ) async -> Bool {
        guard !isSaving, (allowsClosedPayload || !isReadOnly) else { return false }
        isSaving = true
        defer { isSaving = false }
        synchronizePhotoAttachments()
        do {
            let item = try await offlineWorkStore.saveSubdistribution(id: workItemID, payload: draft, status: status)
            workItemID = item.id
            itemStatus = item.status
            feedback = successFeedback
            return true
        } catch {
            feedback = .failed(error.localizedDescription)
            return false
        }
    }
}
