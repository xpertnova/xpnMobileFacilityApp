import SwiftUI

/// Shared status documentation controls for technical-place creation forms.
/// A maintenance status is an explicit checkbox transition, not an app
/// preference, and the related photo/comment actions are usable only while
/// that status is active.
struct TechnicalPlaceStatusControls: View {
    let title: LocalizedStringKey
    let isStatusActive: Bool
    let photoCount: Int
    let hasComment: Bool
    let isEnabled: Bool
    let requestStatusChange: () -> Void
    let openPhotos: () -> Void
    let editComment: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(FacilityTheme.ink)

            Button(action: requestStatusChange) {
                Image(systemName: isStatusActive ? "checkmark.square.fill" : "square")
                    .font(.title2)
                    .foregroundStyle(isStatusActive ? FacilityTheme.blue : Color.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(.gray.opacity(0.25))
                    }
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .accessibilityLabel(Text(title))
            .accessibilityAddTraits(isStatusActive ? .isSelected : [])

            Button(action: openPhotos) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: photoCount == 0 ? "camera" : "camera.fill")
                        .font(.title2)
                        .foregroundStyle(isStatusActive ? FacilityTheme.blue : Color.secondary.opacity(0.45))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(.gray.opacity(0.25))
                        }

                    if photoCount > 0 {
                        Text(photoCount, format: .number)
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(FacilityTheme.blue, in: Circle())
                            .offset(x: 3, y: -3)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!isStatusActive || !isEnabled)
            .accessibilityLabel(Text("notifications.detail.photo"))
            .accessibilityValue(Text(String(format: String(localized: "notifications.detail.photo.count"), photoCount)))

            Button(action: editComment) {
                Image(systemName: hasComment ? "note.text" : "pencil")
                    .font(.title2)
                    .foregroundStyle(isStatusActive ? FacilityTheme.blue : Color.secondary.opacity(0.45))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(.gray.opacity(0.25))
                    }
            }
            .buttonStyle(.plain)
            .disabled(!isStatusActive || !isEnabled)
            .accessibilityLabel(Text("notifications.detail.comment"))
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}
