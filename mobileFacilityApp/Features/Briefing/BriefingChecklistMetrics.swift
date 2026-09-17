import CoreGraphics

/// Column widths of the briefing and proof-of-qualification checklists.
///
/// The item text is the only column that wraps, so on a compact window the
/// fixed columns give up width to keep it readable: beside a narrow window's
/// rail the regular columns would leave the text under 100 pt. The regular
/// widths are the original table.
struct BriefingChecklistMetrics: Equatable {
    let numberColumn: CGFloat
    /// One half of the answer control; the "Nein" and "Ja" header labels
    /// each sit over one half.
    let answerHalfColumn: CGFloat
    /// The "//" between the two answer labels in the header.
    let answerSeparatorColumn: CGFloat
    let documentColumn: CGFloat
    let informationColumn: CGFloat
    let commentColumn: CGFloat

    var answerColumn: CGFloat { answerHalfColumn * 2 + answerSeparatorColumn }

    init(layout: FacilityLayoutMetrics) {
        if layout.isCompact {
            numberColumn = 44
            answerHalfColumn = 70
            answerSeparatorColumn = 24
            documentColumn = 40
            informationColumn = 48
            commentColumn = 64
        } else {
            numberColumn = 70
            answerHalfColumn = 96
            answerSeparatorColumn = 28
            documentColumn = 54
            informationColumn = 64
            commentColumn = 96
        }
    }
}
