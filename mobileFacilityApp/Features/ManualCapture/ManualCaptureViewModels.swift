import Foundation
import Observation

enum ManualCaptureRoute: Equatable, Sendable {
    case landing
    case defect(UUID?)
    case meterReading(UUID?)
}

struct DefectObjectOption: Identifiable, Equatable, Sendable {
    let reference: TechnicalObjectReference
    let name: String
    let dinGroup: String?

    var id: String { reference.id }
    var label: String { "\(reference.objectID) · \(name)" }
}

@MainActor
@Observable
final class DefectCaptureViewModel {
    enum LoadState: Equatable { case idle, loading, loaded, empty, failed }

    private let sapDataStore: SAPDataStore
    private let offlineWorkStore: OfflineWorkStore
    private let photoStore: any PhotoAttachmentStore
    private var originalAttachmentIDs = Set<String>()

    private(set) var state: LoadState = .idle
    private(set) var editingID: UUID?
    private(set) var isExistingDraft = false
    private(set) var itemStatus: OfflineWorkStatus?
    private(set) var objects: [DefectObjectOption] = []
    private(set) var isSaving = false
    private(set) var photoData: [String: Data] = [:]
    var selectedObjectID: String?
    var priority: DefectPriority = .medium
    var shortText = ""
    var longText = ""
    var attachmentIDs: [String] = []
    var saveFailed = false
    var photoFailed = false

    init(sapDataStore: SAPDataStore, offlineWorkStore: OfflineWorkStore, photoStore: any PhotoAttachmentStore) {
        self.sapDataStore = sapDataStore
        self.offlineWorkStore = offlineWorkStore
        self.photoStore = photoStore
    }

    var selectedObject: DefectObjectOption? {
        objects.first { $0.id == selectedObjectID }
    }

    var isReadOnly: Bool {
        guard let itemStatus else { return false }
        return itemStatus != .draft
    }

    var canSave: Bool {
        !isReadOnly && !isSaving && selectedObject != nil && !shortText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func load(itemID: UUID?) async {
        await discardStagedPhotos()
        resetFields()
        isExistingDraft = itemID != nil
        editingID = itemID ?? UUID()
        if objects.isEmpty {
            state = .loading
        }
        await offlineWorkStore.load()

        let existingItem = offlineWorkStore.item(id: itemID)
        let existingPayload = existingItem?.payload.defect
        itemStatus = existingItem?.status
        if objects.isEmpty {
            do {
                let nodes = try await sapDataStore.searchTechnicalObjects("", dinGroup: nil, limit: 500)
                objects = nodes.filter { !$0.isSynthetic }.map {
                    DefectObjectOption(reference: $0.reference, name: $0.displayName, dinGroup: $0.dinGroup)
                }
            } catch {
                if let existingPayload {
                    objects = [DefectObjectOption(
                        reference: existingPayload.technicalObject,
                        name: existingPayload.technicalObjectName,
                        dinGroup: existingPayload.dinGroup
                    )]
                }
            }
        }

        if let existingPayload, !objects.contains(where: { $0.reference == existingPayload.technicalObject }) {
            objects.append(DefectObjectOption(
                reference: existingPayload.technicalObject,
                name: existingPayload.technicalObjectName,
                dinGroup: existingPayload.dinGroup
            ))
        }

        state = objects.isEmpty ? .failed : .loaded

        if let payload = existingPayload {
            selectedObjectID = payload.technicalObject.id
            priority = payload.priority
            shortText = payload.shortText
            longText = payload.longText
            attachmentIDs = payload.attachmentIDs
            originalAttachmentIDs = Set(payload.attachmentIDs)
            await loadPhotos()
        }
    }

    func addPhoto(jpegData: Data) async {
        guard !isReadOnly else { return }
        photoFailed = false
        do {
            let id = try await photoStore.saveJPEG(jpegData)
            attachmentIDs.append(id)
            photoData[id] = jpegData
        } catch {
            photoFailed = true
        }
    }

    func removePhoto(id: String) async {
        guard !isReadOnly else { return }
        attachmentIDs.removeAll { $0 == id }
        photoData[id] = nil
        if !originalAttachmentIDs.contains(id) {
            try? await photoStore.delete(id: id)
        }
    }

    func cancel() async {
        await discardStagedPhotos()
        resetFields()
        state = .idle
    }

    func save(status: OfflineWorkStatus) async -> Bool {
        guard canSave, let selectedObject else { return false }
        isSaving = true
        saveFailed = false
        defer { isSaving = false }
        do {
            let item = try await offlineWorkStore.saveDefect(
                id: editingID,
                payload: DefectDraftPayload(
                    technicalObject: selectedObject.reference,
                    technicalObjectName: selectedObject.name,
                    dinGroup: selectedObject.dinGroup,
                    priority: priority,
                    shortText: shortText.trimmingCharacters(in: .whitespacesAndNewlines),
                    longText: longText.trimmingCharacters(in: .whitespacesAndNewlines),
                    attachmentIDs: attachmentIDs
                ),
                status: status
            )
            for removedID in originalAttachmentIDs.subtracting(attachmentIDs) {
                try? await photoStore.delete(id: removedID)
            }
            editingID = item.id
            itemStatus = item.status
            originalAttachmentIDs = Set(attachmentIDs)
            return true
        } catch {
            saveFailed = true
            return false
        }
    }

    private func loadPhotos() async {
        for id in attachmentIDs {
            if let data = try? await photoStore.loadJPEG(id: id) {
                photoData[id] = data
            }
        }
    }

    private func discardStagedPhotos() async {
        for id in Set(attachmentIDs).subtracting(originalAttachmentIDs) {
            try? await photoStore.delete(id: id)
        }
    }

    private func resetFields() {
        editingID = nil
        isExistingDraft = false
        itemStatus = nil
        selectedObjectID = nil
        priority = .medium
        shortText = ""
        longText = ""
        attachmentIDs = []
        originalAttachmentIDs = []
        photoData = [:]
        saveFailed = false
        photoFailed = false
    }
}

@MainActor
@Observable
final class MeterReadingViewModel {
    enum LoadState: Equatable { case idle, loading, loaded, empty, unavailable, failed }

    private let provider: any MeterReferenceProviding
    private let offlineWorkStore: OfflineWorkStore

    let isShowingPreviewData: Bool
    private(set) var state: LoadState = .idle
    private(set) var editingID: UUID?
    private(set) var itemStatus: OfflineWorkStatus?
    private(set) var references: [MeterReference] = []
    private(set) var isSaving = false
    var kind: MeterKind = .electricity
    var selectedReferenceID: String?
    var valueText = "" {
        didSet {
            let sanitized = Self.sanitizeInput(valueText)
            if valueText != sanitized {
                valueText = sanitized
            }
        }
    }
    var note = ""
    var saveFailed = false

    func setValueText(_ value: String) {
        let sanitized = Self.sanitizeInput(value)
        if valueText != sanitized {
            valueText = sanitized
        }
    }

    init(provider: any MeterReferenceProviding, offlineWorkStore: OfflineWorkStore) {
        self.provider = provider
        self.offlineWorkStore = offlineWorkStore
        self.isShowingPreviewData = provider.isPreviewData
    }

    var selectedReference: MeterReference? {
        references.first { $0.id == selectedReferenceID }
    }

    var parsedValue: Decimal? {
        Self.parseDecimal(valueText)
    }

    var isReadOnly: Bool {
        guard let itemStatus else { return false }
        return itemStatus != .draft
    }

    var isBelowPreviousValue: Bool {
        guard let selectedReference, let parsedValue else { return false }
        return parsedValue < selectedReference.previousValue
    }

    var canSave: Bool {
        !isReadOnly && !isSaving && selectedReference != nil && parsedValue != nil
    }

    func load(itemID: UUID?) async {
        editingID = itemID ?? UUID()
        valueText = ""
        note = ""
        saveFailed = false
        await offlineWorkStore.load()
        let item = offlineWorkStore.item(id: itemID)
        itemStatus = item?.status
        let payload = item?.payload.meterReading
        kind = payload?.meter.kind ?? .electricity
        await loadReferences(preserving: payload?.meter)
        if let payload {
            selectedReferenceID = payload.meter.id
            valueText = Self.displayString(payload.value)
            note = payload.note
        }
    }

    func selectKind(_ newKind: MeterKind) async {
        guard !isReadOnly, kind != newKind else { return }
        kind = newKind
        valueText = ""
        note = ""
        await loadReferences(preserving: nil)
    }

    func save(status: OfflineWorkStatus) async -> Bool {
        guard !isReadOnly, canSave, let meter = selectedReference, let value = parsedValue else { return false }
        isSaving = true
        saveFailed = false
        defer { isSaving = false }
        do {
            let item = try await offlineWorkStore.saveMeterReading(
                id: editingID,
                payload: MeterReadingDraftPayload(
                    meter: meter,
                    value: value,
                    note: note.trimmingCharacters(in: .whitespacesAndNewlines)
                ),
                status: status
            )
            editingID = item.id
            itemStatus = item.status
            return true
        } catch {
            saveFailed = true
            return false
        }
    }

    static func sanitizeInput(_ input: String) -> String {
        let normalized = input.replacingOccurrences(of: ".", with: ",")
        var filtered = ""
        var hasComma = false
        for char in normalized {
            if char.isNumber {
                filtered.append(char)
            } else if char == "," && !hasComma {
                hasComma = true
                filtered.append(char)
            }
        }
        return filtered
    }

    static func parseDecimal(_ text: String, locale: Locale = .current) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != ",", trimmed != "." else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        formatter.generatesDecimalNumbers = true
        if let value = formatter.number(from: trimmed)?.decimalValue { return value }
        var normalized = trimmed.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")
        if normalized.hasPrefix(".") { normalized = "0" + normalized }
        if normalized.hasSuffix(".") { normalized.removeLast() }
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func displayString(_ value: Decimal, locale: Locale = Locale(identifier: "de_DE")) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 4
        formatter.minimumFractionDigits = 0
        if let string = formatter.string(from: value as NSDecimalNumber) {
            return string
        }
        return NSDecimalNumber(decimal: value).stringValue.replacingOccurrences(of: ".", with: ",")
    }

    private func loadReferences(preserving saved: MeterReference?) async {
        state = .loading
        selectedReferenceID = nil
        do {
            references = try await provider.references(for: kind)
            if let saved, !references.contains(where: { $0.id == saved.id }) {
                references.append(saved)
            }
            selectedReferenceID = saved?.id ?? references.first?.id
            state = references.isEmpty ? .empty : .loaded
        } catch is MeterReferenceError {
            if let saved {
                references = [saved]
                selectedReferenceID = saved.id
                state = .loaded
            } else {
                references = []
                state = .unavailable
            }
        } catch {
            references = []
            state = .failed
        }
    }
}
