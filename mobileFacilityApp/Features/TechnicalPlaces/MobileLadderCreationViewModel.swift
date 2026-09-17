import Foundation
import Observation

@MainActor
@Observable
final class MobileLadderCreationViewModel {
    enum State: Equatable { case loading, ready, unavailable }
    enum Feedback: Identifiable {
        case validation, saved, queued, proposalSaved, failed(String)

        var id: String {
            switch self {
            case .validation: "validation"
            case .saved: "saved"
            case .queued: "queued"
            case .proposalSaved: "proposalSaved"
            case let .failed(message): "failed-\(message)"
            }
        }
    }

    private let provider: any MobileLadderCreationProviding
    private let offlineWorkStore: OfflineWorkStore
    private let photoStore: any PhotoAttachmentStore
    private let isDemo: Bool
    private(set) var workItemID: UUID?
    private(set) var itemStatus: OfflineWorkStatus?
    private(set) var state: State = .loading
    private(set) var catalog = MobileLadderCatalog.legacyReference
    private(set) var contexts: [MobileLadderCreationContext] = []
    var draft: MobileLadderDraftPayload
    var selectedBusinessEntity: String?
    var selectedBuilding: String?
    var selectedTrade: String?
    var feedback: Feedback?
    private(set) var isSaving = false

    init(
        provider: any MobileLadderCreationProviding,
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
        draft = item?.payload.mobileLadder ?? MobileLadderDraftPayload()
        selectedBusinessEntity = draft.context?.businessEntity
        selectedBuilding = draft.context?.building
        selectedTrade = draft.context?.trade
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
    var trades: [String] {
        contexts.filter {
            (selectedBusinessEntity == nil || $0.businessEntity == selectedBusinessEntity)
                && (selectedBuilding == nil || $0.building == selectedBuilding)
        }.map(\.trade).uniquedAndSorted()
    }
    var totalPhotoCount: Int { draft.photoAttachments.count }
    var isReadOnly: Bool {
        if draft.isClosedLocally == true { return true }
        guard let itemStatus else { return false }
        return itemStatus != .draft
    }
    var isReadyToClose: Bool {
        !isReadOnly
            && draft.context != nil
            && requiredValues.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            && (Int(draft.rungCount.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0) > 0
            && !draft.inspectionItems.isEmpty
            // Legacy TFM5 clears and disables inspection rows while the
            // header is marked Demontiert, so those rows are not required in
            // that explicit state.
            && (draft.isDisassembled || draft.inspectionItems.allSatisfy { $0.result != nil })
            && draft.photoAttachments.count <= 20
            && !isSaving
    }

    func load() async {
        await offlineWorkStore.load()
        itemStatus = offlineWorkStore.mobileLadderItem(id: workItemID)?.status ?? itemStatus
        setRungCount(draft.rungCount)
        do {
            let data = try await provider.loadMobileLadderCreationData(for: offlineWorkStore.workerID)
            contexts = data.contexts
            for field in MobileLadderCatalogField.allCases {
                let options = data.catalog.options(for: field)
                if !options.isEmpty {
                    catalog.options[field] = options
                }
            }
            if let context = draft.context {
                applyTemplateCatalog(context.legacyContext.template)
                if draft.inspectionItems.isEmpty { applyInspectionTemplate(context.legacyContext.template) }
                state = .ready
            } else {
                state = contexts.isEmpty ? .unavailable : .ready
            }
            synchronizePhotoAttachments()
        } catch is CancellationError {
            return
        } catch {
            if let context = draft.context {
                applyTemplateCatalog(context.legacyContext.template)
                if draft.inspectionItems.isEmpty { applyInspectionTemplate(context.legacyContext.template) }
                state = .ready
            } else {
                state = .unavailable
            }
        }
    }

    func selectBusinessEntity(_ value: String) {
        selectedBusinessEntity = value
        selectedBuilding = nil
        selectedTrade = nil
        draft.context = nil
    }

    func selectBuilding(_ value: String) {
        selectedBuilding = value
        selectedTrade = nil
        draft.context = nil
    }

    func selectTrade(_ value: String) {
        selectedTrade = value
        draft.context = nil
        useSelectedAddress()
    }

    func useSelectedAddress() {
        guard let selectedContext else { return }
        draft.context = selectedContext
        applyTemplateCatalog(selectedContext.legacyContext.template)
        applyInspectionTemplate(selectedContext.legacyContext.template)
        if draft.clientCompany.isEmpty {
            let companies = catalog.options(for: .clientCompany).filter { $0 != "Pflege durch Admin" }
            if companies.count == 1, let first = companies.first {
                draft.clientCompany = first
            }
        }
    }

    func setSelection(_ value: String, for field: MobileLadderCatalogField) {
        guard !isReadOnly else { return }
        switch field {
        case .material: draft.material = value
        case .constructionType: draft.constructionType = value
        case .manufacturer: draft.manufacturer = value
        case .clientCompany: draft.clientCompany = value
        }
    }

    /// Rung counts are numeric legacy values. Normalize input here as well as
    /// in the numeric keyboard field so pasted and reopened draft data cannot
    /// reintroduce text characters.
    func setRungCount(_ value: String) {
        guard !isReadOnly else { return }
        draft.rungCount = String(value.filter(\.isNumber))
    }

    func saveProposal(_ value: String, for field: MobileLadderCatalogField) -> Bool {
        let proposal = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !proposal.isEmpty else { return false }
        catalog.addProposal(proposal, for: field)
        setSelection(proposal, for: field)
        feedback = .proposalSaved
        return true
    }

    func markEverythingOkay() {
        guard !isReadOnly, !draft.isDisassembled else { return }
        for index in draft.inspectionItems.indices { draft.inspectionItems[index].result = .okay }
    }

    func photoScope(for item: MobileLadderInspectionItem) -> LocalPhotoScope {
        LocalPhotoScope(
            workflow: .mobileLadder, ownerID: draft.localDraftID, rowID: item.id,
            displayTitle: String(localized: "mobileLadder.photos.title"),
            displaySubtitle: item.title
        )
    }

    func disassembledPhotoScope() -> LocalPhotoScope {
        LocalPhotoScope(
            workflow: .mobileLadder,
            ownerID: draft.localDraftID,
            rowID: MobileLadderDraftPayload.disassembledStatusRowID,
            displayTitle: String(localized: "mobileLadder.photos.title"),
            displaySubtitle: String(localized: "mobileLadder.field.disassembled")
        )
    }

    func remainingPhotoCapacity(excluding itemID: String) -> Int {
        let otherCount = draft.photoAttachments.filter { $0.inspectionItemID != itemID }.count
        return max(0, 20 - otherCount)
    }

    func photoCount(for itemID: String) -> Int {
        draft.photoAttachments.filter { $0.inspectionItemID == itemID }.count
    }

    func refreshPhotos() {
        synchronizePhotoAttachments()
    }

    /// Mirrors the legacy Demontiert confirmation: a status transition clears
    /// the header/position values and all local documentation before changing
    /// which controls a technician may use.
    func confirmDisassembledChange(to isDisassembled: Bool) async -> Bool {
        guard !isSaving, !isReadOnly else { return false }
        isSaving = true
        defer { isSaving = false }

        let collections = offlineWorkStore.photoCollectionItems.compactMap { item -> PhotoCollectionDraftPayload? in
            guard let collection = item.payload.photoCollection,
                  collection.scope.workflow == .mobileLadder,
                  collection.scope.ownerID == draft.localDraftID else { return nil }
            return collection
        }
        let photoIDs = Set(
            draft.photoAttachments.map(\.localAttachmentID)
                + collections.flatMap { $0.attachments.map(\.localAttachmentID) }
        )

        do {
            for collection in collections {
                _ = try await offlineWorkStore.savePhotoCollection(
                    scope: collection.scope,
                    attachments: []
                )
            }
        } catch {
            feedback = .failed(error.localizedDescription)
            return false
        }

        for id in photoIDs {
            try? await photoStore.delete(id: id)
        }

        draft.isDisassembled = isDisassembled
        draft.disassembledComment = nil
        for index in draft.inspectionItems.indices {
            draft.inspectionItems[index].result = nil
            draft.inspectionItems[index].action = nil
            draft.inspectionItems[index].comment = ""
        }
        draft.photoAttachments = []
        return true
    }

    func saveTemporarily() async -> Bool {
        await save(status: .draft, successFeedback: nil)
    }

    func close() async -> Bool {
        guard !isReadOnly else { return false }
        setRungCount(draft.rungCount)
        synchronizePhotoAttachments()
        guard isReadyToClose else {
            feedback = .validation
            return false
        }
        if !isDemo, draft.legacyIdentifiers == nil {
            draft.legacyIdentifiers = MobileLadderIdentifierFactory.make()
        }
        // Keep the close marker in the local payload, as notification reviews
        // do, so reopening the item reliably restores its read-only state.
        let previousClosedState = draft.isClosedLocally
        draft.isClosedLocally = true
        let didSave = await save(
            status: .pendingSynchronization,
            successFeedback: .queued,
            allowsClosedPayload: true
        )
        if !didSave { draft.isClosedLocally = previousClosedState }
        return didSave
    }

    private var selectedContext: MobileLadderCreationContext? {
        guard let selectedBusinessEntity, let selectedBuilding, let selectedTrade else { return nil }
        return contexts.first {
            $0.businessEntity == selectedBusinessEntity && $0.building == selectedBuilding && $0.trade == selectedTrade
        }
    }

    private var requiredValues: [String] {
        [draft.material, draft.constructionType, draft.manufacturer, draft.rungCount,
         draft.clientCompany, draft.room, draft.designation]
    }

    private func applyInspectionTemplate(_ template: MobileLadderLegacyTemplate) {
        let previous = Dictionary(uniqueKeysWithValues: draft.inspectionItems.map { ($0.id, $0) })
        draft.inspectionItems = template.inspectionItems.enumerated().map { index, definition in
            var item = MobileLadderInspectionItem(definition: definition, number: index + 1)
            if let saved = previous[item.id] {
                item.result = saved.result
                item.action = saved.action
                item.comment = saved.comment
            }
            return item
        }
    }

    private func applyTemplateCatalog(_ template: MobileLadderLegacyTemplate) {
        let mappings: [(MobileLadderCatalogField, String)] = [
            (.material, "TFMMOBLEITER_WERKSTOFF"), (.constructionType, "TFMMOBLEITER_BAUART"),
            (.manufacturer, "TFMMOBLEITER_HERSTELLER"), (.clientCompany, "TFMMOBLEITER_GESELLSCHAFT")
        ]
        for (field, name) in mappings {
            let values = template.characteristics.first {
                $0.name.caseInsensitiveCompare(name) == .orderedSame
            }?.values.map { $0.title.isEmpty ? $0.value : $0.title } ?? []
            if !values.isEmpty { catalog.options[field] = values }
        }
    }

    private func synchronizePhotoAttachments() {
        let existingByLocalID = Dictionary(uniqueKeysWithValues: draft.photoAttachments.map { ($0.localAttachmentID, $0) })
        var updated: [MobileLadderPhotoAttachment] = []
        for item in offlineWorkStore.photoCollectionItems {
            guard let collection = item.payload.photoCollection else { continue }
            guard collection.scope.workflow == .mobileLadder else { continue }
            guard collection.scope.ownerID == draft.localDraftID else { continue }
            guard let rowID = collection.scope.rowID else { continue }
            if rowID == MobileLadderDraftPayload.disassembledStatusRowID {
                let formCode = draft.context?.legacyContext.template.formCode ?? "TFM5"
                for attachment in collection.attachments {
                    let documentID = existingByLocalID[attachment.localAttachmentID]?.sapDocumentID
                        ?? UUID().uuidString.uppercased()
                    updated.append(MobileLadderPhotoAttachment(
                        localAttachmentID: attachment.localAttachmentID,
                        inspectionItemID: rowID,
                        sapElementID: "\(formCode)-0000-9B",
                        capturedAt: attachment.capturedAt,
                        sapDocumentID: documentID
                    ))
                }
                continue
            }
            guard let inspection = draft.inspectionItems.first(where: { candidate in
                candidate.id == rowID
            }) else { continue }
            for attachment in collection.attachments {
                let documentID = existingByLocalID[attachment.localAttachmentID]?.sapDocumentID
                    ?? UUID().uuidString.uppercased()
                updated.append(MobileLadderPhotoAttachment(
                    localAttachmentID: attachment.localAttachmentID,
                    inspectionItemID: rowID,
                    sapElementID: inspection.commentElementID,
                    capturedAt: attachment.capturedAt,
                    sapDocumentID: documentID
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
        setRungCount(draft.rungCount)
        synchronizePhotoAttachments()
        do {
            let item = try await offlineWorkStore.saveMobileLadder(
                id: workItemID, payload: draft, status: status
            )
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
