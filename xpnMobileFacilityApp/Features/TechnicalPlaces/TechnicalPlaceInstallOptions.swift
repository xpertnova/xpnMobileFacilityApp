import Foundation

/// Whether one of the "Equipment einbauen" forms can be used at a technical
/// place, decided before the technician opens it.
enum TechnicalPlaceInstallAvailability: Equatable, Sendable {
    case available
    /// SAP has creation data, but none at this place — for TFM5, no ladder
    /// trade (`TPGSG`, carried here) in the place's building.
    case noContext(trade: String)
    /// No creation data at all for this worker: no template, no segment map
    /// entry, or the cache could not be read.
    case noData
    /// The place carries no business entity (`TPWEH`), so no form can
    /// address it.
    case noBusinessEntity

    var isAvailable: Bool { self == .available }
}

/// What "Equipment einbauen" offers at one technical place: the TFM5 mobile
/// ladder and the TFM7 subdistribution form, each only where the place has a
/// creation context of its own.
struct TechnicalPlaceInstallOptions: Equatable, Sendable {
    let mobileLadder: TechnicalPlaceInstallAvailability
    let subdistribution: TechnicalPlaceInstallAvailability

    var isAnyAvailable: Bool { mobileLadder.isAvailable || subdistribution.isAvailable }

    /// A place inside a building needs a context in that very building — the
    /// form never falls back to another one. A place above building level
    /// (an outdoor area) is served by any context of its business entity.
    static func availability(
        at anchor: TechnicalPlaceCreationAnchor?,
        among contexts: [(country: String, businessEntity: String, building: String)],
        trade: String = ""
    ) -> TechnicalPlaceInstallAvailability {
        guard !contexts.isEmpty else { return .noData }
        guard let anchor else { return .noBusinessEntity }
        let isServed = contexts.contains {
            anchor.buildingCode.isEmpty
                ? anchor.matches(countryCode: $0.country, businessEntity: $0.businessEntity)
                : anchor.matches(countryCode: $0.country, businessEntity: $0.businessEntity, building: $0.building)
        }
        return isServed ? .available : .noContext(trade: trade)
    }
}
