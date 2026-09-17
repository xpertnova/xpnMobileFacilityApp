import SwiftUI

extension View {
    /// Frames the content of a centered dialog card.
    ///
    /// The card keeps `width` while the space it is shown in allows, and stays
    /// at least the layout's dialog margin away from that space's edges. When
    /// the content is taller than the space left, for example with the keyboard
    /// up on an iPad mini, it scrolls inside the card instead of running off
    /// screen. Apply the card's background, border and shadow after this.
    func facilityDialogFrame(
        width: CGFloat,
        padding: CGFloat,
        alignment: Alignment = .leading
    ) -> some View {
        modifier(FacilityDialogFrameModifier(width: width, padding: padding, alignment: alignment))
    }
}

private struct FacilityDialogFrameModifier: ViewModifier {
    let width: CGFloat
    let padding: CGFloat
    let alignment: Alignment

    @Environment(\.facilityLayout) private var layout

    func body(content: Content) -> some View {
        FacilityDialogSizingLayout(preferredWidth: width, margin: layout.dialogMargin) {
            ScrollView(.vertical) {
                content
                    .padding(layout.dialogPadding(padding))
                    .frame(maxWidth: .infinity, alignment: alignment)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

/// Gives its single subview the preferred width and the subview's own ideal
/// height, each capped to the proposed space less `margin` on both sides.
///
/// A vertical `ScrollView` reports its content's height as its ideal height,
/// so the card hugs short content and only scrolls when it has to.
struct FacilityDialogSizingLayout: Layout {
    var preferredWidth: CGFloat
    var margin: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let width = capped(preferredWidth, to: proposal.width)
        let idealHeight = subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        return CGSize(width: width, height: capped(idealHeight, to: proposal.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }

    private func capped(_ length: CGFloat, to available: CGFloat?) -> CGFloat {
        guard let available, available.isFinite else { return length }
        return max(0, min(length, available - margin * 2))
    }
}

#if DEBUG
/// An iPad mini with the keyboard up leaves roughly this much room.
#Preview("Dialog, iPad mini with keyboard", traits: .fixedLayout(width: 1_133, height: 330)) {
    ZStack {
        Color.black.opacity(0.32)
        FacilityConfirmationDialog(
            titleKey: "inspection.masterData.error.title",
            messageKey: "inspection.masterData.error.message",
            symbol: "exclamationmark.circle",
            tint: FacilityTheme.red,
            actions: [FacilityDialogAction(titleKey: "common.ok", emphasis: .primary) {}],
            cancel: {}
        )
    }
    .facilityLayoutRoot()
}
#endif
