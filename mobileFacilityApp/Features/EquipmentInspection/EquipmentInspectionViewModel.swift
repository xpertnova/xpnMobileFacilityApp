import Foundation
import Observation

enum ElevatorInspectionFeedback: Identifiable {
    case savedLocally
    case closedLocally
    case incomplete
    case saveFailed
    case photoFailed
    case photoLimitReached
    case cameraUnavailable
    case cameraPermissionDenied
    /// The chosen I2 notifications were stored with the closed inspection.
    case i2NotificationsQueued

    var id: String { String(describing: self) }
}

enum ElevatorAssetDataState: Equatable {
    case loading
    case ready
    case unavailable
}

/// State and business rules of every shared equipment inspection (TFM2
/// Aufzugskontrolle, TFM4 Steigleitern, TFM6 Feststellanlage, TFM8 Dachanlagen). Everything that differs per form code
/// comes from `form`; see `EquipmentInspectionForm`.
@MainActor
@Observable
final class EquipmentInspectionViewModel {
    static let maximumPhotoCount = 20

    let detail: SAPNotificationDetail
    let form: EquipmentInspectionForm
    let offlineWorkStore: OfflineWorkStore
    let photoStore: any PhotoAttachmentStore
    let sapDataStore: SAPDataStore?
    let elevatorAssetDataProvider: any ElevatorAssetDataProviding

    private(set) var items: [ElevatorInspectionItem] = []
    var performedOn = Date.now
    var results: [String: String] = [:]
    var actions: [String: String] = [:]
    var materials: [String: Bool] = [:]
    var comments: [String: String] = [:]
    private(set) var photoAttachments: [NotificationPhotoAttachment] = []
    private(set) var photoData: [String: Data] = [:]
    private(set) var isSaving = false
    private(set) var isLoading = true
    private(set) var isClosedLocally = false
    private(set) var elevatorAssetDataState: ElevatorAssetDataState = .loading
    private(set) var elevatorAssetCharacteristics: [ElevatorAssetCharacteristic] = []
    private(set) var elevatorAssetValues: [String: String] = [:]
    /// Class description (`TXTBZ`) of the loaded characteristics.
    private(set) var masterDataClassTitle = ""
    /// Header value per characteristic (`ATNAM`) in the transport format of
    /// its control; see `EquipmentMasterDataRules`.
    private(set) var masterDataValues: [String: String] = [:]
    /// `Vorschlag` text per characteristic that selects "Pflege durch Admin".
    private(set) var masterDataProposals: [String: String] = [:]
    /// Characteristics that failed `validateMasterData` on the last close.
    private(set) var masterDataValidationErrors: Set<String> = []
    /// Characteristic whose proposal editor should be shown.
    var proposalCharacteristicID: String?
    private var originalMasterDataValues: [String: String] = [:]
    private var masterRecord: EquipmentMasterRecord?
    /// `HeaderFormBuilder._isEditable` for the loaded record.
    private(set) var isMasterDataRecordEditable = false
    var statusDecision: ElevatorInspectionStatusDecision?
    var feedback: ElevatorInspectionFeedback?

    var isStatusDecisionPresented = false
    /// Shown when closing needs a plain yes/no confirmation, which is every
    /// case except a defective inspection — that one asks for a status
    /// instead.
    var isCloseConfirmationPresented = false
    /// The defect dialog shown after closing, for users with I2 permission.
    let i2Selection = I2DefectSelection()
    /// I2 notifications SAP already holds for the inspected object.
    private(set) var existingI2Notifications: [SAPI2NotificationSummary] = []
    var validationErrors: Set<String> = []

    /// Header-level "Außer Betrieb" status.
    ///
    /// `BaseFormController.buildDefaultElements` builds this control for every
    /// form except TFM1, TFM3, TFM8, TFM9 and TFMQ, so TFM2, TFM4 and TFM6
    /// carry it and TFM8 never does (`form.supportsOutOfService`).
    /// It is a header property, not a checklist row: the flag posts as
    /// `<form>-0000-1` and its comment as `<form>-0000-9B`.
    private(set) var isOutOfService = false
    var outOfServiceComment = ""
    var outOfServiceTransition: InspectionOutOfServiceTransition?

    private var originalAttachmentIDs = Set<String>()
    private var removedOriginalAttachmentIDs = Set<String>()
    private var persistedDraft: ElevatorInspectionDraftPayload?
    private var outgoingProcessID: String?
    private var userProfile: SAPUserProfile?

    init(
        detail: SAPNotificationDetail,
        form: EquipmentInspectionForm? = nil,
        offlineWorkStore: OfflineWorkStore,
        photoStore: any PhotoAttachmentStore,
        sapDataStore: SAPDataStore? = nil,
        elevatorAssetDataProvider: any ElevatorAssetDataProviding = UnavailableElevatorAssetDataProvider()
    ) {
        self.detail = detail
        self.form = form ?? detail.equipmentInspectionForm ?? .elevator
        self.offlineWorkStore = offlineWorkStore
        self.photoStore = photoStore
        self.sapDataStore = sapDataStore
        self.elevatorAssetDataProvider = elevatorAssetDataProvider
        self.items = ElevatorInspectionDecoder.decodeItems(from: detail.summary.rawPayloadJSON)
    }

    /// Row identity of the header status, used for its photo scope.
    var outOfServiceRowID: String { "\(form.formCode)-0000" }
    /// `edata.select.getElementId(<form>, "0000", "1")`.
    var outOfServiceValueElementID: String { "\(form.formCode)-0000-1" }
    /// `edata.select.getNoteIconId(<form>, "0000")`.
    var outOfServiceCommentElementID: String { "\(form.formCode)-0000-9B" }

    /// The form cannot be inspected because its class characteristics are
    /// missing — the legacy `showInvalidData` for every form except TFM2.
    var isMasterDataMissing: Bool {
        form.requiresMasterData && elevatorAssetDataState == .unavailable
    }

    var isEditingDisabled: Bool {
        isLoading || isClosedLocally || isMasterDataMissing
    }

    /// The checklist positions are locked while the form is out of service —
    /// the legacy client binds them to `posTable>/posElementBlocked`, which
    /// `setValues4AnwStatus` sets from the status.
    var arePositionsEditable: Bool {
        !isEditingDisabled && !isOutOfService
    }

    /// The header accepts input: the record's equipment type is maintainable
    /// (`_isEditable`) and the form itself can be edited.
    var isMasterDataEditable: Bool {
        !isEditingDisabled && isMasterDataRecordEditable
    }

    var isOutOfServiceCommentMissing: Bool {
        guard isOutOfService else { return false }
        return !InspectionFormRules.outOfServiceIssues(comment: outOfServiceComment).isEmpty
    }

    var hasMaterialColumn: Bool {
        form.supportsMaterial && items.contains { $0.hasMaterial }
    }

    var isAllGoodAvailable: Bool {
        let resultItems = items.filter(\.requiresResult)
        return !isOutOfService && !resultItems.isEmpty && resultItems.allSatisfy { item in
            item.resultOptions.contains { $0.code == "1" }
        }
    }

    var isChecklistValid: Bool {
        // `HeaderFormBuilder.validateFormValues` skips every position while
        // the status is set and validates only its comment.
        if isOutOfService {
            return !isOutOfServiceCommentMissing
        }
        return !items.isEmpty && invalidItemIDs.isEmpty
    }

    var hasDefect: Bool {
        guard !isOutOfService else { return false }
        return _hasPositionDefect
    }

    private var _hasPositionDefect: Bool {
        items.contains { item in
            let res = results[item.id] ?? ""
            let act = actions[item.id]
            return ElevatorInspectionLogic.isDefect(resultCode: res, actionCode: act)
        }
    }

    var deficientItems: [ElevatorInspectionItem] {
        guard !isOutOfService else { return [] }
        return items.filter { item in
            let res = results[item.id] ?? ""
            let act = actions[item.id]
            return ElevatorInspectionLogic.isDefect(resultCode: res, actionCode: act)
        }
    }

    /// Report title: the class description, like `buildPDF` in both legacy
    /// controllers, or the form's German name when the class has none or the
    /// form names itself (`reportTitleIgnoresClassDescription`).
    var reportTitle: String {
        if form.reportTitleIgnoresClassDescription { return form.reportTitleFallback }
        return masterDataClassTitle.isEmpty ? form.reportTitleFallback : masterDataClassTitle
    }

    var canCreateI2Defects: Bool {
        userProfile?.canCreateI2 ?? false
    }

    /// The deficient positions as rows of the I2 defect dialog
    /// (`HeaderFormBuilder.setValue4Process`).
    var i2Candidates: [I2DefectCandidate] {
        let positions = deficientItems
        guard !positions.isEmpty else { return [] }
        let planRows = I2NotificationRules.planRows(rawPayloadJSON: detail.summary.rawPayloadJSON)
        return positions.map { item in
            let resultCode = results[item.id] ?? ""
            let actionCode = actions[item.id] ?? ""
            let header = I2NotificationRules.headerText(
                operation: item.vornr,
                planRows: planRows,
                groupTitle: item.groupTitle
            )
            return I2DefectCandidate(
                id: item.id,
                number: item.positionNumber,
                title: item.title,
                resultCode: resultCode,
                resultText: item.resultOptions.first { $0.code == resultCode }?.text ?? "",
                actionCode: actionCode,
                actionText: item.actionOptions.first { $0.code == actionCode }?.text ?? "",
                note: I2NotificationRules.note(comment: comments[item.id, default: ""], headerText: header),
                noteElementID: item.commentElementID
            )
        }
    }

    func attachments(for checklistItemID: String) -> [NotificationPhotoAttachment] {
        photoAttachments.filter { $0.checklistItemID == checklistItemID }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        await discardStagedPhotos()
        await offlineWorkStore.load()

        if let store = sapDataStore {
            self.userProfile = await store.loadUserProfile()
            existingI2Notifications = await store.loadI2Notifications(for: detail)
        }

        await reloadElevatorAssetData()

        guard let draft = offlineWorkStore.elevatorInspection(notificationID: detail.summary.id) else {
            return
        }

        persistedDraft = draft
        restoreMasterData(from: draft.masterData)
        performedOn = draft.performedOn
        outgoingProcessID = draft.outgoingProcessID
        isClosedLocally = draft.isClosedLocally
        photoAttachments = draft.photoAttachments
        originalAttachmentIDs = Set(draft.photoAttachments.map(\.localAttachmentID))
        removedOriginalAttachmentIDs.removeAll()
        photoData.removeAll()

        for attachment in draft.photoAttachments {
            if let data = try? await photoStore.loadJPEG(id: attachment.localAttachmentID) {
                photoData[attachment.localAttachmentID] = data
            }
        }

        // Restore checklist values
        for item in items {
            if let val = draft.elementValues[item.resultElementID] {
                results[item.id] = val
            }
            if let actID = item.actionElementID, let actVal = draft.elementValues[actID] {
                actions[item.id] = actVal
            }
            if let matID = item.materialElementID, let matVal = draft.materialFlags[matID] {
                materials[item.id] = matVal
            } else if let matVal = draft.materialFlags[item.id] {
                materials[item.id] = matVal
            }
            if let commentVal = draft.comments[item.commentElementID] {
                comments[item.id] = commentVal
            } else if let commentVal = draft.comments[item.id] {
                comments[item.id] = commentVal
            }
        }

        isOutOfService = form.supportsOutOfService && (draft.isOutOfOperation ?? false)
        outOfServiceComment = isOutOfService ? draft.outOfOperationComment ?? "" : ""

        if draft.closingSystemStatus == "MIAR" {
            statusDecision = .leaveOpen
        } else if draft.closingSystemStatus == "MMAB" {
            statusDecision = .close
        }
    }

    func reloadElevatorAssetData() async {
        elevatorAssetDataState = .loading
        do {
            let assetData = try await elevatorAssetDataProvider.loadElevatorAssetData(for: detail.summary)
            elevatorAssetCharacteristics = assetData.characteristics
            elevatorAssetValues = assetData.values
            masterDataClassTitle = assetData.classTitle
            masterRecord = assetData.masterRecord
            isMasterDataRecordEditable = assetData.isEditable
            originalMasterDataValues = EquipmentMasterDataRules.initialValues(for: assetData)
            masterDataValues = originalMasterDataValues
            restoreMasterData(from: persistedDraft?.masterData)
            elevatorAssetDataState = assetData.characteristics.isEmpty ? .unavailable : .ready
        } catch is CancellationError {
            return
        } catch {
            elevatorAssetCharacteristics = []
            elevatorAssetValues = [:]
            masterDataClassTitle = ""
            masterRecord = nil
            isMasterDataRecordEditable = false
            originalMasterDataValues = [:]
            masterDataValues = [:]
            elevatorAssetDataState = .unavailable
        }
    }

    func elevatorAssetDisplayValue(for characteristic: ElevatorAssetCharacteristic) -> String {
        let value = EquipmentMasterDataRules.displayValue(
            for: characteristic,
            value: masterDataValues[characteristic.name] ?? ""
        )
        return value.isEmpty ? "—" : value
    }

    // MARK: - Class-characteristics header

    /// `_setIDNUMMERFalse` and `_isEditable` combined, independent of whether
    /// the form is currently locked.
    func isCharacteristicMaintainable(_ characteristic: ElevatorAssetCharacteristic) -> Bool {
        isMasterDataRecordEditable && !characteristic.isLockedIdentifier
    }

    func canEditCharacteristic(_ characteristic: ElevatorAssetCharacteristic) -> Bool {
        !isEditingDisabled && !isSaving && isCharacteristicMaintainable(characteristic)
    }

    func masterDataValue(for characteristic: ElevatorAssetCharacteristic) -> String {
        masterDataValues[characteristic.name] ?? ""
    }

    func masterDataSelection(for characteristic: ElevatorAssetCharacteristic) -> Set<String> {
        EquipmentMasterDataRules.selectedCodes(for: characteristic, value: masterDataValue(for: characteristic))
    }

    func masterDataDate(for characteristic: ElevatorAssetCharacteristic) -> Date? {
        EquipmentMasterDataRules.date(fromSAP: masterDataValue(for: characteristic))
    }

    func isMasterDataInvalid(_ characteristic: ElevatorAssetCharacteristic) -> Bool {
        masterDataValidationErrors.contains(characteristic.name)
    }

    /// Applies a dropdown pick the way `onChangeHeader` does. Picking
    /// "Pflege durch Admin" asks for a proposal; leaving it drops the proposal
    /// (`deleteVorschlag`). A multi-value field toggles the picked entry.
    func selectMasterDataOption(_ code: String, for characteristic: ElevatorAssetCharacteristic) {
        guard canEditCharacteristic(characteristic) else { return }
        let wasAdmin = EquipmentMasterDataRules.selectsAdmin(characteristic, value: masterDataValue(for: characteristic))

        let newValue: String
        if characteristic.control == .multiSelect {
            var codes = masterDataSelection(for: characteristic)
            if codes.contains(code) { codes.remove(code) } else { codes.insert(code) }
            newValue = characteristic.selectableOptions.map(\.code).filter(codes.contains).joined(separator: ";")
        } else {
            newValue = code
        }
        setMasterDataValue(newValue, for: characteristic)

        switch MasterDataProposalRules.selectionChange(
            wasAdmin: wasAdmin,
            isAdmin: EquipmentMasterDataRules.selectsAdmin(characteristic, value: newValue)
        ) {
        case .requestProposal: proposalCharacteristicID = characteristic.name
        case .removeProposal: masterDataProposals[characteristic.name] = nil
        case .none: break
        }
    }

    func setMasterDataText(_ text: String, for characteristic: ElevatorAssetCharacteristic) {
        guard canEditCharacteristic(characteristic) else { return }
        setMasterDataValue(EquipmentMasterDataRules.normalizedText(text, for: characteristic), for: characteristic)
    }

    func setMasterDataNumber(_ text: String, for characteristic: ElevatorAssetCharacteristic) {
        guard canEditCharacteristic(characteristic) else { return }
        setMasterDataValue(EquipmentMasterDataRules.normalizedNumber(text), for: characteristic)
    }

    func setMasterDataDate(_ date: Date?, for characteristic: ElevatorAssetCharacteristic) {
        guard canEditCharacteristic(characteristic) else { return }
        setMasterDataValue(date.map(EquipmentMasterDataRules.sapDate) ?? "", for: characteristic)
    }

    /// The proposal button is enabled while "Pflege durch Admin" is selected
    /// (`_setInitialMasterData`, `onChangeHeader`).
    func isProposalAvailable(for characteristic: ElevatorAssetCharacteristic) -> Bool {
        canEditCharacteristic(characteristic)
            && EquipmentMasterDataRules.selectsAdmin(characteristic, value: masterDataValue(for: characteristic))
    }

    func proposal(for characteristic: ElevatorAssetCharacteristic) -> String {
        masterDataProposals[characteristic.name] ?? ""
    }

    /// Proposals for the same field of the same object that are still on
    /// this device, newest first. The legacy `getVorschlag` reads the unsent
    /// `TO_T0211` rows for the element and `EQUNR`/`STRNO`.
    /// `insertVorschlag` writes a proposal as soon as the popover is saved, so
    /// this inspection's own proposal counts even before the draft is saved.
    func proposalHistory(for characteristic: ElevatorAssetCharacteristic) -> [String] {
        let equipmentID = detail.summary.equipmentID
        let locationID = detail.summary.functionalLocationID
        let others = offlineWorkStore.items
            .filter { $0.status != .synchronized }
            .sorted { $0.updatedAt > $1.updatedAt }
            .compactMap { item -> String? in
                guard let inspection = item.payload.elevatorInspection,
                      // This inspection's saved proposal is replaced by the
                      // one being edited, like `insertVorschlag` replaces its row.
                      inspection.notificationID != detail.summary.id,
                      let masterData = inspection.masterData,
                      equipmentID.isEmpty
                        ? masterData.functionalLocationID == locationID
                        : masterData.equipmentID == equipmentID
                else { return nil }
                return masterData.proposals[characteristic.name]
            }
        return MasterDataProposalRules.history([proposal(for: characteristic)] + others)
    }

    /// `onPressVorschlagSave`: a text stores the proposal, an empty text
    /// removes an existing one.
    func saveProposal(_ text: String, for characteristic: ElevatorAssetCharacteristic) {
        let value = MasterDataProposalRules.normalized(text)
        masterDataProposals[characteristic.name] = value.isEmpty ? nil : value
        if !value.isEmpty {
            masterDataValidationErrors.remove(characteristic.name)
        }
        proposalCharacteristicID = nil
    }

    private func setMasterDataValue(_ value: String, for characteristic: ElevatorAssetCharacteristic) {
        masterDataValues[characteristic.name] = value
        masterDataValidationErrors.remove(characteristic.name)
    }

    private func restoreMasterData(from draft: EquipmentMasterDataDraft?) {
        guard let draft else { return }
        for characteristic in elevatorAssetCharacteristics {
            if let value = draft.values[characteristic.name] {
                masterDataValues[characteristic.name] = value
            }
        }
        masterDataProposals = draft.proposals
    }

    /// `validateMasterData`, which `validateFormValues` runs whether or not
    /// the form is out of service.
    private func validateMasterData() -> Bool {
        guard elevatorAssetDataState == .ready else {
            masterDataValidationErrors.removeAll()
            return true
        }
        masterDataValidationErrors = EquipmentMasterDataRules.invalidCharacteristicIDs(
            characteristics: elevatorAssetCharacteristics,
            values: masterDataValues,
            proposals: masterDataProposals,
            isEditable: isCharacteristicMaintainable
        )
        return masterDataValidationErrors.isEmpty
    }

    /// Header state for the offline draft. On a closed inspection it also
    /// carries the rewritten master record when the characteristics changed.
    private func masterDataDraft(closed: Bool) -> EquipmentMasterDataDraft? {
        guard elevatorAssetDataState == .ready else { return persistedDraft?.masterData }
        let characteristics = elevatorAssetCharacteristics
        let proposals = masterDataProposals.filter { name, value in
            guard !value.isEmpty, let characteristic = characteristics.first(where: { $0.name == name }) else {
                return false
            }
            return EquipmentMasterDataRules.selectsAdmin(characteristic, value: masterDataValues[name] ?? "")
        }
        let updatedPayload: String?
        if closed, isMasterDataRecordEditable, let masterRecord {
            updatedPayload = EquipmentMasterDataRules.updatedMasterPayloadJSON(
                record: masterRecord,
                characteristics: characteristics,
                original: originalMasterDataValues,
                current: masterDataValues,
                client: detail.summary.client
            )
        } else {
            updatedPayload = nil
        }
        let equipmentID = masterRecord?.equipmentID ?? detail.summary.equipmentID
        return EquipmentMasterDataDraft(
            values: masterDataValues,
            proposals: proposals,
            headerValues: characteristics.map {
                EquipmentMasterDataHeaderValue(
                    elementID: $0.name,
                    label: $0.title,
                    value: masterDataValues[$0.name] ?? ""
                )
            },
            equipmentID: equipmentID,
            functionalLocationID: masterRecord?.functionalLocationID
                ?? (equipmentID.isEmpty ? detail.summary.functionalLocationID : ""),
            updatedMasterPayloadJSON: updatedPayload
        )
    }

    func applyAllGood() {
        guard arePositionsEditable, isAllGoodAvailable else { return }
        for item in items where item.requiresResult {
            // Set only empty/unanswered result controls to "1"
            if results[item.id] == nil || results[item.id]?.isEmpty == true {
                results[item.id] = "1"
            }
        }
        validationErrors.removeAll()
    }

    func handleCloseTapped() {
        guard !isSaving, !isEditingDisabled else { return }

        let isMasterDataValid = validateMasterData()

        // An out-of-service form closes on its documented status alone; the
        // positions are cleared and are not validated
        // (`HeaderFormBuilder.validateFormValues`).
        if isOutOfService {
            guard !isOutOfServiceCommentMissing, isMasterDataValid else {
                feedback = .incomplete
                return
            }
            validationErrors.removeAll()
            isCloseConfirmationPresented = true
            return
        }

        // Validate
        let missing = invalidItemIDs

        if !missing.isEmpty || !isMasterDataValid {
            validationErrors = missing
            feedback = .incomplete
            return
        }

        validationErrors.removeAll()

        if hasDefect {
            isStatusDecisionPresented = true
        } else {
            isCloseConfirmationPresented = true
        }
    }

    /// Closes after the plain confirmation. An out-of-service form stays open
    /// for the follow-up (`MIAR`); a clean inspection closes (`MMAB`).
    func confirmClose() async {
        await save(closed: true, statusDecision: isOutOfService ? .leaveOpen : .close)
    }

    func confirmStatusDecision(_ decision: ElevatorInspectionStatusDecision) async {
        isStatusDecisionPresented = false
        statusDecision = decision
        await save(closed: true, statusDecision: decision)
    }

    /// Requests a change of the header status. Both directions are confirmed
    /// because either one discards documentation.
    func requestOutOfServiceChange() {
        guard form.supportsOutOfService, !isEditingDisabled, !isSaving else { return }
        outOfServiceTransition = isOutOfService ? .disable : .enable
    }

    /// Applies a confirmed status change.
    ///
    /// `onSelectOutofOrder` clears the `T0283` position values and calls
    /// `deleteDocsForVorgang`, so every result, action, material flag, comment
    /// and photo recorded so far is discarded in both directions.
    func confirmOutOfServiceChange(to isActive: Bool) async {
        outOfServiceTransition = nil
        guard form.supportsOutOfService, !isEditingDisabled, !isSaving else { return }

        isOutOfService = isActive
        results.removeAll()
        actions.removeAll()
        materials.removeAll()
        comments.removeAll()
        validationErrors.removeAll()
        outOfServiceComment = ""

        isSaving = true
        defer { isSaving = false }
        let discarded = photoAttachments
        do {
            try await persistStatusChange()
            photoAttachments = []
            photoData.removeAll()
            for attachment in discarded {
                try? await photoStore.delete(id: attachment.localAttachmentID)
            }
        } catch {
            feedback = .saveFailed
        }
    }

    /// Writes the cleared checklist and the new header status to the offline
    /// draft so a status change survives leaving the form without an explicit
    /// temporary save.
    private func persistStatusChange() async throws {
        var draft = persistedDraft ?? ElevatorInspectionDraftPayload(
            notificationID: detail.summary.id,
            performedOn: performedOn,
            notificationSnapshot: OfflineNotificationSnapshot(detail: detail),
            formCode: form.formCode
        )
        draft.performedOn = performedOn
        draft.elementValues = [:]
        draft.comments = [:]
        draft.materialFlags = [:]
        draft.photoAttachments = []
        draft.isOutOfOperation = isOutOfService
        draft.outOfOperationComment = isOutOfService ? outOfServiceComment : nil
        draft.masterData = masterDataDraft(closed: false)
        _ = try await offlineWorkStore.saveElevatorInspection(draft)
        persistedDraft = draft
        originalAttachmentIDs = []
        removedOriginalAttachmentIDs.removeAll()
    }

    @discardableResult
    func save(closed: Bool, statusDecision: ElevatorInspectionStatusDecision? = nil) async -> Bool {
        guard !isSaving, !isEditingDisabled else { return false }

        isSaving = true
        defer { isSaving = false }

        let processID = closed ? (outgoingProcessID ?? UUID().uuidString.uppercased()) : outgoingProcessID

        var elementValues: [String: String] = [:]
        var commentsMap: [String: String] = [:]
        var materialFlagsMap: [String: Bool] = [:]

        for item in items {
            if let res = results[item.id] {
                elementValues[item.resultElementID] = res
            }
            if let actID = item.actionElementID, let act = actions[item.id] {
                elementValues[actID] = act
            }
            if hasMaterialColumn, let matID = item.materialElementID, let mat = materials[item.id] {
                materialFlagsMap[matID] = mat
            }
            if let comment = comments[item.id], !comment.isEmpty {
                commentsMap[item.commentElementID] = comment
            }
        }

        let isDef = hasDefect
        let sysStatus: String
        if closed {
            if isOutOfService {
                // An out-of-service object stays open for the follow-up.
                sysStatus = ElevatorInspectionStatusDecision.leaveOpen.systemStatus
            } else if let statusDecision {
                sysStatus = statusDecision.systemStatus
            } else {
                sysStatus = isDef ? "MIAR" : "MMAB"
            }
        } else {
            sysStatus = persistedDraft?.closingSystemStatus ?? "MMAB"
        }

        let closingUSTXT = ElevatorInspectionLogic.updatedUserStatus(
            current: detail.summary.userStatus,
            hasDefect: isOutOfService || isDef
        )

        // Generate PDF report
        var pdfBytes: Data? = nil
        let payloadDict = extractPayloadDict()
        let city = payloadDict["CITY1_TO"] as? String ?? ""
        let street = payloadDict["STREET_TO"] as? String ?? ""
        let we = payloadDict["TPWEH"] as? String ?? ""
        let ge = payloadDict["TPGEB"] as? String ?? ""
        let weGe = "\(we)/ \(ge)"
        let placeText = payloadDict["PLTXT"] as? String ?? ""
        let eqktx = payloadDict["EQKTX"] as? String ?? ""
        let plant = payloadDict["IWERK"] as? String ?? ""
        let orgUnit = payloadDict["GEWRK"] as? String ?? ""

        let workerDisplayName = [userProfile?.firstName, userProfile?.name]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let pdfPayload = ElevatorInspectionPDFPayload(
            formTitle: reportTitle,
            masterDataTitle: form.reportMasterDataTitle,
            notificationID: detail.summary.id,
            notificationTitle: placeText.isEmpty ? detail.summary.title : placeText,
            functionalLocation: detail.summary.functionalLocationID,
            equipmentID: detail.summary.equipmentID.isEmpty ? nil : detail.summary.equipmentID,
            equipmentName: eqktx.isEmpty ? nil : eqktx,
            locationCity: city,
            locationStreet: street,
            weGe: weGe,
            workerName: workerDisplayName,
            workerID: userProfile?.personalNumber ?? "",
            company: userProfile?.company ?? "",
            orgUnit: orgUnit,
            plant: plant,
            performedAt: performedOn,
            items: items,
            results: results,
            actions: actions,
            materials: materials,
            notes: comments,
            hasMaterialColumn: hasMaterialColumn,
            assetCharacteristics: elevatorAssetCharacteristics,
            assetValues: masterDataValues,
            outOfOperationComment: isOutOfService ? outOfServiceComment : nil
        )

        if let artifact = try? ElevatorInspectionPDFRenderer.render(pdfPayload) {
            pdfBytes = artifact.data
        }

        let draft = ElevatorInspectionDraftPayload(
            notificationID: detail.summary.id,
            performedOn: performedOn,
            elementValues: elementValues,
            comments: commentsMap,
            materialFlags: materialFlagsMap,
            photoAttachments: photoAttachments,
            pdfDocumentID: persistedDraft?.pdfDocumentID ?? UUID().uuidString.uppercased(),
            pdfBytes: pdfBytes,
            outgoingProcessID: processID,
            isClosedLocally: closed,
            closingSystemStatus: sysStatus,
            closingUserStatus: closingUSTXT,
            statusNumber: isOutOfService || isDef ? "2" : "1",
            isOutOfOperation: isOutOfService,
            outOfOperationComment: isOutOfService ? outOfServiceComment : nil,
            notificationSnapshot: OfflineNotificationSnapshot(detail: detail),
            formCode: form.formCode,
            masterData: masterDataDraft(closed: closed)
        )

        do {
            _ = try await offlineWorkStore.saveElevatorInspection(draft)
            for id in removedOriginalAttachmentIDs {
                try? await photoStore.delete(id: id)
            }
            originalAttachmentIDs = Set(photoAttachments.map(\.localAttachmentID))
            removedOriginalAttachmentIDs.removeAll()
            outgoingProcessID = processID
            isClosedLocally = closed
            persistedDraft = draft
            // `_afterSetMeldung` offers the deficient positions for I2
            // notifications instead of finishing the form.
            if closed {
                SAPSynchronizationDiagnostics.logI2(
                    "form closed: user may create I2 \(canCreateI2Defects), " +
                        "\(i2Candidates.count) defective position(s) offered"
                )
            }
            let offersI2 = closed && canCreateI2Defects && i2Selection.present(i2Candidates)
            if !offersI2 {
                feedback = closed ? .closedLocally : .savedLocally
            }
            return true
        } catch {
            feedback = .saveFailed
            return false
        }
    }

    /// Stores the notifications chosen in the defect dialog with the closed
    /// inspection. Returns `false` when nothing was chosen, so the form can be
    /// left straight away as `onDefectPosItemAccept` does.
    func acceptI2Selection() async -> Bool {
        let requests = i2Selection.accept()
        SAPSynchronizationDiagnostics.logI2(
            "dialog accepted with \(requests.count) request(s), closed draft present: " +
                "\(persistedDraft?.isClosedLocally == true)"
        )
        guard !requests.isEmpty, var draft = persistedDraft, draft.isClosedLocally else { return false }
        isSaving = true
        defer { isSaving = false }
        draft.i2Requests = requests
        do {
            _ = try await offlineWorkStore.saveElevatorInspection(draft)
            SAPSynchronizationDiagnostics.logI2("stored \(requests.count) request(s) with the closed form")
            persistedDraft = draft
            feedback = .i2NotificationsQueued
        } catch {
            feedback = .saveFailed
        }
        return true
    }

    func cancelI2Selection() {
        i2Selection.cancel()
    }

    func addPhoto(jpegData: Data, to item: ElevatorInspectionItem) async {
        await addPhoto(jpegData: jpegData, checklistItemID: item.id, sapElementID: item.commentElementID)
    }

    private var invalidItemIDs: Set<String> {
        Set(items.compactMap { item in
            let issues = InspectionFormRules.issues(
                resultCode: results[item.id],
                actionCode: actions[item.id],
                isMaterialSelected: materials[item.id] ?? false,
                comment: comments[item.id, default: ""],
                requiresResult: item.requiresResult,
                requiresPhoto: item.requiresPhoto,
                requiresPhotoAndComment: item.requiresPhotoAndComment,
                photoCount: attachments(for: item.id).count,
                variant: form.variant
            )
            return issues.isEmpty ? nil : item.id
        })
    }

    /// Documents the header status. The legacy camera icon on the out-of-order
    /// box is bound to the same `T0282` element as its note.
    func addOutOfServicePhoto(jpegData: Data) async {
        guard isOutOfService else { return }
        await addPhoto(
            jpegData: jpegData,
            checklistItemID: outOfServiceRowID,
            sapElementID: outOfServiceCommentElementID
        )
    }

    private func addPhoto(jpegData: Data, checklistItemID: String, sapElementID: String) async {
        guard !isEditingDisabled, !isSaving else { return }
        guard photoAttachments.count < Self.maximumPhotoCount else {
            feedback = .photoLimitReached
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let localID = try await photoStore.saveJPEG(jpegData)
            let attachment = NotificationPhotoAttachment(
                localAttachmentID: localID,
                checklistItemID: checklistItemID,
                sapElementID: sapElementID,
                capturedAt: .now,
                sapDocumentID: UUID().uuidString.uppercased()
            )
            let updated = photoAttachments + [attachment]
            do {
                try await persistPhotoChanges(updated)
            } catch {
                try? await photoStore.delete(id: localID)
                feedback = .photoFailed
                return
            }
            photoAttachments = updated
            photoData[localID] = jpegData
        } catch {
            feedback = .photoFailed
        }
    }

    func removePhoto(_ attachment: NotificationPhotoAttachment) async {
        guard !isEditingDisabled, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        let updated = photoAttachments.filter { $0.id != attachment.id }
        do {
            try await persistPhotoChanges(updated)
            photoAttachments = updated
            photoData[attachment.localAttachmentID] = nil
            try? await photoStore.delete(id: attachment.localAttachmentID)
            originalAttachmentIDs.remove(attachment.localAttachmentID)
            removedOriginalAttachmentIDs.remove(attachment.localAttachmentID)
        } catch {
            feedback = .photoFailed
        }
    }

    func updatePhoto(id: String, name: String, description: String) async {
        guard !isEditingDisabled, !isSaving,
              photoAttachments.contains(where: { $0.id == id }) else { return }
        isSaving = true
        defer { isSaving = false }

        let updated = photoAttachments.map {
            $0.id == id ? $0.updatingMetadata(name: name, description: description) : $0
        }
        do {
            try await persistPhotoChanges(updated)
            photoAttachments = updated
        } catch {
            feedback = .photoFailed
        }
    }

    func cancel() async {
        await discardStagedPhotos()
    }

    private func discardStagedPhotos() async {
        let currentIDs = Set(photoAttachments.map(\.localAttachmentID))
        for id in currentIDs.subtracting(originalAttachmentIDs) {
            try? await photoStore.delete(id: id)
        }
    }

    private func persistPhotoChanges(_ attachments: [NotificationPhotoAttachment]) async throws {
        var draft = persistedDraft ?? ElevatorInspectionDraftPayload(
            notificationID: detail.summary.id,
            performedOn: performedOn,
            elementValues: [:],
            comments: [:],
            materialFlags: [:],
            photoAttachments: [],
            outgoingProcessID: nil,
            isClosedLocally: false,
            notificationSnapshot: OfflineNotificationSnapshot(detail: detail),
            formCode: form.formCode
        )
        draft.photoAttachments = attachments
        _ = try await offlineWorkStore.saveElevatorInspection(draft)
        persistedDraft = draft
        originalAttachmentIDs = Set(attachments.map(\.localAttachmentID))
        removedOriginalAttachmentIDs.removeAll()
    }

    private func extractPayloadDict() -> [String: Any] {
        guard let data = detail.summary.rawPayloadJSON.data(using: .utf8),
              var dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return [:]
        }
        if dict["T_PLPOD"] == nil,
           let feldwert = dict["FELDWERT"] as? String,
           let decoded = SAPLegacyDataExchangeCodec.cachedNotificationPayload(fromFeldwert: feldwert) {
            dict.merge(decoded) { _, v in v }
        }
        return dict
    }
}
