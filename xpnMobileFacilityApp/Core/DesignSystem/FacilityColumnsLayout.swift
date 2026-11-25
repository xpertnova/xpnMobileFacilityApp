import SwiftUI

/// Lays its subviews out in rows of equal-width columns.
///
/// It uses the largest count in `columnCounts` whose columns are all at least
/// `minimumColumnWidth` wide, falling back to the smallest count. Unlike an
/// adaptive `LazyVGrid`, the count only steps between the listed values, so
/// four cards become two rows of two rather than a row of three and an orphan.
struct FacilityColumnsLayout: Layout {
    var columnCounts: [Int]
    var minimumColumnWidth: CGFloat
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let arrangement = arrangement(forWidth: proposal.width)
        let rowHeights = rowHeights(for: arrangement, subviews: subviews)
        let height = rowHeights.reduce(0, +) + spacing * CGFloat(rowHeights.count - 1)
        return CGSize(width: arrangement.totalWidth(spacing: spacing), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let arrangement = arrangement(forWidth: bounds.width)
        let rowHeights = rowHeights(for: arrangement, subviews: subviews)

        var y = bounds.minY
        for (row, rowHeight) in rowHeights.enumerated() {
            for column in 0..<arrangement.columns {
                let index = row * arrangement.columns + column
                guard index < subviews.count else { break }
                let x = bounds.minX + CGFloat(column) * (arrangement.columnWidth + spacing)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: arrangement.columnWidth, height: rowHeight)
                )
            }
            y += rowHeight + spacing
        }
    }

    /// The number of columns used when the layout is given `width`.
    func columnCount(forWidth width: CGFloat?) -> Int {
        arrangement(forWidth: width).columns
    }

    private struct Arrangement {
        let columns: Int
        let columnWidth: CGFloat

        func totalWidth(spacing: CGFloat) -> CGFloat {
            columnWidth * CGFloat(columns) + spacing * CGFloat(columns - 1)
        }
    }

    private func arrangement(forWidth width: CGFloat?) -> Arrangement {
        let counts = columnCounts.filter { $0 > 0 }.sorted(by: >)
        let largest = counts.first ?? 1
        guard let width, width.isFinite else {
            return Arrangement(columns: largest, columnWidth: minimumColumnWidth)
        }
        let columns = counts.first { count in
            CGFloat(count) * minimumColumnWidth + CGFloat(count - 1) * spacing <= width
        } ?? counts.last ?? 1
        let columnWidth = max(0, (width - CGFloat(columns - 1) * spacing) / CGFloat(columns))
        return Arrangement(columns: columns, columnWidth: columnWidth)
    }

    private func rowHeights(for arrangement: Arrangement, subviews: Subviews) -> [CGFloat] {
        let proposal = ProposedViewSize(width: arrangement.columnWidth, height: nil)
        return stride(from: 0, to: subviews.count, by: arrangement.columns).map { start in
            subviews[start..<min(start + arrangement.columns, subviews.count)]
                .map { $0.sizeThatFits(proposal).height }
                .max() ?? 0
        }
    }
}
