import Foundation

enum TechnicalObjectDemoData {
    static let cachedData = SAPCachedData(
        notifications: notifications,
        workerProfile: nil,
        technicalObjects: objects,
        metadata: SAPCacheMetadata(sapWorkerID: "demo", lastSuccessfulRefreshAt: Date())
    )

    static let objects: [TechnicalObjectNode] = TechnicalObjectHierarchyNormalizer.normalize([
        location("UN01", "Musterunternehmen", parent: nil),
        location("UN01-ST01", "Hauptstandort", parent: "UN01"),
        location("UN01-ST01-BG01", "Bürogebäude", parent: "UN01-ST01"),
        location("UN01-ST01-BG01-TECH", "Technikzentralen", parent: "UN01-ST01-BG01"),
        location("UN01-ST01-BG01-TECH-420", "Wärmeversorgungsanlagen", parent: "UN01-ST01-BG01-TECH", din: "420"),
        location("UN01-ST01-BG01-TECH-420-Z", "Zentrale Wärmeversorgung", parent: "UN01-ST01-BG01-TECH-420", din: "420", status: "In Betrieb"),
        equipment("EQ-100040", "Gas-Brennwertkessel 320 kW", location: "UN01-ST01-BG01-TECH-420-Z", manufacturer: "Viessmann", type: "Vitocrossal", serial: "VIE-VC-5512", din: "420"),
        equipment("EQ-100041", "Heizungsumwälzpumpe HP-1", location: "UN01-ST01-BG01-TECH-420-Z", manufacturer: "Grundfos", type: "MAGNA3", serial: "GR-4421", din: "420"),
        // A system-level place with no equipment under it, so the demo has a
        // technical place whose detail actually opens — every other branch
        // here ends in equipment. Taken from the reference tree, which gives
        // this system `equipment: []` and no `EQMAP` entry.
        location("UN01-ST01-BG01-EG00", "Erdgeschoss", parent: "UN01-ST01-BG01"),
        location("UN01-ST01-BG01-EG00-300", "Bauwerk – Baukonstruktionen", parent: "UN01-ST01-BG01-EG00", din: "300"),
        location("UN01-ST01-BG01-EG00-300-BAU1", "Baukonstruktion Erdgeschoss", parent: "UN01-ST01-BG01-EG00-300", din: "300", status: "In Betrieb"),
        location("UN01-ST01-PH01", "Produktion", parent: "UN01-ST01"),
        location("UN01-ST01-PH01-TECH", "Technikzentralen", parent: "UN01-ST01-PH01"),
        location("UN01-ST01-PH01-TECH-440", "Elektrotechnik", parent: "UN01-ST01-PH01-TECH", din: "440"),
        equipment("EQ-100090", "Hauptverteilung NSHV", location: "UN01-ST01-PH01-TECH-440", manufacturer: "Siemens", type: "SIVACON", serial: "SI-99218", din: "440")
    ])

    static let notifications = [
        SAPNotificationSummary(
            id: "M-31042", client: "100", title: "Jährliche Kesselprüfung",
            functionalLocationID: "UN01-ST01-BG01-TECH-420-Z", functionalLocationName: "Zentrale Wärmeversorgung",
            equipmentID: "EQ-100040", startDate: "2026-10-01", endDate: "2026-10-01",
            systemStatus: "Offen", userStatus: "", rawPayloadJSON: "{}"
        )
    ]

    /// `TPWEH` / `TPGEB` as `DemoMobileLadderCreationProvider` declares them:
    /// the company is the business entity and the third segment the building.
    /// Kept in step with that provider so the demo behaves like production.
    private static func location(_ id: String, _ name: String, parent: String?, din: String? = nil, status: String = "") -> TechnicalObjectNode {
        let segments = id.split(separator: "-").map(String.init)
        return TechnicalObjectNode(
            reference: .init(kind: .functionalLocation, objectID: id),
            parent: parent.map { .init(kind: .functionalLocation, objectID: $0) }, client: "100", name: name,
            functionalLocationID: id, countryCode: "DE", locationCode: "ST01", cityName: "Essen",
            hierarchyLevel: "", category: "", structureIndicator: "TPL",
            businessEntityCode: segments.first ?? "",
            buildingCode: segments.count > 2 ? segments[2] : "",
            tradeCode: din ?? "",
            equipmentCategory: "", equipmentType: "", manufacturer: "", modelType: "", serialNumber: "",
            systemStatus: status, userStatus: "", dinGroup: din,
            sourceFingerprint: TechnicalObjectFingerprint.make([id, name, status, din ?? ""]),
            directChildCount: 0, directEquipmentCount: 0, isUnassigned: false, isSynthetic: false
        )
    }

    private static func equipment(_ id: String, _ name: String, location: String, manufacturer: String, type: String, serial: String, din: String) -> TechnicalObjectNode {
        TechnicalObjectNode(
            reference: .init(kind: .equipment, objectID: id),
            parent: .init(kind: .functionalLocation, objectID: location), client: "100", name: name,
            functionalLocationID: location, countryCode: "DE", locationCode: "ST01", cityName: "Essen",
            hierarchyLevel: "", category: "", structureIndicator: "",
            equipmentCategory: "M", equipmentType: "", manufacturer: manufacturer, modelType: type, serialNumber: serial,
            systemStatus: "In Betrieb", userStatus: "", dinGroup: din,
            sourceFingerprint: TechnicalObjectFingerprint.make([id, name, location, manufacturer, type, serial, din]),
            directChildCount: 0, directEquipmentCount: 0, isUnassigned: false, isSynthetic: false
        )
    }
}
