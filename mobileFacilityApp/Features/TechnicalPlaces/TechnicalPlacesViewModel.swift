import Foundation
import Observation
import SwiftUI

struct TechnicalObjectVisibleRow: Identifiable, Equatable {
    let node: TechnicalObjectNode
    let depth: Int
    var id: String { node.id }
}

struct EquipmentEditDraft: Equatable {
    let equipmentID: String
    let functionalLocationID: String
    let cityAndLocationDisplay: String
    var designation: String
    var manufacturer: String
    var modelType: String
    var serialNumber: String
    var dinGroup: String?
    var hasNextInspectionDate: Bool
    var nextInspectionDate: Date
    let sourceFingerprint: String

    init(detail: EquipmentDetail, pending: TechnicalObjectEditPayload?) {
        let object = detail.object
        equipmentID = object.reference.objectID
        functionalLocationID = object.functionalLocationID
        cityAndLocationDisplay = object.cityAndLocationDisplay
        designation = pending?.designation ?? object.name
        manufacturer = pending?.manufacturer ?? object.manufacturer
        modelType = pending?.modelType ?? object.modelType
        serialNumber = pending?.serialNumber ?? object.serialNumber
        dinGroup = pending?.dinGroup ?? object.dinGroup
        hasNextInspectionDate = pending?.nextInspectionDate != nil
        nextInspectionDate = pending?.nextInspectionDate ?? Date()
        sourceFingerprint = object.sourceFingerprint
    }

    var payload: TechnicalObjectEditPayload {
        TechnicalObjectEditPayload(
            equipmentID: equipmentID,
            functionalLocationID: functionalLocationID,
            designation: designation.trimmingCharacters(in: .whitespacesAndNewlines),
            manufacturer: manufacturer.trimmingCharacters(in: .whitespacesAndNewlines),
            modelType: modelType.trimmingCharacters(in: .whitespacesAndNewlines),
            serialNumber: serialNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            dinGroup: dinGroup,
            nextInspectionDate: hasNextInspectionDate ? nextInspectionDate : nil,
            sourceFingerprint: sourceFingerprint
        )
    }
}

@MainActor
@Observable
final class TechnicalPlacesViewModel {
    enum State: Equatable { case idle, loading, loaded, empty, noResults, failed }
    enum SaveState: Equatable { case idle, saving, savedPending, conflict, failed }

    private let sapDataStore: SAPDataStore
    private let offlineWorkStore: OfflineWorkStore
    private let unavailableActionHandler: ((String) -> Void)?
    private let pageSize = 100
    private var nodesByID: [TechnicalObjectReference: TechnicalObjectNode] = [:]
    private var rootReferences: [TechnicalObjectReference] = []
    private var sourceRootReferences: [TechnicalObjectReference] = []
    private var childReferences: [TechnicalObjectReference: [TechnicalObjectReference]] = [:]
    private var nextOffsets: [TechnicalObjectReference: Int] = [:]
    private var nextRootOffset: Int?

    private(set) var state: State = .idle
    private(set) var saveState: SaveState = .idle
    private(set) var dinCounts: [TechnicalObjectDINCount] = []
    private(set) var totalCount = 0
    private(set) var selectedDetail: TechnicalObjectDetail?
    var equipmentDraft: EquipmentEditDraft?
    var query = ""
    var selectedDINGroup: String?
    var expanded = Set<TechnicalObjectReference>()
    var unavailableActionKey: String?

    init(
        sapDataStore: SAPDataStore,
        offlineWorkStore: OfflineWorkStore,
        unavailableActionHandler: ((String) -> Void)? = nil
    ) {
        self.sapDataStore = sapDataStore
        self.offlineWorkStore = offlineWorkStore
        self.unavailableActionHandler = unavailableActionHandler
    }

    func performUnavailableAction(_ explanationKey: String) {
        if let unavailableActionHandler { unavailableActionHandler(explanationKey) }
        else { unavailableActionKey = explanationKey }
    }

    var visibleRows: [TechnicalObjectVisibleRow] {
        var result: [TechnicalObjectVisibleRow] = []
        func append(_ reference: TechnicalObjectReference, depth: Int) {
            guard let node = nodesByID[reference] else { return }
            result.append(.init(node: node, depth: depth))
            guard expanded.contains(reference) else { return }
            for child in childReferences[reference, default: []] { append(child, depth: depth + 1) }
        }
        for root in rootReferences { append(root, depth: 0) }
        return result
    }

    func pendingEdit(for node: TechnicalObjectNode) -> OfflineWorkItem? {
        guard node.reference.kind == .equipment else { return nil }
        return offlineWorkStore.technicalObjectEdit(equipmentID: node.reference.objectID)
    }

    func displayName(for node: TechnicalObjectNode) -> String {
        pendingEdit(for: node)?.payload.technicalObjectEdit?.designation ?? node.displayName
    }

    func hasMoreChildren(of reference: TechnicalObjectReference) -> Bool {
        nextOffsets[reference] != nil
    }

    var hasMoreRoots: Bool { nextRootOffset != nil }

    func loadMoreRoots() async {
        guard let offset = nextRootOffset else { return }
        do {
            let page = try await sapDataStore.technicalObjectRoots(limit: pageSize, offset: offset)
            withAnimation(.smooth(duration: 0.24)) {
                page.objects.forEach { nodesByID[$0.reference] = $0 }
                sourceRootReferences.append(contentsOf: page.objects.map(\.reference))
                applyCityGroups(expandGroups: true)
                nextRootOffset = page.nextOffset
            }
        } catch {
            state = .failed
        }
    }

    func load() async {
        guard state != .loading else { return }
        state = .loading
        do {
            async let count = sapDataStore.technicalObjectCount()
            async let counts = sapDataStore.technicalObjectDINCounts()
            async let roots = sapDataStore.technicalObjectRoots(limit: pageSize, offset: 0)
            totalCount = try await count
            dinCounts = try await counts
            let loadedRoots = try await roots
            withAnimation(.smooth(duration: 0.24)) {
                applyRootPage(loadedRoots)
                state = rootReferences.isEmpty ? .empty : .loaded
            }
        } catch is CancellationError {
            return
        } catch {
            state = .failed
        }
    }

    func updateSearch() async {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty || selectedDINGroup != nil else {
            await load()
            return
        }
        state = .loading
        do {
            let results = try await sapDataStore.searchTechnicalObjects(normalized, dinGroup: selectedDINGroup, limit: 500)
            withAnimation(.smooth(duration: 0.24)) {
                applySearchResults(results)
                state = results.isEmpty ? .noResults : .loaded
            }
        } catch is CancellationError {
            return
        } catch {
            state = .failed
        }
    }

    func selectDIN(_ code: String?) async {
        withAnimation(.smooth(duration: 0.2)) {
            selectedDINGroup = selectedDINGroup == code ? nil : code
        }
        await updateSearch()
    }

    func toggle(_ node: TechnicalObjectNode) async {
        if expanded.contains(node.reference) {
            withAnimation(.smooth(duration: 0.22)) {
                _ = expanded.remove(node.reference)
            }
            return
        }
        withAnimation(.smooth(duration: 0.22)) {
            expanded.insert(node.reference)
        }
        guard !node.isCityGroup else { return }
        if childReferences[node.reference] == nil {
            await loadChildren(of: node.reference, offset: 0)
        }
    }

    func loadMoreChildren(of parent: TechnicalObjectReference) async {
        guard let offset = nextOffsets[parent] else { return }
        await loadChildren(of: parent, offset: offset)
    }

    func open(_ reference: TechnicalObjectReference) async {
        if let node = nodesByID[reference], node.isCityGroup {
            await toggle(node)
            return
        }
        do {
            guard let detail = try await sapDataStore.technicalObjectDetail(reference) else { return }
            withAnimation(.smooth(duration: 0.24)) {
                selectedDetail = detail
                saveState = .idle
            }
            if case let .equipment(equipment) = detail {
                let item = offlineWorkStore.technicalObjectEdit(equipmentID: reference.objectID)
                let pending = item?.payload.technicalObjectEdit
                equipmentDraft = EquipmentEditDraft(detail: equipment, pending: pending)
                if let pending, pending.sourceFingerprint != equipment.object.sourceFingerprint {
                    saveState = .conflict
                    if item?.status != .conflict {
                        _ = try? await offlineWorkStore.saveTechnicalObjectEdit(pending, status: .conflict)
                    }
                } else if item != nil {
                    saveState = .savedPending
                }
            }
        } catch {
            state = .failed
        }
    }

    func closeDetail() {
        withAnimation(.smooth(duration: 0.24)) {
            selectedDetail = nil
            equipmentDraft = nil
            saveState = .idle
        }
    }

    func saveEquipment() async {
        guard saveState != .saving, let draft = equipmentDraft,
              draft.dinGroup.map({ TechnicalDIN276.supportedCodes.contains($0) }) ?? true else {
            saveState = .failed
            return
        }
        saveState = .saving
        do {
            _ = try await offlineWorkStore.saveTechnicalObjectEdit(draft.payload)
            withAnimation(.smooth(duration: 0.2)) {
                saveState = .savedPending
            }
        } catch {
            withAnimation(.smooth(duration: 0.2)) {
                saveState = .failed
            }
        }
    }

    func reset() {
        nodesByID = [:]
        rootReferences = []
        sourceRootReferences = []
        childReferences = [:]
        nextOffsets = [:]
        nextRootOffset = nil
        expanded = []
        selectedDetail = nil
        equipmentDraft = nil
        state = .idle
    }

    private func loadChildren(of parent: TechnicalObjectReference, offset: Int) async {
        do {
            let page = try await sapDataStore.technicalObjectChildren(of: parent, limit: pageSize, offset: offset)
            withAnimation(.smooth(duration: 0.24)) {
                page.objects.forEach { nodesByID[$0.reference] = $0 }
                let new = page.objects.map(\.reference)
                childReferences[parent] = offset == 0 ? new : childReferences[parent, default: []] + new
                nextOffsets[parent] = page.nextOffset
            }
        } catch {
            state = .failed
        }
    }

    private func applyRootPage(_ page: TechnicalObjectPage) {
        nodesByID = Dictionary(uniqueKeysWithValues: page.objects.map { ($0.reference, $0) })
        sourceRootReferences = page.objects.map(\.reference)
        childReferences = [:]
        nextOffsets = [:]
        nextRootOffset = page.nextOffset
        expanded = []
        applyCityGroups(expandGroups: true)
    }

    private func applySearchResults(_ objects: [TechnicalObjectNode]) {
        nodesByID = Dictionary(uniqueKeysWithValues: objects.map { ($0.reference, $0) })
        childReferences = Dictionary(grouping: objects.compactMap { node in
            node.parent.map { ($0, node.reference) }
        }, by: \.0).mapValues { $0.map(\.1) }
        let included = Set(nodesByID.keys)
        sourceRootReferences = objects.filter { $0.parent == nil || !included.contains($0.parent!) }.map(\.reference)
        expanded = included
        nextOffsets = [:]
        nextRootOffset = nil
        applyCityGroups(expandGroups: true)
    }

    /// City nodes are presentation-only. They group the SAP roots without
    /// changing parent identifiers or being persisted as technical objects.
    private func applyCityGroups(expandGroups: Bool) {
        let previousCityReferences = nodesByID.values
            .filter(\.isCityGroup)
            .map(\.reference)
        for reference in previousCityReferences {
            nodesByID.removeValue(forKey: reference)
            childReferences.removeValue(forKey: reference)
            expanded.remove(reference)
        }

        let roots = sourceRootReferences.compactMap { reference in
            nodesByID[reference].map { (reference, $0) }
        }
        let grouped = Dictionary(grouping: roots.compactMap { entry -> (TechnicalLocationKey, TechnicalObjectReference, TechnicalObjectNode)? in
            guard !entry.1.isUnassignedGroup, let key = entry.1.locationKey else { return nil }
            return (key, entry.0, entry.1)
        }, by: \.0)
        let groupedRootReferences = Set(grouped.values.flatMap { $0.map(\.1) })

        let cityReferences = grouped.keys.sorted { left, right in
            let leftName = grouped[left]?.first?.2.cityDisplayName ?? left.locationCode
            let rightName = grouped[right]?.first?.2.cityDisplayName ?? right.locationCode
            let nameOrder = leftName.localizedStandardCompare(rightName)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            if left.countryCode != right.countryCode { return left.countryCode < right.countryCode }
            return left.locationCode < right.locationCode
        }.map { key in
            let entries = grouped[key, default: []]
            let cityName = entries.lazy.map(\.2.cityName).first { !$0.isEmpty } ?? ""
            let reference = TechnicalObjectReference.city(
                countryCode: key.countryCode,
                locationCode: key.locationCode
            )
            nodesByID[reference] = .cityGroup(
                countryCode: key.countryCode,
                locationCode: key.locationCode,
                cityName: cityName,
                childCount: entries.count
            )
            childReferences[reference] = entries.map(\.1)
            if expandGroups { expanded.insert(reference) }
            return reference
        }

        let ungroupedReferences = sourceRootReferences.filter { !groupedRootReferences.contains($0) }
        rootReferences = cityReferences + ungroupedReferences
    }
}
