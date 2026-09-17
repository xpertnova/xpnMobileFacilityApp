import SwiftUI

/// Places a main view and a side column next to each other while the main view
/// keeps at least `minimumMainWidth`, and otherwise stacks the side column
/// under the main view.
///
/// Both arrangements lay out the same subviews, so switching keeps their
/// identity: a text field keeps its focus when the window or the sidebar
/// changes width, which `ViewThatFits` or an `if` on a measured width would
/// not. Expects two subviews; any other count is stacked.
struct FacilitySideColumnLayout: Layout {
    /// Width of the side column when side by side; `nil` uses its ideal width.
    var sideWidth: CGFloat?
    var minimumMainWidth: CGFloat
    var spacing: CGFloat
    /// Vertical alignment of the two columns when side by side.
    var alignment: VerticalAlignment = .top

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(forWidth: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrangement(forWidth: proposal.width ?? bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, arrangement.frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    /// Whether the columns sit side by side when the layout is given `width`.
    func isSideBySide(forWidth width: CGFloat?, sideIdealWidth: CGFloat = 0) -> Bool {
        guard let width, width.isFinite else { return true }
        return width - (sideWidth ?? sideIdealWidth) - spacing >= minimumMainWidth
    }

    private func arrangement(forWidth width: CGFloat?, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        let finiteWidth = width.flatMap { $0.isFinite ? $0 : nil }

        if subviews.count == 2 {
            let side = sideWidth ?? subviews[1].sizeThatFits(.unspecified).width
            if isSideBySide(forWidth: finiteWidth, sideIdealWidth: side) {
                let totalWidth = finiteWidth ?? minimumMainWidth + spacing + side
                let mainWidth = totalWidth - spacing - side
                let mainHeight = subviews[0].sizeThatFits(ProposedViewSize(width: mainWidth, height: nil)).height
                let sideHeight = subviews[1].sizeThatFits(ProposedViewSize(width: side, height: nil)).height
                let height = max(mainHeight, sideHeight)
                return (
                    [
                        CGRect(x: 0, y: offset(for: mainHeight, in: height), width: mainWidth, height: mainHeight),
                        CGRect(x: mainWidth + spacing, y: offset(for: sideHeight, in: height), width: side, height: sideHeight)
                    ],
                    CGSize(width: totalWidth, height: height)
                )
            }
        }

        let totalWidth = finiteWidth ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        var frames: [CGRect] = []
        var y: CGFloat = 0
        for subview in subviews {
            let height = subview.sizeThatFits(ProposedViewSize(width: totalWidth, height: nil)).height
            frames.append(CGRect(x: 0, y: y, width: totalWidth, height: height))
            y += height + spacing
        }
        return (frames, CGSize(width: totalWidth, height: max(0, y - spacing)))
    }

    private func offset(for height: CGFloat, in rowHeight: CGFloat) -> CGFloat {
        alignment == .center ? (rowHeight - height) / 2 : 0
    }
}
