import SwiftUI

/// The shared "this is loading" frame.
///
/// It reuses the chrome of `FacilityConfirmationDialog` so a busy state looks
/// like the app's own dialogs instead of a bare system spinner, and it covers
/// only the region it is attached to: a screen keeps its header, search field
/// and filters usable while its list reloads underneath.
struct FacilityBusyOverlay: View {
    let titleKey: String
    var cornerRadius: CGFloat = 20

    var body: some View {
        ZStack {
            // A plain colour intercepts touches, so the covered region is
            // inert while it loads.
            Color.black.opacity(0.10)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(FacilityTheme.accent)
                Text(LocalizedStringKey(titleKey))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FacilityTheme.ink)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 360)
            .background(FacilityTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.black.opacity(0.06), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
            .padding(24)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(LocalizedStringKey(titleKey)))
        .accessibilityAddTraits(.updatesFrequently)
    }
}

extension View {
    /// Covers this view with the shared busy frame while `isBusy`.
    ///
    /// The frame appears on the very frame the flag turns true — only its
    /// removal fades — so a list never flashes its empty state first. That
    /// means the flag has to be true from the start as well: a busy state that
    /// is only raised inside `.task` arrives one frame after the empty list.
    func facilityBusy(
        _ isBusy: Bool,
        titleKey: String,
        cornerRadius: CGFloat = 20
    ) -> some View {
        modifier(
            FacilityBusyOverlayModifier(
                isBusy: isBusy,
                titleKey: titleKey,
                cornerRadius: cornerRadius
            )
        )
    }
}

private struct FacilityBusyOverlayModifier: ViewModifier {
    let isBusy: Bool
    let titleKey: String
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if isBusy {
                    FacilityBusyOverlay(titleKey: titleKey, cornerRadius: cornerRadius)
                        .transition(.asymmetric(insertion: .identity, removal: .opacity))
                }
            }
            .animation(
                accessibilityReduceMotion ? nil : .easeOut(duration: 0.18),
                value: isBusy
            )
    }
}
