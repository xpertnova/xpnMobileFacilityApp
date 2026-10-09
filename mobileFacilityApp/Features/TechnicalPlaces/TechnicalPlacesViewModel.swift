import Foundation
import Observation
import SwiftUI

/// What the hierarchy can say about identifier naming without inventing
/// anything: an identifier that really exists in the cache and the structure
/// indicators (TPLKZ) the cached functional locations carry.
struct TechnicalPlaceNamingHint: Equatable {
    let exampleID: String
    let structureIndicators: [String]
}

struct TechnicalObjectVisibleRow: Identifiable, Equatable {
    let node: TechnicalObjectNode
    /// Indentation depth, counting the synthetic grouping rows.
    let depth: Int
    /// Depth among the real SAP objects only, so the city grouping rows do not
    /// shift every functional location down a level. This is what decides
    /// which hierarchy level a row is drawn as.
    let structuralDepth: Int
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
    /// The offset of the next page of roots. The page marker row uses it as
    /// its identity, so a page is read once and only while it is on screen.
    private(set) var nextRootOffset: Int?

    private(set) var state: State = .idle
    private(set) var saveState: SaveState = .idle
    private(set) var dinCounts: [TechnicalObjectDINCount] = []
    private(set) var counts: TechnicalObjectCounts = .zero
    /// `counts` and `totalCount` are only meaningful once this is true.
    private(set) var hasLoadedTotalCount = false
    private(set) var selectedDetail: TechnicalObjectDetail?
    var equipmentDraft: EquipmentEditDraft?
    var query = ""
    var selectedDINGroup: String?
    var expanded = Set<TechnicalObjectReference>() {
        didSet { if !isBatchingTreeChanges { rebuildVisibleRows() } }
    }
    var unavailableActionKey: String?
    /// The flattened tree the list renders.
    ///
    /// One SwiftUI pass reads this several times and it walks every expanded
    /// branch, so it is rebuilt when the tree or the expansion changes rather
    /// than on every pass.
    private(set) var visibleRows: [TechnicalObjectVisibleRow] = []
    /// Identifier information for the naming hint, read from the cached SAP
    /// rows themselves. Nothing here is a placeholder: the example is an
    /// identifier that exists in this landscape and the indicators are the
    /// TPLKZ values those rows carry, so the card stays empty until real data
    /// is loaded rather than showing a made-up pattern. Like `visibleRows` it
    /// is derived once per change instead of per render.
    private(set) var namingHint: TechnicalPlaceNamingHint?
    /// The pages currently in flight. A page row stays on screen while its
    /// page loads, so without this a second pass would ask for the same
    /// offset again and append the rows twice.
    private(set) var isLoadingMoreRoots = false
    private(set) var loadingChildrenOf: Set<TechnicalObjectReference> = []
    @ObservationIgnored private var isBatchingTreeChanges = false

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

    private func rebuildVisibleRows() {
        var result: [TechnicalObjectVisibleRow] = []
        func append(_ reference: TechnicalObjectReference, depth: Int, structuralDepth: Int) {
            guard let node = nodesByID[reference] else { return }
            result.append(.init(node: node, depth: depth, structuralDepth: structuralDepth))
            guard expanded.contains(reference) else { return }
            let childStructuralDepth = node.isSynthetic ? structuralDepth : structuralDepth + 1
            for child in childReferences[reference, default: []] {
                append(child, depth: depth + 1, structuralDepth: childStructuralDepth)
            }
        }
        for root in rootReferences { append(root, depth: 0, structuralDepth: 0) }
        visibleRows = result
    }

    /// Applies a group of tree changes with a single rebuild of the derived
    /// state at the end, instead of one per mutation.
    private func batchingTreeChanges(_ body: () -> Void) {
        let wasBatching = isBatchingTreeChanges
        isBatchingTreeChanges = true
        body()
        isBatchingTreeChanges = wasBatching
        guard !isBatchingTreeChanges else { return }
        rebuildVisibleRows()
        rebuildNamingHint()
    }

    var totalCount: Int { counts.total }

    private func rebuildNamingHint() {
        let locations = nodesByID.values.filter {
            !$0.isSynthetic && $0.reference.kind == .functionalLocation
        }
        // The longest identifier is the most deeply structured one, so it shows
        // the most segments of the customer's scheme.
        guard let example = locations
            .map(\.reference.objectID)
            .max(by: { $0.count < $1.count })
        else {
            namingHint = nil
            return
        }
        namingHint = TechnicalPlaceNamingHint(
            exampleID: example,
            structureIndicators: locations.map(\.structureIndicator).uniquedAndSorted()
        )
    }

    func pendingEdit(for node: TechnicalObjectNode) -> OfflineWorkItem? {
        guard node.reference.kind == .equipment else { return nil }
        return offlineWorkStore.technicalObjectEdit(equipmentID: node.reference.objectID)
    }

    func displayName(for node: TechnicalObjectNode) -> String {
        if node.isSynthetic, node.structureLevel == .country {
            return AppLanguage.current.locale.localizedString(forRegionCode: node.countryCode) ?? node.displayName
        }
        return pendingEdit(for: node)?.payload.technicalObjectEdit?.designation ?? node.displayName
    }

    func hasMoreChildren(of reference: TechnicalObjectReference) -> Bool {
        nextOffsets[reference] != nil
    }

    /// The offset of the next page of a branch, used as the identity of the
    /// row that pulls it: a new page means a new task, the same page never
    /// runs twice.
    func nextChildOffset(of reference: TechnicalObjectReference) -> Int? {
        nextOffsets[reference]
    }

    var hasMoreRoots: Bool { nextRootOffset != nil }

    func loadMoreRoots() async {
        guard let offset = nextRootOffset, !isLoadingMoreRoots else { return }
        isLoadingMoreRoots = true
        defer { isLoadingMoreRoots = false }
        do {
            let page = try await sapDataStore.technicalObjectRoots(limit: pageSize, offset: offset)
            withFacilityAnimation {
                batchingTreeChanges {
                    page.objects.forEach { nodesByID[$0.reference] = $0 }
                    sourceRootReferences.append(contentsOf: page.objects.map(\.reference))
                    applyCityGroups(expandGroups: true)
                    nextRootOffset = page.nextOffset
                }
            }
        } catch {
            state = .failed
        }
    }

    func load() async {
        guard state != .loading else { return }
        state = .loading
        do {
            async let objectCounts = sapDataStore.technicalObjectCounts()
            async let groupCounts = sapDataStore.technicalObjectDINCounts()
            async let roots = sapDataStore.technicalObjectRoots(limit: pageSize, offset: 0)
            counts = try await objectCounts
            hasLoadedTotalCount = true
            dinCounts = try await groupCounts
            let loadedRoots = try await roots
            // The country rows open on their cities, so the first screen
            // lists cities rather than a handful of countries.
            var countryPages: [TechnicalObjectReference: TechnicalObjectPage] = [:]
            for country in loadedRoots.objects where country.structureLevel == .country {
                countryPages[country.reference] = try await sapDataStore.technicalObjectChildren(
                    of: country.reference, limit: pageSize, offset: 0
                )
            }
            withFacilityAnimation {
                batchingTreeChanges {
                    applyRootPage(loadedRoots)
                    for (country, page) in countryPages {
                        applyChildPage(page, of: country, offset: 0)
                        expanded.insert(country)
                    }
                }
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
            // A search expands every hit, so a broad query inserts hundreds of
            // rows at once; animating that costs more than the search itself.
            withFacilityAnimation(results.count > 50 ? nil : FacilityMotion.standard) {
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
        withFacilityAnimation {
            selectedDINGroup = selectedDINGroup == code ? nil : code
        }
        await updateSearch()
    }

    func toggle(_ node: TechnicalObjectNode) async {
        if expanded.contains(node.reference) {
            withFacilityAnimation {
                _ = expanded.remove(node.reference)
            }
            return
        }
        withFacilityAnimation {
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

    func isLoadingChildren(of parent: TechnicalObjectReference) -> Bool {
        loadingChildrenOf.contains(parent)
    }

    /// Only a leaf opens a detail view. A row that still has children is a
    /// container in the hierarchy, so tapping it expands or collapses the
    /// subtree instead — the same rule the grouping rows already follow.
    func canOpenDetail(_ node: TechnicalObjectNode) -> Bool {
        !node.isSynthetic && !node.hasChildren
    }

    func open(_ reference: TechnicalObjectReference) async {
        if let node = nodesByID[reference], !canOpenDetail(node) {
            await toggle(node)
            return
        }
        do {
            guard let detail = try await sapDataStore.technicalObjectDetail(reference) else { return }
            // The same rule has to hold for a reference the tree has not
            // loaded yet — the saved-work list deep links straight into a
            // technical object — so the fetched object decides as well.
            guard canOpenDetail(detail.object) else { return }
            withFacilityAnimation(FacilityMotion.navigation) {
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
        withFacilityAnimation(FacilityMotion.navigation) {
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
            withFacilityAnimation {
                saveState = .savedPending
            }
        } catch {
            withFacilityAnimation {
                saveState = .failed
            }
        }
    }

    func reset() {
        batchingTreeChanges {
            nodesByID = [:]
            rootReferences = []
            sourceRootReferences = []
            childReferences = [:]
            nextOffsets = [:]
            nextRootOffset = nil
            expanded = []
        }
        selectedDetail = nil
        equipmentDraft = nil
        counts = .zero
        hasLoadedTotalCount = false
        isLoadingMoreRoots = false
        loadingChildrenOf = []
        state = .idle
    }

    private func loadChildren(of parent: TechnicalObjectReference, offset: Int) async {
        guard loadingChildrenOf.insert(parent).inserted else { return }
        defer { loadingChildrenOf.remove(parent) }
        do {
            let page = try await sapDataStore.technicalObjectChildren(of: parent, limit: pageSize, offset: offset)
            withFacilityAnimation {
                applyChildPage(page, of: parent, offset: offset)
            }
        } catch {
            state = .failed
        }
    }

    private func applyChildPage(_ page: TechnicalObjectPage, of parent: TechnicalObjectReference, offset: Int) {
        batchingTreeChanges {
            page.objects.forEach { nodesByID[$0.reference] = $0 }
            let new = page.objects.map(\.reference)
            if offset == 0 {
                childReferences[parent] = new
            } else {
                // A page boundary can shift between requests when the
                // cache is rebuilt, so a reference that is already
                // there is kept once — a repeated id breaks the list.
                var existing = childReferences[parent, default: []]
                let known = Set(existing)
                existing.append(contentsOf: new.filter { !known.contains($0) })
                childReferences[parent] = existing
            }
            nextOffsets[parent] = page.nextOffset
        }
    }

    private func applyRootPage(_ page: TechnicalObjectPage) {
        batchingTreeChanges {
            nodesByID = Dictionary(uniqueKeysWithValues: page.objects.map { ($0.reference, $0) })
            sourceRootReferences = page.objects.map(\.reference)
            childReferences = [:]
            nextOffsets = [:]
            nextRootOffset = page.nextOffset
            expanded = []
            applyCityGroups(expandGroups: true)
        }
    }

    private func applySearchResults(_ objects: [TechnicalObjectNode]) {
        batchingTreeChanges {
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
    }

    /// City nodes are presentation-only. They group the SAP roots without
    /// changing parent identifiers or being persisted as technical objects.
    private func applyCityGroups(expandGroups: Bool) {
        batchingTreeChanges {
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
}
