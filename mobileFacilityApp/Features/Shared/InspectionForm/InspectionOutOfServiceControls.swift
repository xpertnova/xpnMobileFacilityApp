import SwiftUI

/// The header-level "Außer Betrieb" / "Demontiert" status of an inspection
/// form, with its own photo and comment documentation.
///
/// Traced from `BaseFormController.buildDefaultElements`, which builds this
/// exact group — exception icon, label, checkbox, camera, note — into the
/// table header toolbar for every form except TFM1, TFM3, TFM8, TFM9 and
/// TFMQ, and relabels it for TFM5. It is a header property, not a checklist
/// row: its values are posted as `<FORM>-0000-1` and `<FORM>-0000-9B`.
struct InspectionOutOfServiceControls: View {
    let titleKey: String
    let isActive: Bool
    let photoCount: Int
    let isPhotoLimitReached: Bool
    let hasComment: Bool
    /// The status is set but undocumented. `validateFormValues` refuses to
    /// close such a form, so the missing comment is marked here too.
    var isCommentMissing: Bool = false
    let isEnabled: Bool
    let requestStatusChange: () -> Void
    let openPhotos: () -> Void
    let editComment: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(FacilityTheme.red)
                .opacity(isCommentMissing ? 1 : 0)
                .accessibilityLabel(Text("inspection.validation.outOfServiceCommentRequired"))
                .accessibilityHidden(!isCommentMissing)

            Text(LocalizedStringKey(titleKey))
                .font(.body.weight(.semibold))
                .foregroundStyle(FacilityTheme.ink)

            Button(action: requestStatusChange) {
                Image(systemName: isActive ? "checkmark.square.fill" : "square")
                    .font(.title2)
                    .foregroundStyle(isActive ? FacilityTheme.blue : Color.secondary)
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
            .accessibilityLabel(Text(LocalizedStringKey(titleKey)))
            .accessibilityAddTraits(isActive ? .isSelected : [])

            Button(action: openPhotos) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: photoCount == 0 ? "camera" : "camera.fill")
                        .font(.title2)
                        .foregroundStyle(isPhotoLimitReached ? FacilityTheme.red : (isActive ? FacilityTheme.blue : Color.secondary.opacity(0.45)))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(isPhotoLimitReached ? FacilityTheme.red : .gray.opacity(0.25))
                        }

                    if photoCount > 0 {
                        Text(photoCount, format: .number)
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(isPhotoLimitReached ? FacilityTheme.red : FacilityTheme.blue, in: Circle())
                            .offset(x: 3, y: -3)
                    }
                }
            }
            .buttonStyle(.plain)
            // The legacy icons bind `blocked` to `outOfOrderBlocked`: the
            // status documentation is only reachable while the status is set.
            .disabled(!isActive || !isEnabled)
            .accessibilityLabel(Text("notifications.detail.photo"))
            .accessibilityValue(Text(String(format: String(localized: "notifications.detail.photo.count", bundle: .appLanguage), photoCount)))

            Button(action: editComment) {
                Image(systemName: hasComment ? "note.text" : "pencil")
                    .font(.title2)
                    .foregroundStyle(commentForeground)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isCommentMissing ? FacilityTheme.red : .gray.opacity(0.25))
                    }
            }
            .buttonStyle(.plain)
            .disabled(!isActive || !isEnabled)
            .accessibilityLabel(Text("notifications.detail.comment"))
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var commentForeground: Color {
        if isCommentMissing { return FacilityTheme.red }
        if !isActive { return Color.secondary.opacity(0.45) }
        return hasComment ? FacilityTheme.blue : FacilityTheme.ink
    }
}

/// A requested change of the header status, awaiting confirmation.
///
/// Both directions are confirmed in the legacy client
/// (`msg.viewForm.longTextOutOfOrder` / `...BackInOrder`) because either one
/// discards the photos and comments recorded so far.
enum InspectionOutOfServiceTransition: Identifiable, Equatable, Sendable {
    case enable
    case disable

    var id: String { self == .enable ? "enable" : "disable" }

    /// The value the status takes if the technician confirms.
    var isActive: Bool { self == .enable }

    var titleKey: String {
        switch self {
        case .enable: "inspection.outOfService.enable.title"
        case .disable: "inspection.outOfService.disable.title"
        }
    }

    var messageKey: String {
        switch self {
        case .enable: "inspection.outOfService.enable.message"
        case .disable: "inspection.outOfService.disable.message"
        }
    }
}
