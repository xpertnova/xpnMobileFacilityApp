import Foundation
import Observation

@MainActor
@Observable
final class FirePermitViewModel {
    let source: SafetyFormSource
    var record: FirePermitRecord
    var hasAttemptedCompletion = false
    var isRenderingPDF = false
    var validationMessage: String?
    var pdfArtifact: BriefingPDFArtifact?
    var selectedBusinessEntityID: String?
    var selectedBuildingCode: String?

    init(source: SafetyFormSource) {
        self.source = source
        record = FirePermitRecord(source: source)
    }

    var businessEntities: [SafetyFormContext] {
        Dictionary(grouping: source.contexts, by: \.businessEntityID)
            .values.compactMap(\.first)
            .sorted { $0.businessEntityTitle < $1.businessEntityTitle }
    }

    var buildings: [SafetyFormContext] {
        Dictionary(grouping: source.contexts.filter { $0.businessEntityID == selectedBusinessEntityID }, by: \.buildingCode)
            .values.compactMap(\.first)
            .sorted { $0.buildingTitle < $1.buildingTitle }
    }

    var functionalLocations: [SafetyFormContext] {
        source.contexts.filter {
            $0.businessEntityID == selectedBusinessEntityID && $0.buildingCode == selectedBuildingCode
        }.sorted { $0.functionalLocationTitle < $1.functionalLocationTitle }
    }

    var firstValidationIssue: FirePermitValidationIssue? {
        let ordered: [FirePermitValidationIssue] = [
            .context, .coordinator, .partner, .executionRange, .workDescription, .instructedPerson
        ] + FirePermitSignatureSlot.allCases.flatMap { [.signerName($0), .signature($0)] }
        return ordered.first { validationIssues.contains($0) }
    }

    var validationIssues: Set<FirePermitValidationIssue> {
        var issues: Set<FirePermitValidationIssue> = []
        if record.context == nil { issues.insert(.context) }
        if record.coordinator.trimmed.isEmpty { issues.insert(.coordinator) }
        if record.instructedPerson.trimmed.isEmpty { issues.insert(.instructedPerson) }
        if record.partner == nil { issues.insert(.partner) }
        if record.workDescription.trimmed.isEmpty { issues.insert(.workDescription) }
        if record.executionEnd < record.executionStart { issues.insert(.executionRange) }
        for slot in FirePermitSignatureSlot.allCases {
            if signerName(for: slot).trimmed.isEmpty { issues.insert(.signerName(slot)) }
            if record.signatures[slot] == nil { issues.insert(.signature(slot)) }
        }
        return issues
    }

    func isInvalid(_ issue: FirePermitValidationIssue) -> Bool {
        hasAttemptedCompletion && validationIssues.contains(issue)
    }

    func selectBusinessEntity(_ id: String) {
        guard selectedBusinessEntityID != id else { return }
        selectedBusinessEntityID = id
        selectedBuildingCode = nil
        record.context = nil
        record.partner = nil
        record.partnerEmail = ""
    }

    func selectBuilding(_ code: String) {
        guard selectedBuildingCode != code else { return }
        selectedBuildingCode = code
        record.context = nil
    }

    func selectContext(_ context: SafetyFormContext) {
        selectedBusinessEntityID = context.businessEntityID
        selectedBuildingCode = context.buildingCode
        record.context = context
    }

    func selectPartner(_ partner: SAPBriefingPartner) {
        record.partner = partner
        record.partnerEmail = partner.email
    }

    func setInstructedPerson(_ value: String) { record.instructedPerson = String(value.prefix(29)) }
    func setWorkDescription(_ value: String) { record.workDescription = String(value.prefix(300)) }
    func setExecutionStart(_ value: Date) {
        record.executionStart = value
        if record.executionEnd < value { record.executionEnd = value }
    }
    func setDimension(_ value: String, keyPath: WritableKeyPath<FirePermitRecord, String>) {
        record[keyPath: keyPath] = String(value.filter(\.isNumber).prefix(3))
    }
    func setFireWatchDuration(_ value: String) {
        record.fireWatchDurationHours = String(value.filter(\.isNumber).prefix(2))
    }
    func setOther(_ isEnabled: Bool, text: WritableKeyPath<FirePermitRecord, String>) {
        if !isEnabled { record[keyPath: text] = "" }
    }

    func signerName(for slot: FirePermitSignatureSlot) -> String {
        switch slot {
        case .fireHazardMeasures: record.fireHazardPerformer
        case .extinguishingMedia: record.extinguishingPerformer
        case .fireAlarmSystem: record.fireAlarmPerformer
        case .explosionHazardMeasures: record.explosionPerformer
        case .permitIssuer: record.permitIssuerName
        case .contractor: record.contractorName
        case .onSiteWorker: record.onSiteWorkerName
        }
    }

    func updateSignerName(_ value: String, for slot: FirePermitSignatureSlot) {
        guard signerName(for: slot) != value else { return }
        var updatedRecord = record
        switch slot {
        case .fireHazardMeasures: updatedRecord.fireHazardPerformer = value
        case .extinguishingMedia: updatedRecord.extinguishingPerformer = value
        case .fireAlarmSystem: updatedRecord.fireAlarmPerformer = value
        case .explosionHazardMeasures: updatedRecord.explosionPerformer = value
        case .permitIssuer: updatedRecord.permitIssuerName = value
        case .contractor: updatedRecord.contractorName = value
        case .onSiteWorker: updatedRecord.onSiteWorkerName = value
        }
        updatedRecord.signatures[slot] = nil
        record = updatedRecord
    }

    func setSignature(_ data: Data?, for slot: FirePermitSignatureSlot) {
        var updatedRecord = record
        guard let data, !data.isEmpty else {
            updatedRecord.signatures[slot] = nil
            record = updatedRecord
            return
        }
        updatedRecord.signatures[slot] = SafetyFormSignature(
            signerName: signerName(for: slot),
            capturedAt: .now,
            pngData: data
        )
        record = updatedRecord
    }

    func complete() {
        guard !isRenderingPDF else { return }
        Task { @MainActor [weak self] in
            // Let the last PencilKit stroke be persisted by SwiftUI before
            // checking `record.signatures`.
            await Task.yield()
            self?.finishCompletion()
        }
    }

    private func finishCompletion() {
        guard !isRenderingPDF else { return }
        hasAttemptedCompletion = true
        guard validationIssues.isEmpty else {
            validationMessage = String(localized: "safetyForms.validation.message")
            return
        }
        guard !isRenderingPDF else { return }
        isRenderingPDF = true
        let snapshot = record
        Task {
            let artifact = await Task.detached(priority: .userInitiated) {
                try? LegacyFirePermitPDFRenderer().render(snapshot)
            }.value
            isRenderingPDF = false
            guard let artifact else {
                validationMessage = String(localized: "firePermit.pdf.failure.message")
                return
            }
            pdfArtifact = artifact
        }
    }
}

@MainActor
@Observable
final class ElectricalSafetyViewModel {
    let source: SafetyFormSource
    var draft: ElectricalSafetyDraftPayload
    var hasAttemptedCompletion = false
    var isSaving = false
    var validationMessage: String?
    var alertTitle = String(localized: "electricalSafety.form.title")
    var validationIssueToReveal: ElectricalSafetyValidationIssue?
    var pdfArtifact: BriefingPDFArtifact?
    var selectedBusinessEntityID: String?
    var selectedBuildingCode: String?
    private var savedWorkID: UUID?

    init(source: SafetyFormSource, existingDraft: OfflineWorkItem?) {
        self.source = source
        if let existingDraft, let payload = existingDraft.payload.electricalSafety {
            draft = payload
            savedWorkID = existingDraft.id
            selectedBusinessEntityID = payload.context?.businessEntityID
            selectedBuildingCode = payload.context?.buildingCode
        } else {
            draft = ElectricalSafetyDraftPayload(source: source)
        }
    }

    var businessEntities: [SafetyFormContext] {
        Dictionary(grouping: source.contexts, by: \.businessEntityID)
            .values.compactMap(\.first)
            .sorted { $0.businessEntityTitle < $1.businessEntityTitle }
    }

    var buildings: [SafetyFormContext] {
        Dictionary(grouping: source.contexts.filter { $0.businessEntityID == selectedBusinessEntityID }, by: \.buildingCode)
            .values.compactMap(\.first)
            .sorted { $0.buildingTitle < $1.buildingTitle }
    }

    var functionalLocations: [SafetyFormContext] {
        source.contexts.filter {
            $0.businessEntityID == selectedBusinessEntityID && $0.buildingCode == selectedBuildingCode
        }.sorted { $0.functionalLocationTitle < $1.functionalLocationTitle }
    }

    var firstValidationIssue: ElectricalSafetyValidationIssue? {
        let ordered: [ElectricalSafetyValidationIssue] = [
            .context, .coordinator, .partner, .executionRange, .workDescription, .instructedPerson,
            .systemResponsibleName, .workResponsibleName
        ] + ElectricalSafetySignatureSlot.allCases.map { .signature($0) }
        return ordered.first { validationIssues.contains($0) }
    }

    var validationIssues: Set<ElectricalSafetyValidationIssue> {
        var issues: Set<ElectricalSafetyValidationIssue> = []
        if draft.context == nil { issues.insert(.context) }
        if draft.coordinator.trimmed.isEmpty { issues.insert(.coordinator) }
        if draft.instructedPerson.trimmed.isEmpty { issues.insert(.instructedPerson) }
        if draft.partner == nil { issues.insert(.partner) }
        if draft.workDescription.trimmed.isEmpty { issues.insert(.workDescription) }
        if draft.executionEnd < draft.executionStart { issues.insert(.executionRange) }
        if draft.systemResponsible.name.trimmed.isEmpty { issues.insert(.systemResponsibleName) }
        if draft.workResponsible.name.trimmed.isEmpty { issues.insert(.workResponsibleName) }
        for slot in ElectricalSafetySignatureSlot.allCases where draft.signatures[slot] == nil {
            issues.insert(.signature(slot))
        }
        return issues
    }

    func isInvalid(_ issue: ElectricalSafetyValidationIssue) -> Bool {
        hasAttemptedCompletion && validationIssues.contains(issue)
    }

    func selectBusinessEntity(_ id: String) {
        guard selectedBusinessEntityID != id else { return }
        selectedBusinessEntityID = id
        selectedBuildingCode = nil
        draft.context = nil
        draft.partner = nil
        draft.partnerEmail = ""
    }

    func selectBuilding(_ code: String) {
        guard selectedBuildingCode != code else { return }
        selectedBuildingCode = code
        draft.context = nil
    }

    func selectContext(_ context: SafetyFormContext) {
        selectedBusinessEntityID = context.businessEntityID
        selectedBuildingCode = context.buildingCode
        draft.context = context
    }

    func selectPartner(_ partner: SAPBriefingPartner) {
        draft.partner = partner
        draft.partnerEmail = partner.email
    }

    func setInstructedPerson(_ value: String) { draft.instructedPerson = String(value.prefix(29)) }
    func setWorkDescription(_ value: String) { draft.workDescription = String(value.prefix(300)) }
    func setExecutionStart(_ value: Date) {
        draft.executionStart = value
        if draft.executionEnd < value { draft.executionEnd = value }
    }

    func updateSystemResponsibleName(_ value: String) {
        guard draft.systemResponsible.name != value else { return }
        draft.systemResponsible.name = value
        draft.signatures[.handoverSystemResponsible] = nil
        draft.signatures[.returnSystemResponsible] = nil
    }

    func updateWorkResponsibleName(_ value: String) {
        guard draft.workResponsible.name != value else { return }
        draft.workResponsible.name = value
        draft.signatures[.handoverWorkResponsible] = nil
        draft.signatures[.returnWorkResponsible] = nil
    }

    func signerName(for slot: ElectricalSafetySignatureSlot) -> String {
        switch slot {
        case .handoverSystemResponsible, .returnSystemResponsible: draft.systemResponsible.name
        case .handoverWorkResponsible, .returnWorkResponsible: draft.workResponsible.name
        }
    }

    func setSignature(_ data: Data?, for slot: ElectricalSafetySignatureSlot) {
        var updatedDraft = draft
        guard let data, !data.isEmpty else {
            updatedDraft.signatures[slot] = nil
            draft = updatedDraft
            return
        }
        updatedDraft.signatures[slot] = SafetyFormSignature(
            signerName: signerName(for: slot),
            capturedAt: .now,
            pngData: data
        )
        draft = updatedDraft
    }

    func saveDraft(using store: OfflineWorkStore) async -> Bool {
        await save(using: store, status: .draft, isCompletion: false)
    }

    func complete() async {
        // Let a signature field persist the final PencilKit stroke before
        // checking the draft for missing fields.
        await Task.yield()
        hasAttemptedCompletion = true
        guard validationIssues.isEmpty else {
            validationIssueToReveal = firstValidationIssue
            alertTitle = String(localized: "electricalSafety.form.title")
            validationMessage = String(localized: "safetyForms.validation.message")
            return
        }
        let snapshot = draft
        let artifact = await Task.detached(priority: .userInitiated) {
            try? LegacyElectricalSafetyPDFRenderer().render(snapshot)
        }.value
        guard let artifact else {
            alertTitle = String(localized: "electricalSafety.form.title")
            validationMessage = String(localized: "safetyForms.pdf.failure")
            return
        }
        pdfArtifact = artifact
    }

    func dismissAlert() {
        validationMessage = nil
        validationIssueToReveal = nil
    }

    func markPendingSynchronization(using store: OfflineWorkStore) async -> Bool {
        await save(using: store, status: .pendingSynchronization, isCompletion: true)
    }

    private func save(
        using store: OfflineWorkStore,
        status: OfflineWorkStatus,
        isCompletion: Bool
    ) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        var payload = draft
        payload.completedAt = isCompletion ? .now : nil
        do {
            let item = try await store.saveElectricalSafety(
                id: savedWorkID,
                payload: payload,
                status: status
            )
            savedWorkID = item.id
            draft = payload
            if !isCompletion {
                alertTitle = String(localized: "electricalSafety.temporarySaved.title")
                validationMessage = String(localized: "electricalSafety.temporarySaved.message")
            }
            return true
        } catch {
            alertTitle = String(localized: "electricalSafety.saveFailed.title")
            validationMessage = String(localized: "electricalSafety.saveFailed.message")
            return false
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
