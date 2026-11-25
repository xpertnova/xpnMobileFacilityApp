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

    init(reference: TechnicalObjectReference, name: String, dinGroup: String?) {
        self.reference = reference
        self.name = name
        self.dinGroup = dinGroup
    }

    init(node: TechnicalObjectNode) {
        self.init(reference: node.reference, name: node.displayName, dinGroup: node.dinGroup)
    }

    var id: String { reference.id }
    var label: String { "\(reference.displayID) · \(name)" }
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
    /// The open I1s a defect can be reported under, for every object.
    private(set) var parentNotifications: [DefectParentNotification] = []
    private(set) var isSaving = false
    private(set) var photoData: [String: Data] = [:]
    var selectedObjectID: String?
    var priority: DefectPriority = .medium
    var category: I2NotificationCategory?
    var selectedParentID: String?
    var shortText = ""
    var longText = ""
    var attachmentIDs: [String] = []
    private(set) var syncError: String?
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

    /// The I1s of the selected object.
    var parentOptions: [DefectParentNotification] {
        guard let selectedObject else { return [] }
        return parentOptions(for: selectedObject)
    }

    var selectedParent: DefectParentNotification? {
        parentOptions.first { $0.id == selectedParentID }
    }

    func parentOptions(for object: DefectObjectOption) -> [DefectParentNotification] {
        parentNotifications.filter { $0.belongs(to: object.reference) }
    }

    /// SAP creates an I2 only under an I1, so an object without one cannot
    /// take a defect.
    func canReportDefect(on object: DefectObjectOption) -> Bool {
        !parentOptions(for: object).isEmpty
    }

    /// Picks the object and, when it has exactly one I1, that I1.
    func selectObject(_ id: String?) {
        selectedObjectID = id
        let options = parentOptions
        if !options.contains(where: { $0.id == selectedParentID }) {
            selectedParentID = options.count == 1 ? options[0].id : nil
        }
    }

    /// A defect SAP did not take can be corrected and sent again.
    var isReadOnly: Bool {
        guard let itemStatus else { return false }
        return itemStatus != .draft && itemStatus != .failed
    }

    var canSave: Bool {
        !isReadOnly && !isSaving && selectedObject != nil && selectedParent != nil && category != nil
            && !shortText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// `preselected` is the technical object the technician came from — a
    /// technical place detail — and is only applied to a new draft, never over
    /// the object an existing draft was saved against.
    func load(itemID: UUID?, preselecting preselected: DefectObjectOption? = nil) async {
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
        syncError = existingItem?.status == .failed ? existingItem?.syncError : nil
        if objects.isEmpty {
            do {
                let nodes = try await sapDataStore.searchTechnicalObjects("", dinGroup: nil, limit: 500)
                objects = nodes.filter { !$0.isSynthetic }.map(DefectObjectOption.init(node:))
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

        parentNotifications = await sapDataStore.loadDefectParentNotifications()
        // A saved defect keeps showing its I1 even when the cache no longer
        // holds it open; sending it then fails with the reason.
        if let existingPayload, let parentID = existingPayload.parentNotificationID,
           !parentNotifications.contains(where: { $0.id == parentID }) {
            parentNotifications.append(DefectParentNotification(
                id: parentID,
                title: existingPayload.parentNotificationTitle ?? "",
                functionalLocationID: existingPayload.technicalObject.kind == .functionalLocation
                    ? existingPayload.technicalObject.objectID : "",
                equipmentID: existingPayload.technicalObject.kind == .equipment
                    ? existingPayload.technicalObject.objectID : "",
                startDate: ""
            ))
        }

        // The object list is capped, so the place the technician came from is
        // not necessarily in it.
        if let preselected, !objects.contains(where: { $0.reference == preselected.reference }) {
            objects.append(preselected)
        }

        state = objects.isEmpty ? .failed : .loaded

        if existingPayload == nil, let preselected {
            selectObject(preselected.id)
        }

        if let payload = existingPayload {
            selectedObjectID = payload.technicalObject.id
            priority = payload.priority
            category = payload.category
            selectedParentID = payload.parentNotificationID
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
                    attachmentIDs: attachmentIDs,
                    category: category,
                    parentNotificationID: selectedParent?.id,
                    parentNotificationTitle: selectedParent?.title
                ),
                status: status
            )
            for removedID in originalAttachmentIDs.subtracting(attachmentIDs) {
                try? await photoStore.delete(id: removedID)
            }
            editingID = item.id
            itemStatus = item.status
            syncError = nil
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
        category = nil
        selectedParentID = nil
        syncError = nil
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

    /// `DECIM` of a SAP measuring point caps the fraction digits.
    var hasTooManyDecimals: Bool {
        guard let decimals = selectedReference?.decimals, let parsedValue else { return false }
        return parsedValue.fractionDigitCount > max(decimals, 0)
    }

    /// A SAP counter reading below the last one is refused: the legacy edit
    /// dialog enables Save only for `fValue >= history.RECDV`. Demo meters
    /// keep accepting any value.
    var isRejectedBelowPreviousValue: Bool {
        isBelowPreviousValue && selectedReference?.client != nil
    }

    var canSave: Bool {
        !isReadOnly && !isSaving && selectedReference != nil && parsedValue != nil
            && !isRejectedBelowPreviousValue && !hasTooManyDecimals
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
                    note: String(
                        note.trimmingCharacters(in: .whitespacesAndNewlines)
                            .prefix(MeasuringPointReadingEntry.maximumTextLength)
                    ),
                    recordedAt: .now
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

    /// The most digits, integer and fraction together, a reading may have:
    /// "Number of Chars" of the SAP meter characteristics (`TFM_ZAEHLER_*`,
    /// `ANZST` 10 with 2 decimal places). `MEASURMENT_POINT` carries only
    /// `DECIM`, so the total is fixed here for every meter type.
    nonisolated static let maximumDigitCount = 10

    /// Keeps digits and one decimal comma. `maximumFractionDigits` is the
    /// point's `DECIM`, the `maxFractionDigits` of the legacy input; `0`
    /// drops the comma, `nil` leaves the fraction open. The integer part
    /// takes what the fraction leaves of `maximumDigitCount`.
    nonisolated static func sanitizeInput(_ input: String, maximumFractionDigits: Int? = nil) -> String {
        let normalized = input.replacingOccurrences(of: ".", with: ",")
        let fractionLimit = maximumFractionDigits.map { min(max($0, 0), maximumDigitCount) }
        let integerLimit = maximumDigitCount - (fractionLimit ?? 0)
        var filtered = ""
        var hasComma = false
        var digitCount = 0
        var fractionDigitCount = 0
        for char in normalized {
            if char.isNumber {
                guard digitCount < maximumDigitCount else { continue }
                if hasComma {
                    if let fractionLimit, fractionDigitCount >= fractionLimit { continue }
                    fractionDigitCount += 1
                } else if digitCount >= integerLimit {
                    continue
                }
                digitCount += 1
                filtered.append(char)
            } else if char == "," && !hasComma {
                // With `DECIM` 0 the comma is dropped, and so are the
                // digits after it, rather than joined to the integer part.
                hasComma = true
                if fractionLimit != 0 {
                    filtered.append(char)
                }
            }
        }
        return filtered
    }

    nonisolated static func parseDecimal(_ text: String, locale: Locale = .current) -> Decimal? {
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

    nonisolated static func displayString(_ value: Decimal, locale: Locale = Locale(identifier: "de_DE")) -> String {
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
