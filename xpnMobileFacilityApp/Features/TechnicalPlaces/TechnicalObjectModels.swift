import Foundation

enum TechnicalObjectKind: String, Codable, CaseIterable, Hashable, Sendable {
    case functionalLocation
    case equipment

    var titleKey: String {
        switch self {
        case .functionalLocation: "places.badge.functionalLocation"
        case .equipment: "places.badge.equipment"
        }
    }
}

struct TechnicalObjectReference: Codable, Hashable, Identifiable, Sendable {
    let kind: TechnicalObjectKind
    let objectID: String

    var id: String { "\(kind.rawValue):\(objectID)" }

    /// The identifier as the screens show it. Only the display drops the
    /// padding: SAP, the cache and QR payloads keep the full `EQUNR`.
    var displayID: String {
        kind == .equipment ? objectID.withoutSAPLeadingZeros : objectID
    }

    static let unassigned = TechnicalObjectReference(
        kind: .functionalLocation,
        objectID: "__unassigned__"
    )

    static func city(countryCode: String, locationCode: String) -> TechnicalObjectReference {
        TechnicalObjectReference(
            kind: .functionalLocation,
            objectID: "__city__:\(countryCode.uppercased())|\(locationCode.uppercased())"
        )
    }
}

extension String {
    /// SAP pads numeric keys — equipment, notification and measuring point
    /// numbers — with zeros; the legacy lists showed them without the
    /// padding. For display only: SAP and the cache need the padded key.
    var withoutSAPLeadingZeros: String {
        guard !isEmpty, allSatisfy({ $0.isASCII && $0.isNumber }) else { return self }
        let trimmed = drop(while: { $0 == "0" })
        return trimmed.isEmpty ? "0" : String(trimmed)
    }
}

/// The levels of the customer's RE-FX identifier scheme,
/// `XX-XXX-XXXXX-XX-XXX-XXX`: country (`TPLND`), city (`TPORT`), business
/// entity (`TPWEH`), building (`TPGEB`), DIN 276 cost group (`TPGSG`) and
/// the final object. The raw value is the number of segments.
enum TechnicalPlaceStructureLevel: Int, CaseIterable, Sendable {
    case country = 1, city, businessEntity, building, costGroup, finalObject

    var nameKey: String {
        switch self {
        case .country: "places.level.country"
        case .city: "places.level.city"
        case .businessEntity: "places.level.businessEntity"
        case .building: "places.level.building"
        case .costGroup: "places.level.costGroup"
        case .finalObject: "places.level.object"
        }
    }
}

/// Builds the technical places tree from the RE-FX identifier itself: a place
/// hangs under the place one segment shorter. SAP's own `TPLMA` cannot be used
/// for this — it points at country and city places SAP never sends to the
/// device, which left nearly every place unassigned.
enum TechnicalPlaceStructure {
    static let indicator = "RE-FX"
    static let separator = "-"

    /// The identifier's segments when it fits the scheme, nil otherwise.
    static func segments(of identifier: String) -> [String]? {
        let segments = identifier.components(separatedBy: separator)
        guard segments.count <= TechnicalPlaceStructureLevel.allCases.count,
              !segments.contains(where: \.isEmpty)
        else { return nil }
        return segments
    }

    /// The country a first segment stands for. Some companies key Germany as
    /// `D` plus a character of their own — `D1`, `D2`, `D8`, `DR`, `DW` — so
    /// every such segment is Germany (confirmed by the SAP side), unless it is
    /// another country's ISO code such as `DK`.
    static func country(of segment: String) -> String {
        let code = segment.uppercased()
        guard code.hasPrefix("D"), !isoRegionCodes.contains(code) else { return code }
        return "DE"
    }

    private static let isoRegionCodes = Set(Locale.Region.isoRegions.map(\.identifier))

    /// The cost group segment, when the identifier reaches that level.
    static func costGroup(of identifier: String) -> String? {
        guard let segments = segments(of: identifier),
              segments.count >= TechnicalPlaceStructureLevel.costGroup.rawValue
        else { return nil }
        return segments[TechnicalPlaceStructureLevel.costGroup.rawValue - 1]
    }

    /// Gives every RE-FX place the place one segment shorter as its parent,
    /// creating placeholders for the levels the cache does not hold — country
    /// and city are never sent, deeper levels sometimes are not. A city hangs
    /// under its country's ISO code, so `D1-HAM` and `DE-ESS` share one
    /// Germany. Equipment
    /// whose superior equipment is not cached moves to its own place, and
    /// equipment on an uncached place of a known RE-FX country gets that
    /// place as a placeholder too.
    static func attach(_ nodes: inout [TechnicalObjectReference: TechnicalObjectNode]) {
        let ordered = nodes.values.sorted { $0.reference.id < $1.reference.id }
        let places = ordered.filter { $0.structureLevel != nil && !$0.isSynthetic }
        let countries = Set(places.compactMap { segments(of: $0.reference.objectID)?.first.map(country(of:)) })
        // Equipment counts too: some cities are only reached through it.
        var cityNames: [String: String] = [:]
        for node in ordered where !node.isSynthetic && !node.cityName.isEmpty {
            guard let segments = segments(of: node.functionalLocationID), segments.count >= 2 else { continue }
            let city = segments.prefix(2).joined(separator: separator)
            if cityNames[city] == nil { cityNames[city] = node.cityName }
        }
        func place(_ identifier: String) -> TechnicalObjectReference {
            let reference = TechnicalObjectReference(kind: .functionalLocation, objectID: identifier)
            guard nodes[reference] == nil else { return reference }
            let city = identifier.components(separatedBy: separator).prefix(2).joined(separator: separator)
            var placeholder = TechnicalObjectNode.structurePlaceholder(identifier, cityName: cityNames[city] ?? "")
            if let parentID = parentID(of: identifier) {
                placeholder.parent = place(parentID)
            }
            nodes[reference] = placeholder
            return reference
        }

        for original in places {
            var node = original
            node.parent = nil
            if let parentID = parentID(of: node.reference.objectID) {
                node.parent = place(parentID)
            }
            node.isUnassigned = false
            nodes[node.reference] = node
        }

        for original in ordered where original.reference.kind == .equipment {
            var node = original
            if let parent = node.parent, parent.kind == .equipment, nodes[parent] != nil { continue }
            let locationID = node.functionalLocationID
            let location = TechnicalObjectReference(kind: .functionalLocation, objectID: locationID)
            if nodes[location] != nil {
                node.parent = location
            } else if let segments = segments(of: locationID), countries.contains(country(of: segments[0])) {
                node.parent = place(locationID)
            } else {
                continue
            }
            node.isUnassigned = false
            nodes[node.reference] = node
        }
    }

    private static func parentID(of identifier: String) -> String? {
        guard let segments = segments(of: identifier), segments.count > 1 else { return nil }
        if segments.count == TechnicalPlaceStructureLevel.city.rawValue {
            return country(of: segments[0])
        }
        return segments.dropLast().joined(separator: separator)
    }
}

struct TechnicalLocationKey: Hashable, Sendable {
    let countryCode: String
    let locationCode: String

    init?(countryCode: String, locationCode: String) {
        let country = countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let location = locationCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !location.isEmpty else { return nil }
        self.countryCode = country
        self.locationCode = location
    }
}

/// The address a creation form should start on, taken from the technical
/// place the technician opened it from.
///
/// TFM5 and TFM7 address a building through the legacy `TPLND` / `TPWEH` /
/// `TPGEB` classification, never through the place's own identifier, so that
/// is what is matched. The trade is deliberately left out: the ladder contexts
/// live under their own `TPGSG` (350), which is not the trade of the place the
/// technician is standing on.
///
/// The form is filled as far down as the anchor matches: the business entity
/// alone when the building has no creation context (or the place sits above
/// building level), then the building, then the last level if only one is
/// left to choose.
struct TechnicalPlaceCreationAnchor: Equatable, Sendable {
    let countryCode: String
    let businessEntityCode: String
    /// Empty for a place that is not classified down to a building, such as
    /// an outdoor area.
    let buildingCode: String

    /// Nil when the place carries no business entity; the form then opens
    /// with its normal pickers.
    init?(_ node: TechnicalObjectNode) {
        guard node.reference.kind == .functionalLocation, !node.isSynthetic,
              !node.businessEntityCode.isEmpty
        else { return nil }
        countryCode = node.countryCode
        businessEntityCode = node.businessEntityCode
        buildingCode = node.buildingCode
    }

    /// A country code is only compared when both sides carry one, so a cache
    /// that leaves `TPLND` empty still matches on the business entity.
    func matches(countryCode other: String, businessEntity: String) -> Bool {
        guard businessEntity == businessEntityCode else { return false }
        return countryCode.isEmpty || other.isEmpty || other == countryCode
    }

    func matches(countryCode other: String, businessEntity: String, building: String) -> Bool {
        !buildingCode.isEmpty && building == buildingCode
            && matches(countryCode: other, businessEntity: businessEntity)
    }
}

struct TechnicalObjectNode: Codable, Equatable, Identifiable, Sendable {
    let reference: TechnicalObjectReference
    var parent: TechnicalObjectReference?
    let client: String
    let name: String
    var functionalLocationID: String
    var countryCode: String
    var locationCode: String
    var cityName: String
    let hierarchyLevel: String
    let category: String
    let structureIndicator: String
    /// `TPWEH` / `TPGEB` / `TPGSG`: the business entity, building and trade a
    /// functional location belongs to. The creation forms address a building
    /// by these codes, so a place can point them at itself. Equipment rows
    /// (`FROM_T0262`) do not carry them and leave them empty.
    let businessEntityCode: String
    let buildingCode: String
    let tradeCode: String
    let equipmentCategory: String
    let equipmentType: String
    let manufacturer: String
    let modelType: String
    let serialNumber: String
    let systemStatus: String
    let userStatus: String
    let dinGroup: String?
    let sourceFingerprint: String
    var directChildCount: Int
    var directEquipmentCount: Int
    var isUnassigned: Bool
    let isSynthetic: Bool

    init(
        reference: TechnicalObjectReference,
        parent: TechnicalObjectReference?,
        client: String,
        name: String,
        functionalLocationID: String,
        countryCode: String = "",
        locationCode: String = "",
        cityName: String = "",
        hierarchyLevel: String,
        category: String,
        structureIndicator: String,
        businessEntityCode: String = "",
        buildingCode: String = "",
        tradeCode: String = "",
        equipmentCategory: String,
        equipmentType: String,
        manufacturer: String,
        modelType: String,
        serialNumber: String,
        systemStatus: String,
        userStatus: String,
        dinGroup: String?,
        sourceFingerprint: String,
        directChildCount: Int,
        directEquipmentCount: Int,
        isUnassigned: Bool,
        isSynthetic: Bool
    ) {
        self.reference = reference
        self.parent = parent
        self.client = client
        self.name = name
        self.functionalLocationID = functionalLocationID
        self.countryCode = countryCode
        self.locationCode = locationCode
        self.cityName = cityName
        self.hierarchyLevel = hierarchyLevel
        self.category = category
        self.structureIndicator = structureIndicator
        self.businessEntityCode = businessEntityCode
        self.buildingCode = buildingCode
        self.tradeCode = tradeCode
        self.equipmentCategory = equipmentCategory
        self.equipmentType = equipmentType
        self.manufacturer = manufacturer
        self.modelType = modelType
        self.serialNumber = serialNumber
        self.systemStatus = systemStatus
        self.userStatus = userStatus
        self.dinGroup = dinGroup
        self.sourceFingerprint = sourceFingerprint
        self.directChildCount = directChildCount
        self.directEquipmentCount = directEquipmentCount
        self.isUnassigned = isUnassigned
        self.isSynthetic = isSynthetic
    }

    var id: String { reference.id }

    var displayName: String {
        name.isEmpty ? reference.displayID : name
    }

    var displayStatus: String {
        [systemStatus, userStatus]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var hasChildren: Bool { directChildCount > 0 }

    var locationKey: TechnicalLocationKey? {
        TechnicalLocationKey(countryCode: countryCode, locationCode: locationCode)
    }

    var cityDisplayName: String {
        cityName.isEmpty ? locationCode : cityName
    }

    var cityAndLocationDisplay: String {
        [cityDisplayName, locationCode]
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { values, value in
                if !values.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) {
                    values.append(value)
                }
            }
            .joined(separator: " · ")
    }

    var isCityGroup: Bool {
        isSynthetic && reference.objectID.hasPrefix("__city__:")
    }

    var isUnassignedGroup: Bool {
        reference == .unassigned
    }

    /// The level of a place in the RE-FX identifier scheme; nil for equipment
    /// and for places of any other structure indicator.
    var structureLevel: TechnicalPlaceStructureLevel? {
        guard reference.kind == .functionalLocation,
              structureIndicator == TechnicalPlaceStructure.indicator,
              let segments = TechnicalPlaceStructure.segments(of: reference.objectID)
        else { return nil }
        return TechnicalPlaceStructureLevel(rawValue: segments.count)
    }

    /// A level of the RE-FX scheme the cache holds no row for, kept so the
    /// places under it still sit in the tree. It carries only what its
    /// identifier says and never opens a detail.
    static func structurePlaceholder(_ identifier: String, cityName: String) -> TechnicalObjectNode {
        let segments = TechnicalPlaceStructure.segments(of: identifier) ?? []
        func segment(_ level: TechnicalPlaceStructureLevel) -> String {
            segments.count >= level.rawValue ? segments[level.rawValue - 1] : ""
        }
        // A city SAP sends no name for is titled by its own code, so it
        // reads and sorts like the named ones.
        let isCity = segments.count == TechnicalPlaceStructureLevel.city.rawValue
        let cityTitle = cityName.isEmpty ? segment(.city) : cityName
        return TechnicalObjectNode(
            reference: TechnicalObjectReference(kind: .functionalLocation, objectID: identifier),
            parent: nil,
            client: "",
            name: isCity ? cityTitle : "",
            functionalLocationID: identifier,
            countryCode: segment(.country),
            locationCode: segment(.city),
            cityName: cityName,
            hierarchyLevel: "",
            category: "",
            structureIndicator: TechnicalPlaceStructure.indicator,
            businessEntityCode: segment(.businessEntity),
            buildingCode: segment(.building),
            tradeCode: segment(.costGroup),
            equipmentCategory: "",
            equipmentType: "",
            manufacturer: "",
            modelType: "",
            serialNumber: "",
            systemStatus: "",
            userStatus: "",
            dinGroup: TechnicalDIN276.detect(explicitValue: segment(.costGroup), label: ""),
            sourceFingerprint: "",
            directChildCount: 0,
            directEquipmentCount: 0,
            isUnassigned: false,
            isSynthetic: true
        )
    }

    static let unassignedRoot = TechnicalObjectNode(
        reference: .unassigned,
        parent: nil,
        client: "",
        name: "",
        functionalLocationID: "",
        countryCode: "",
        locationCode: "",
        cityName: "",
        hierarchyLevel: "",
        category: "",
        structureIndicator: "",
        equipmentCategory: "",
        equipmentType: "",
        manufacturer: "",
        modelType: "",
        serialNumber: "",
        systemStatus: "",
        userStatus: "",
        dinGroup: nil,
        sourceFingerprint: "",
        directChildCount: 0,
        directEquipmentCount: 0,
        isUnassigned: false,
        isSynthetic: true
    )

    static func cityGroup(
        countryCode: String,
        locationCode: String,
        cityName: String,
        childCount: Int
    ) -> TechnicalObjectNode {
        TechnicalObjectNode(
            reference: .city(countryCode: countryCode, locationCode: locationCode),
            parent: nil,
            client: "",
            name: cityName.isEmpty ? locationCode : cityName,
            functionalLocationID: "",
            countryCode: countryCode,
            locationCode: locationCode,
            cityName: cityName,
            hierarchyLevel: "city",
            category: "",
            structureIndicator: "",
            equipmentCategory: "",
            equipmentType: "",
            manufacturer: "",
            modelType: "",
            serialNumber: "",
            systemStatus: "",
            userStatus: "",
            dinGroup: nil,
            sourceFingerprint: "",
            directChildCount: childCount,
            directEquipmentCount: 0,
            isUnassigned: false,
            isSynthetic: true
        )
    }
}

struct TechnicalObjectPage: Equatable, Sendable {
    let objects: [TechnicalObjectNode]
    let nextOffset: Int?
    let totalCount: Int

    static let empty = TechnicalObjectPage(objects: [], nextOffset: nil, totalCount: 0)
}

/// How many cached technical objects a worker has, split by kind. Feeds the
/// hierarchy subtitle, which names functional locations and equipment
/// separately.
struct TechnicalObjectCounts: Equatable, Sendable {
    let functionalLocations: Int
    let equipment: Int

    static let zero = TechnicalObjectCounts(functionalLocations: 0, equipment: 0)

    var total: Int { functionalLocations + equipment }
}

struct TechnicalObjectDINCount: Equatable, Identifiable, Sendable {
    let code: String
    let count: Int

    var id: String { code }
}

struct FunctionalLocationDetail: Equatable, Sendable {
    let object: TechnicalObjectNode
    let breadcrumbs: [TechnicalObjectNode]
    let children: [TechnicalObjectNode]
    let linkedNotifications: [SAPNotificationSummary]
}

struct EquipmentDetail: Equatable, Sendable {
    let object: TechnicalObjectNode
    let breadcrumbs: [TechnicalObjectNode]
    let linkedNotifications: [SAPNotificationSummary]
}

enum TechnicalObjectDetail: Equatable, Sendable {
    case functionalLocation(FunctionalLocationDetail)
    case equipment(EquipmentDetail)

    var object: TechnicalObjectNode {
        switch self {
        case let .functionalLocation(detail): detail.object
        case let .equipment(detail): detail.object
        }
    }
}

protocol TechnicalObjectRepository: Sendable {
    func loadTechnicalObjectRoots(
        for localWorkerID: String,
        limit: Int,
        offset: Int
    ) async throws -> TechnicalObjectPage
    func loadTechnicalObjectChildren(
        for localWorkerID: String,
        parent: TechnicalObjectReference,
        limit: Int,
        offset: Int
    ) async throws -> TechnicalObjectPage
    func searchTechnicalObjects(
        for localWorkerID: String,
        query: String,
        dinGroup: String?
    ) async throws -> [TechnicalObjectNode]
    func loadTechnicalObjectDINCounts(
        for localWorkerID: String
    ) async throws -> [TechnicalObjectDINCount]
    func loadTechnicalObjectDetail(
        for localWorkerID: String,
        reference: TechnicalObjectReference
    ) async throws -> TechnicalObjectDetail?
    func technicalObjectCount(
        for localWorkerID: String,
        kind: TechnicalObjectKind
    ) async throws -> Int
}

enum TechnicalDIN276 {
    static let supportedCodes = [
        "300", "330", "340", "350", "360", "390",
        "410", "420", "430", "440", "450", "460",
        "470", "480", "500", "550"
    ]

    /// Short cost-group name for the filter chips. The full DIN 276 titles are
    /// too long for a chip (KG 450 alone is 63 characters), so the bar uses the
    /// abbreviated names from the design reference.
    static func shortNameKey(for code: String) -> String {
        "places.din.\(code)"
    }

    /// `"430 · Raumlufttechnik (4)"`. The separator and the count are the same
    /// in both catalog languages, so only the name is localized.
    static func chipLabel(for code: String, count: Int) -> String {
        let key = shortNameKey(for: code)
        let name = String(localized: String.LocalizationValue(stringLiteral: key), bundle: .appLanguage)
        // A code without a short name in the catalog keeps the bare KG label
        // instead of printing the missing key.
        guard name != key else { return "KG \(code) (\(count))" }
        return "\(code) · \(name) (\(count))"
    }

    static func detect(explicitValue: String = "", label: String) -> String? {
        if let explicit = uniqueSupportedCode(in: explicitValue) {
            return explicit
        }
        return uniqueSupportedCode(in: label)
    }

    private static func uniqueSupportedCode(in value: String) -> String? {
        let components = value.components(separatedBy: CharacterSet.alphanumerics.inverted)
        let matches = Set(components.filter { supportedCodes.contains($0) })
        return matches.count == 1 ? matches.first : nil
    }
}

enum TechnicalObjectFingerprint {
    static func make(_ values: [String]) -> String {
        // Stable FNV-1a is sufficient for change detection and avoids retaining
        // complete source rows in pending work metadata.
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in values.joined(separator: "\u{001F}").utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

enum TechnicalObjectHierarchyNormalizer {
    static func normalize(_ source: [TechnicalObjectNode]) -> [TechnicalObjectNode] {
        var nodes: [TechnicalObjectReference: TechnicalObjectNode] = [:]
        for node in source where nodes[node.reference] == nil {
            nodes[node.reference] = node
        }
        TechnicalPlaceStructure.attach(&nodes)
        let references = Set(nodes.keys)

        for reference in Array(nodes.keys) {
            guard var node = nodes[reference], let parent = node.parent else { continue }
            if parent == reference || !references.contains(parent) {
                node.parent = nil
                node.isUnassigned = true
                nodes[reference] = node
            }
        }

        var resolved = Set<TechnicalObjectReference>()
        for start in Array(nodes.keys) where !resolved.contains(start) {
            var path: [TechnicalObjectReference] = []
            var indexes: [TechnicalObjectReference: Int] = [:]
            var current: TechnicalObjectReference? = start

            while let reference = current, !resolved.contains(reference) {
                if let cycleStart = indexes[reference] {
                    for cycleReference in path[cycleStart...] {
                        guard var cycleNode = nodes[cycleReference] else { continue }
                        cycleNode.parent = nil
                        cycleNode.isUnassigned = true
                        nodes[cycleReference] = cycleNode
                    }
                    break
                }
                indexes[reference] = path.count
                path.append(reference)
                current = nodes[reference]?.parent
            }
            resolved.formUnion(path)
        }

        var childCounts: [TechnicalObjectReference: Int] = [:]
        var equipmentCounts: [TechnicalObjectReference: Int] = [:]
        for node in nodes.values {
            guard let parent = node.parent else { continue }
            childCounts[parent, default: 0] += 1
            if node.reference.kind == .equipment {
                equipmentCounts[parent, default: 0] += 1
            }
        }

        return nodes.values.map { node in
            var result = node
            result.directChildCount = childCounts[node.reference, default: 0]
            result.directEquipmentCount = equipmentCounts[node.reference, default: 0]
            return result
        }
        .sorted {
            if $0.reference.kind != $1.reference.kind {
                return $0.reference.kind == .functionalLocation
            }
            let nameOrder = $0.displayName.localizedStandardCompare($1.displayName)
            return nameOrder == .orderedSame
                ? $0.reference.objectID < $1.reference.objectID
                : nameOrder == .orderedAscending
        }
    }
}

enum SAPTechnicalObjectMapper {
    /// SAP superior-location links use the internal `TPLNR`, while the app
    /// presents `STRNO`. Aliases are resolved after every snapshot pack has
    /// been collected so parents can live in a different pack.
    static func functionalLocationAliases(from rows: [[String: Any]]) -> [String: String] {
        var aliases: [String: String] = [:]
        for row in rows {
            let externalID = string("STRNO", in: row)
            guard !externalID.isEmpty else { continue }
            aliases[externalID] = externalID
            let internalID = string("TPLNR", in: row)
            if !internalID.isEmpty { aliases[internalID] = externalID }
        }
        return aliases
    }

    /// City names are supplied by the established legacy address fields, while
    /// `TPLND`/`TPORT` form the stable technical location key. `STRNO` is a
    /// verified fallback for those two codes when a row omits them.
    static func cityNames(from rows: [[String: Any]]) -> [TechnicalLocationKey: String] {
        var names: [TechnicalLocationKey: String] = [:]
        for row in rows {
            let identity = locationIdentity(in: row)
            guard let key = TechnicalLocationKey(
                countryCode: identity.countryCode,
                locationCode: identity.locationCode
            ) else { continue }
            let cityName = firstString(["CITY1_TO", "CITY1_QM", "CITY1"], in: row)
            guard !cityName.isEmpty else { continue }
            names[key] = cityName
        }
        return names
    }

    static func resolveRelationships(
        in source: [TechnicalObjectNode],
        functionalLocationAliases: [String: String],
        cityNames: [TechnicalLocationKey: String] = [:]
    ) -> [TechnicalObjectNode] {
        var resolved = source.map { sourceNode in
            var node = sourceNode
            if let parent = node.parent,
               parent.kind == .functionalLocation,
               let externalParentID = functionalLocationAliases[parent.objectID] {
                node.parent = TechnicalObjectReference(
                    kind: .functionalLocation,
                    objectID: externalParentID
                )
            }
            if node.reference.kind == .equipment,
               let externalLocationID = functionalLocationAliases[node.functionalLocationID] {
                node.functionalLocationID = externalLocationID
                if node.parent?.kind == .functionalLocation {
                    node.parent = TechnicalObjectReference(
                        kind: .functionalLocation,
                        objectID: externalLocationID
                    )
                }
            }
            return node
        }

        let locationsByID = Dictionary(uniqueKeysWithValues: resolved.compactMap { node in
            node.reference.kind == .functionalLocation
                ? (node.reference.objectID, node)
                : nil
        })
        resolved = resolved.map { sourceNode in
            var node = sourceNode
            if let key = node.locationKey, node.cityName.isEmpty {
                node.cityName = cityNames[key] ?? ""
            }
            if node.reference.kind == .equipment,
               let location = locationsByID[node.functionalLocationID] {
                if node.countryCode.isEmpty { node.countryCode = location.countryCode }
                if node.locationCode.isEmpty { node.locationCode = location.locationCode }
                if node.cityName.isEmpty { node.cityName = location.cityName }
            }
            if let key = node.locationKey, node.cityName.isEmpty {
                node.cityName = cityNames[key] ?? ""
            }
            return node
        }
        return resolved
    }

    static func functionalLocation(from row: [String: Any]) -> TechnicalObjectNode? {
        let id = string("STRNO", in: row)
        guard !id.isEmpty else { return nil }
        let parentID = string("TPLMA", in: row)
        let name = string("PLTXT", in: row)
        let location = locationIdentity(in: row)
        let explicitDIN = firstString(["DIN276", "DIN_KG", "KOSTENGRUPPE"], in: row)
        // An RE-FX place names its cost group in the fifth segment only; a
        // final object numbered like a cost group must not count as one.
        let dinGroup = string("TPLKZ", in: row) == TechnicalPlaceStructure.indicator
            ? TechnicalDIN276.detect(
                explicitValue: explicitDIN.isEmpty ? TechnicalPlaceStructure.costGroup(of: id) ?? "" : explicitDIN,
                label: ""
            )
            : TechnicalDIN276.detect(explicitValue: explicitDIN, label: id)
        let values = [
            id, parentID, name, string("LEVELID", in: row), string("FLTYP", in: row),
            string("TPLKZ", in: row), string("STTXT", in: row), string("USTXT", in: row),
            dinGroup ?? ""
        ]
        return TechnicalObjectNode(
            reference: TechnicalObjectReference(kind: .functionalLocation, objectID: id),
            parent: parentID.isEmpty ? nil : TechnicalObjectReference(kind: .functionalLocation, objectID: parentID),
            client: string("MANDT", in: row),
            name: name,
            functionalLocationID: id,
            countryCode: location.countryCode,
            locationCode: location.locationCode,
            cityName: firstString(["CITY1_TO", "CITY1_QM", "CITY1"], in: row),
            hierarchyLevel: string("LEVELID", in: row),
            category: string("FLTYP", in: row),
            structureIndicator: string("TPLKZ", in: row),
            businessEntityCode: string("TPWEH", in: row),
            buildingCode: string("TPGEB", in: row),
            tradeCode: string("TPGSG", in: row),
            equipmentCategory: "",
            equipmentType: "",
            manufacturer: string("HERST", in: row),
            modelType: string("TYPBZ", in: row),
            serialNumber: string("SERGE", in: row),
            systemStatus: string("STTXT", in: row),
            userStatus: string("USTXT", in: row),
            dinGroup: dinGroup,
            sourceFingerprint: TechnicalObjectFingerprint.make(values),
            directChildCount: 0,
            directEquipmentCount: 0,
            isUnassigned: false,
            isSynthetic: false
        )
    }

    static func equipment(from row: [String: Any]) -> TechnicalObjectNode? {
        let id = string("EQUNR", in: row)
        guard !id.isEmpty else { return nil }
        let superiorEquipment = string("HEQUI", in: row)
        let functionalLocation = firstString(["STRNO", "TPLNR"], in: row)
        let location = locationIdentity(in: row, functionalLocationID: functionalLocation)
        let parent: TechnicalObjectReference? = !superiorEquipment.isEmpty
            ? TechnicalObjectReference(kind: .equipment, objectID: superiorEquipment)
            : functionalLocation.isEmpty
                ? nil
                : TechnicalObjectReference(kind: .functionalLocation, objectID: functionalLocation)
        let name = string("EQKTX", in: row)
        let dinGroup = TechnicalDIN276.detect(
            explicitValue: firstString(["DIN276", "DIN_KG", "KOSTENGRUPPE"], in: row),
            label: functionalLocation
        )
        let values = [
            id, superiorEquipment, functionalLocation, name, string("HERST", in: row),
            string("TYPBZ", in: row), string("SERGE", in: row), string("EQTYP", in: row),
            string("EQART", in: row), string("STTXT", in: row), string("USTXT", in: row),
            dinGroup ?? ""
        ]
        return TechnicalObjectNode(
            reference: TechnicalObjectReference(kind: .equipment, objectID: id),
            parent: parent,
            client: string("MANDT", in: row),
            name: name,
            functionalLocationID: functionalLocation,
            countryCode: location.countryCode,
            locationCode: location.locationCode,
            cityName: firstString(["CITY1_TO", "CITY1_QM", "CITY1"], in: row),
            hierarchyLevel: "",
            category: "",
            structureIndicator: "",
            equipmentCategory: string("EQTYP", in: row),
            equipmentType: string("EQART", in: row),
            manufacturer: string("HERST", in: row),
            modelType: string("TYPBZ", in: row),
            serialNumber: string("SERGE", in: row),
            systemStatus: string("STTXT", in: row),
            userStatus: string("USTXT", in: row),
            dinGroup: dinGroup,
            sourceFingerprint: TechnicalObjectFingerprint.make(values),
            directChildCount: 0,
            directEquipmentCount: 0,
            isUnassigned: parent == nil,
            isSynthetic: false
        )
    }

    private static func firstString(_ keys: [String], in row: [String: Any]) -> String {
        for key in keys {
            let value = string(key, in: row)
            if !value.isEmpty { return value }
        }
        return ""
    }

    private static func locationIdentity(
        in row: [String: Any],
        functionalLocationID: String? = nil
    ) -> (countryCode: String, locationCode: String) {
        let identifier = functionalLocationID ?? firstString(["STRNO", "TPLNR"], in: row)
        let components = identifier
            .split(separator: "-", omittingEmptySubsequences: false)
            .map(String.init)
        let countryCode = firstString(["TPLND"], in: row)
        let locationCode = firstString(["TPORT"], in: row)
        return (
            countryCode.isEmpty ? (components.first ?? "") : countryCode,
            locationCode.isEmpty && components.count > 1 ? components[1] : locationCode
        )
    }

    private static func string(_ key: String, in row: [String: Any]) -> String {
        let value = row.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
        switch value {
        case let string as String:
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        case let number as NSNumber:
            return number.stringValue
        default:
            return ""
        }
    }
}
