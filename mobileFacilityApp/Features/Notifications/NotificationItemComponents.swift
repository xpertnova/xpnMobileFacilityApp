import SwiftUI

/// Shared photo button with attachment counter badge reused across notification inspection checklists.
struct NotificationPhotoButton: View {
    let count: Int
    var isLimitReached = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: count == 0 ? "camera" : "camera.fill")
                    .foregroundStyle(isLimitReached ? FacilityTheme.red : (count == 0 ? FacilityTheme.ink : FacilityTheme.blue))
                    .frame(width: 44, height: 44)
                    .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(isLimitReached ? FacilityTheme.red : .gray.opacity(0.25)))

                if count > 0 {
                    Text(count, format: .number)
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(isLimitReached ? FacilityTheme.red : FacilityTheme.blue, in: Circle())
                        .offset(x: 5, y: -5)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("notifications.detail.photo"))
        .accessibilityValue(Text(String(format: String(localized: "notifications.detail.photo.count", bundle: .appLanguage), count)))
    }
}

/// Shared info button with circular icon and popover presentation reused across notification checklists.
struct NotificationInfoButton: View {
    let information: String
    @State private var isShowingInformation = false

    var body: some View {
        Group {
            if information.isEmpty {
                Image(systemName: "info.circle")
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, height: 28)
            } else {
                Button {
                    isShowingInformation = true
                } label: {
                    Image(systemName: "info.circle.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(FacilityTheme.blue)
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("notifications.detail.showInformation"))
                .popover(isPresented: $isShowingInformation) {
                    NotificationInfoPopoverContent(information: information)
                }
            }
        }
    }
}

/// Shared info frame displayed in the info button popover.
struct NotificationInfoPopoverContent: View {
    let information: String

    var body: some View {
        Text(information)
            .font(.body)
            .padding(20)
            .frame(width: 360, alignment: .leading)
    }
}

/// Shared metadata row for notification details cards.
struct NotificationMetadataRow: View {
    let titleKey: String
    let value: String
    var monospaced: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 24) {
            Text(LocalizedStringKey(titleKey))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 180, alignment: .leading)

            Text(value)
                .font(monospaced ? .subheadline.monospaced() : .body)
                .foregroundStyle(FacilityTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}
