import Foundation
import Observation

@MainActor
@Observable
final class FacilityDemoViewModel {
    var selection: AppDestination = .overview
    var selectedNotificationID: String?
    var selectedTechnicalPlaceID: String?
    var notifications = MockFacilityData.notifications
    var defects = MockFacilityData.defects
    var drafts = MockFacilityData.drafts
    let technicalPlaces = MockFacilityData.technicalPlaces
    let forms = MockFacilityData.forms

    var selectedNotification: MaintenanceNotification? {
        notifications.first { $0.id == selectedNotificationID }
    }

    var selectedTechnicalPlace: TechnicalPlace? {
        technicalPlaces.first { $0.id == selectedTechnicalPlaceID }
    }

    var openNotifications: Int {
        notifications.filter { $0.status == .open || $0.status == .attention }.count
    }

    func open(_ destination: AppDestination) {
        selection = destination
    }

    func saveManualDraft() {
        drafts.insert(
            DraftWork(
                id: "draft-manual-\(drafts.count + 1)",
                title: "Manual issue report",
                detail: "Local demo entry · Building A",
                savedAt: "Just now",
                status: .draft
            ),
            at: 0
        )
        selection = .drafts
    }

    func finishChecks(for notification: MaintenanceNotification) {
        guard let index = notifications.firstIndex(where: { $0.id == notification.id }) else { return }
        notifications[index].completedChecks = notifications[index].totalChecks
        notifications[index].status = .draft
    }

    func resetDemo() {
        notifications = MockFacilityData.notifications
        defects = MockFacilityData.defects
        drafts = MockFacilityData.drafts
        selectedNotificationID = nil
        selectedTechnicalPlaceID = nil
        selection = .overview
    }
}

private enum MockFacilityData {
    static let notifications: [MaintenanceNotification] = [
        .init(id: "M-31042", title: "Fire door inspection", location: "Building A · Level 02", dueDate: "Today", equipment: "Door group A2", status: .open, completedChecks: 1, totalChecks: 6),
        .init(id: "M-31057", title: "Emergency lighting test", location: "Building C · Level 01", dueDate: "Today", equipment: "Lighting circuit C-11", status: .attention, completedChecks: 3, totalChecks: 8),
        .init(id: "M-30987", title: "Ventilation filter check", location: "Building B · Roof plant", dueDate: "Tomorrow", equipment: "AHU-03", status: .open, completedChecks: 0, totalChecks: 5),
        .init(id: "M-30965", title: "Water meter reading", location: "Utility room · Level -1", dueDate: "29 Aug", equipment: "WM-120", status: .pending, completedChecks: 4, totalChecks: 4)
    ]

    static let defects: [Defect] = [
        .init(id: "D-0284", title: "Emergency exit sign dim", location: "Building C · Corridor 1.04", reportedAt: "Today, 08:45", severity: .attention, description: "Illumination is below the visual inspection threshold."),
        .init(id: "D-0279", title: "Door closer requires adjustment", location: "Building A · Door A2-16", reportedAt: "Yesterday", severity: .pending, description: "Door does not close fully without manual support."),
        .init(id: "D-0274", title: "Filter replacement due", location: "Building B · AHU-03", reportedAt: "27 Aug", severity: .draft, description: "Filter service record prepared for the next maintenance window.")
    ]

    static let drafts: [DraftWork] = [
        .init(id: "S-1008", title: "Emergency lighting test", detail: "Building C · 3 of 8 checks recorded", savedAt: "Today, 09:14", status: .draft),
        .init(id: "S-1007", title: "Issue report · exit sign", detail: "Building C · photo placeholder attached", savedAt: "Today, 08:47", status: .pending),
        .init(id: "S-1003", title: "Safety briefing", detail: "Workshop · signature awaiting completion", savedAt: "Yesterday, 15:32", status: .draft)
    ]

    static let technicalPlaces: [TechnicalPlace] = [
        .init(id: "TP-100", code: "EON-01-A-330-10", title: "Building A · Electrical distribution", detail: "DIN 276 · KG 440", equipmentCount: 8),
        .init(id: "TP-101", code: "EON-01-B-430-03", title: "Building B · Air handling", detail: "DIN 276 · KG 430", equipmentCount: 4),
        .init(id: "TP-102", code: "EON-01-C-470-01", title: "Building C · Safety systems", detail: "DIN 276 · KG 470", equipmentCount: 11),
        .init(id: "TP-103", code: "EON-01-U-410-02", title: "Utility room · Water", detail: "DIN 276 · KG 410", equipmentCount: 6)
    ]

    static let forms: [FacilityForm] = [
        .init(
            id: "briefing",
            titleKey: "forms.briefing.title",
            subtitleKey: "forms.briefing.subtitle",
            coverageKeys: ["forms.briefing.coverage.context", "forms.briefing.coverage.checklist", "forms.briefing.coverage.signatures"],
            symbol: "figure.stand",
            tint: "blue"
        ),
        .init(
            id: "fire",
            titleKey: "forms.fire.title",
            subtitleKey: "forms.fire.subtitle",
            coverageKeys: ["forms.fire.coverage.work", "forms.fire.coverage.measures", "forms.fire.coverage.signatures"],
            symbol: "flame",
            tint: "red"
        ),
        .init(
            id: "electrical",
            titleKey: "forms.electrical.title",
            subtitleKey: "forms.electrical.subtitle",
            coverageKeys: ["forms.electrical.coverage.work", "forms.electrical.coverage.handover", "forms.electrical.coverage.signatures"],
            symbol: "bolt",
            tint: "orange"
        ),
        .init(
            id: "qualification",
            titleKey: "forms.qualification.title",
            subtitleKey: "forms.qualification.subtitle",
            coverageKeys: ["forms.qualification.coverage.context", "forms.qualification.coverage.checklist", "forms.qualification.coverage.signatures"],
            symbol: "checkmark.seal",
            tint: "green"
        )
    ]
}
