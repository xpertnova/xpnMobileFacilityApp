import SwiftUI

enum FacilityTheme {
    static let canvas = Color(red: 0.95, green: 0.95, blue: 0.97)
    static let sidebar = Color(red: 0.965, green: 0.965, blue: 0.98)
    static let surface = Color.white
    static let ink = Color(red: 0.04, green: 0.12, blue: 0.20)
    static let muted = Color.secondary
    static let accent = Color(red: 0.05, green: 0.56, blue: 0.39)
    static let accentSoft = Color(red: 0.90, green: 0.97, blue: 0.94)
    static let navy = Color(red: 0.04, green: 0.12, blue: 0.20)
    static let blue = Color(red: 0.0, green: 0.43, blue: 0.85)
    /// `--purple` / `--purple-soft` of the design reference (#5e5ce6 on
    /// #f0ecfd), used for DIN-276 cost groups and equipment.
    static let purple = Color(red: 0.369, green: 0.361, blue: 0.902)
    static let purpleSoft = Color(red: 0.941, green: 0.925, blue: 0.992)
    /// Neutral tile fill for the structural levels of the hierarchy.
    static let neutralSoft = Color(red: 0.463, green: 0.463, blue: 0.502).opacity(0.12)
    static let orange = Color(red: 0.87, green: 0.43, blue: 0.0)
    static let red = Color(red: 0.83, green: 0.18, blue: 0.16)
    /// The dimmed backdrop behind every centered dialog and picker.
    static let dialogScrim = Color.black.opacity(0.32)
}

extension View {
    func facilityCard(padding cardPadding: CGFloat = 18) -> some View {
        self.padding(cardPadding)
            .background(FacilityTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.black.opacity(0.055), radius: 10, y: 4)
    }
}

struct StatusPill: View {
    let status: WorkStatus

    private var tint: Color {
        switch status {
        case .open: FacilityTheme.blue
        case .draft: FacilityTheme.orange
        case .pending: FacilityTheme.accent
        case .attention: FacilityTheme.red
        case .complete: FacilityTheme.accent
        case .closedLocally: FacilityTheme.accent
        }
    }

    var body: some View {
        Text(LocalizedStringKey(status.titleKey))
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

struct OfflineStatusPill: View {
    let status: OfflineWorkStatus

    private var tint: Color {
        switch status {
        case .draft: FacilityTheme.orange
        case .pendingSynchronization, .synchronizing: FacilityTheme.blue
        case .synchronized: FacilityTheme.accent
        case .failed, .conflict: FacilityTheme.red
        }
    }

    var body: some View {
        Text(LocalizedStringKey(status.titleKey))
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

struct DemoBadge: View {
    var body: some View {
        Label("demo.badge", systemImage: "theatermasks.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(FacilityTheme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(FacilityTheme.accentSoft, in: Capsule())
    }
}
