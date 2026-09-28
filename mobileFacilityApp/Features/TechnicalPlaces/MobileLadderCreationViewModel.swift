import Foundation
import Observation

@MainActor
@Observable
final class MobileLadderCreationViewModel {
    enum State: Equatable { case loading, ready, unavailable }
    enum Feedback: Identifiable {
        case validation, saved, queued, failed(String)

        var id: String {
            switch self {
            case .validation: "validation"
            case .saved: "saved"
            case .queued: "queued"
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
    /// Catalog field whose proposal editor is open.
    var proposalField: MobileLadderCatalogField?
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
            && !MobileLadderCatalogField.allCases.contains(where: isMissingProposal)
            && (Int(draft.rungCount.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0) > 0
            && !draft.inspectionItems.isEmpty
            // Legacy TFM5 clears and disables inspection rows while the
            // header is marked Demontiert, so those rows are not required in
            // that explicit state.
            && (draft.isDisassembled || draft.inspectionItems.allSatisfy { $0.result != nil })
            && draft.photoAttachments.count <= 20
            && !isSaving
    }

    /// `anchor` is the building the technician opened the form from. It only
    /// preselects the address of a new draft — a saved one keeps the context
    /// it was saved with.
    func load(preselecting anchor: TechnicalPlaceCreationAnchor? = nil) async {
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
                // A reload (the form's task can restart) never overrides a
                // choice the technician has already made.
                if let anchor, selectedBusinessEntity == nil { applyAnchor(anchor) }
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

    /// Fills the pickers from the anchored place as far as this landscape has
    /// a ladder context for it: the business entity, then the building, then
    /// the trade when only one is left. Anything ambiguous stays with the
    /// technician.
    private func applyAnchor(_ anchor: TechnicalPlaceCreationAnchor) {
        let entityMatches = contexts.filter {
            anchor.matches(countryCode: $0.legacyContext.country, businessEntity: $0.legacyContext.businessEntity)
        }
        let entities = Set(entityMatches.map(\.businessEntity))
        guard entities.count == 1, let entity = entities.first else { return }
        selectedBusinessEntity = entity

        let buildingMatches = entityMatches.filter {
            anchor.matches(
                countryCode: $0.legacyContext.country,
                businessEntity: $0.legacyContext.businessEntity,
                building: $0.legacyContext.building
            )
        }
        let matchedBuildings = Set(buildingMatches.map(\.building))
        let entityBuildings = Set(entityMatches.map(\.building))
        if matchedBuildings.count == 1 {
            selectedBuilding = matchedBuildings.first
        } else if anchor.buildingCode.isEmpty, entityBuildings.count == 1 {
            // A place above building level: a single building is still no
            // choice. A place in a building without a context of its own
            // never falls back to another building.
            selectedBuilding = entityBuildings.first
        } else {
            return
        }

        let trades = Set(entityMatches.filter { $0.building == selectedBuilding }.map(\.trade))
        guard trades.count == 1, let trade = trades.first else { return }
        selectedTrade = trade
        useSelectedAddress()
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
            let companies = catalog.options(for: .clientCompany).filter { !MasterDataProposalRules.isAdmin(text: $0) }
            if companies.count == 1, let first = companies.first {
                draft.clientCompany = first
            }
        }
    }

    /// Value-list entries in legacy order: "Pflege durch Admin" first,
    /// "nicht bekannt" second.
    func options(for field: MobileLadderCatalogField) -> [String] {
        MasterDataProposalRules.ordered(catalog.options(for: field))
    }

    /// Applies a dropdown pick the way `onChangeHeader` does: picking
    /// "Pflege durch Admin" asks for a proposal, replacing it drops the
    /// proposal (`deleteVorschlag`).
    func setSelection(_ value: String, for field: MobileLadderCatalogField) {
        guard !isReadOnly else { return }
        let wasAdmin = draft.selectsAdmin(field)
        draft.setValue(value, for: field)
        switch MasterDataProposalRules.selectionChange(wasAdmin: wasAdmin, isAdmin: draft.selectsAdmin(field)) {
        case .requestProposal: proposalField = field
        case .removeProposal: draft.proposals?[field.characteristicName] = nil
        case .none: break
        }
    }

    /// The field's value list offers "Pflege durch Admin", so it carries the
    /// proposal button.
    func offersProposal(for field: MobileLadderCatalogField) -> Bool {
        options(for: field).contains { MasterDataProposalRules.isAdmin(text: $0) }
    }

    /// The proposal button is enabled while "Pflege durch Admin" is selected.
    func isProposalAvailable(for field: MobileLadderCatalogField) -> Bool {
        !isReadOnly && !isSaving && draft.selectsAdmin(field)
    }

    func isMissingProposal(_ field: MobileLadderCatalogField) -> Bool {
        MasterDataProposalRules.isMissingProposal(
            selectsAdmin: draft.selectsAdmin(field),
            proposal: draft.proposal(for: field)
        )
    }

    /// A new ladder gets a new equipment number, so the legacy `getVorschlag`
    /// (element plus `EQUNR`) only ever finds this ladder's own proposal.
    func proposalHistory(for field: MobileLadderCatalogField) -> [String] {
        MasterDataProposalRules.history([draft.proposal(for: field)])
    }

    /// `onPressVorschlagSave`: a text stores the proposal, an empty text
    /// removes it.
    func saveProposal(_ text: String, for field: MobileLadderCatalogField) {
        defer { proposalField = nil }
        guard !isReadOnly else { return }
        let proposal = MasterDataProposalRules.normalized(text)
        var proposals = draft.proposals ?? [:]
        proposals[field.characteristicName] = proposal.isEmpty ? nil : proposal
        draft.proposals = proposals
    }

    static let rungCountMaxDigits = 3

    /// Legacy `NbpmNumberInput` showed the characteristic's SAP unit (`MSEHI`)
    /// beside the value; TFM5 counts rungs in pieces ("ST").
    var rungCountUnit: String {
        (draft.context?.legacyContext.template.characteristics.first {
            $0.name.caseInsensitiveCompare("TFMMOBLEITER_ANZAHLSPROSSEN") == .orderedSame
        }?.unit ?? "").ifEmpty("ST")
    }

    /// Rung counts are numeric legacy values of at most three digits. Normalize
    /// input here as well as in the numeric keyboard field so pasted and
    /// reopened draft data cannot reintroduce text characters or longer values.
    func setRungCount(_ value: String) {
        guard !isReadOnly else { return }
        let digits = String(value.filter(\.isNumber).prefix(Self.rungCountMaxDigits))
        // `draft` is one observed property: skip unchanged writes so they do
        // not re-render the whole form.
        if draft.rungCount != digits {
            draft.rungCount = digits
        }
    }

    func markEverythingOkay() {
        guard !isReadOnly, !draft.isDisassembled else { return }
        for index in draft.inspectionItems.indices { draft.inspectionItems[index].result = .okay }
    }

    func photoScope(for item: MobileLadderInspectionItem) -> LocalPhotoScope {
        LocalPhotoScope(
            workflow: .mobileLadder, ownerID: draft.localDraftID, rowID: item.id,
            displayTitle: String(localized: "mobileLadder.photos.title", bundle: .appLanguage),
            displaySubtitle: item.title
        )
    }

    func disassembledPhotoScope() -> LocalPhotoScope {
        LocalPhotoScope(
            workflow: .mobileLadder,
            ownerID: draft.localDraftID,
            rowID: MobileLadderDraftPayload.disassembledStatusRowID,
            displayTitle: String(localized: "mobileLadder.photos.title", bundle: .appLanguage),
            displaySubtitle: String(localized: "mobileLadder.field.disassembled", bundle: .appLanguage)
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
        for field in MobileLadderCatalogField.allCases {
            let values = template.characteristics.first {
                $0.name.caseInsensitiveCompare(field.characteristicName) == .orderedSame
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
        draft.proposals = draft.outgoingProposals
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
