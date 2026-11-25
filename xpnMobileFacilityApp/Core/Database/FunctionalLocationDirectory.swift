import Foundation

/// One SAP functional location (`FROM_T0272`) at business-entity, building
/// or trade level.
struct FunctionalLocation: Codable, Equatable, Hashable, Identifiable, Sendable {
    /// `STRNO`, e.g. `DE-SAF-11152-01`.
    let id: String
    /// `TPLND`.
    let countryCode: String
    /// `TPORT`.
    let locationCode: String
    /// `TPWEH`.
    let businessEntityCode: String
    /// `TPGEB`, empty for a business entity.
    let buildingCode: String
    /// `TPGSG`, empty above trade level.
    let tradeCode: String
    /// `PLTXT`.
    let title: String
    let street: String
    let postalCode: String
    let city: String
    /// `COUNTRY` of the address.
    let country: String

    /// `TPLND-TPORT-TPWEH`, the business entity key of the notification
    /// filter and the safety forms.
    var businessEntityID: String {
        [countryCode, locationCode, businessEntityCode].filter { !$0.isEmpty }.joined(separator: "-")
    }
}

/// The active SAP functional locations the creation dropdowns of the legacy
/// app offer (`getWE4CreateDDB`, `getGE4CreateDDB`, `getGW4CreateDDB`), and
/// the names its filters resolve through `techPlatzMap`.
///
/// Each level has its own location: a business entity has no building
/// (`TPGEB = ''`), a building has no trade (`TPGSG = ''`), a trade has no
/// sub-location (`TPUSG = ''`). A name always comes from the location of that
/// level; a notification's or a sub-location's text never names a building.
struct FunctionalLocationDirectory: Equatable, Sendable {
    static let empty = FunctionalLocationDirectory(locations: [])

    /// Business entities, ordered by key.
    let businessEntities: [FunctionalLocation]
    /// Buildings, ordered by business entity and building code.
    let buildings: [FunctionalLocation]
    private let businessEntitiesByKey: [String: FunctionalLocation]
    private let buildingsByKey: [String: FunctionalLocation]
    private let tradesByKey: [String: FunctionalLocation]

    init(locations: [FunctionalLocation]) {
        var businessEntitiesByKey: [String: FunctionalLocation] = [:]
        var buildingsByKey: [String: FunctionalLocation] = [:]
        var tradesByKey: [String: FunctionalLocation] = [:]
        // `GROUP BY` keeps one location per key.
        for location in locations {
            if location.buildingCode.isEmpty {
                let key = Self.key(location.countryCode, location.businessEntityCode)
                businessEntitiesByKey[key] = businessEntitiesByKey[key] ?? location
            } else if location.tradeCode.isEmpty {
                let key = Self.key(location.countryCode, location.businessEntityCode, location.buildingCode)
                buildingsByKey[key] = buildingsByKey[key] ?? location
            } else {
                let key = Self.key(
                    location.countryCode, location.businessEntityCode, location.buildingCode, location.tradeCode
                )
                tradesByKey[key] = tradesByKey[key] ?? location
            }
        }
        self.businessEntitiesByKey = businessEntitiesByKey
        self.buildingsByKey = buildingsByKey
        self.tradesByKey = tradesByKey
        businessEntities = businessEntitiesByKey.sorted { $0.key < $1.key }.map(\.value)
        buildings = buildingsByKey.sorted { $0.key < $1.key }.map(\.value)
    }

    func businessEntity(countryCode: String, businessEntityCode: String) -> FunctionalLocation? {
        businessEntitiesByKey[Self.key(countryCode, businessEntityCode)]
    }

    func building(countryCode: String, businessEntityCode: String, buildingCode: String) -> FunctionalLocation? {
        buildingsByKey[Self.key(countryCode, businessEntityCode, buildingCode)]
    }

    func trade(
        countryCode: String,
        businessEntityCode: String,
        buildingCode: String,
        tradeCode: String
    ) -> FunctionalLocation? {
        tradesByKey[Self.key(countryCode, businessEntityCode, buildingCode, tradeCode)]
    }

    private static func key(_ parts: String...) -> String {
        parts.joined(separator: "|")
    }
}
