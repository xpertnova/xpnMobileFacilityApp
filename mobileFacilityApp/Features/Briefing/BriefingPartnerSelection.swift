import SwiftUI
import UIKit
import PencilKit

struct BriefingPartnerSelectionFrame<Content: View>: View {
    let title: LocalizedStringKey
    let confirmationTitle: LocalizedStringKey
    let isConfirmationDisabled: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @ViewBuilder let content: Content

    init(
        title: LocalizedStringKey = "safetyInstrucForm.addPartnerCompany.dialog.title",
        confirmationTitle: LocalizedStringKey = "safetyInstrucForm.addPartnerCompany.dialog.title.add",
        isConfirmationDisabled: Bool,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.confirmationTitle = confirmationTitle
        self.isConfirmationDisabled = isConfirmationDisabled
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "building.2.crop.circle.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(FacilityTheme.accent)
                    .frame(width: 48, height: 48)
                    .background(FacilityTheme.accentSoft, in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(FacilityTheme.ink)
                    Text("briefing.partnerPicker.subtitle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .background(FacilityTheme.canvas, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("safetyInstrucForm.addPartnerCompany.dialog.title.cancel"))
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .background(FacilityTheme.surface)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(FacilityTheme.canvas)

            HStack(spacing: 12) {
                Spacer()

                Button("safetyInstrucForm.addPartnerCompany.dialog.title.cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .tint(FacilityTheme.ink)

                Button(confirmationTitle, action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .tint(FacilityTheme.accent)
                    .disabled(isConfirmationDisabled)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
            .background(FacilityTheme.surface)
            .overlay(alignment: .top) { Divider().opacity(0.7) }
        }
        .background(FacilityTheme.surface)
    }
}

/// Presents briefing value help in the same elevated-card treatment used by the
/// landscape shell. Content remains shared by partner and business-entity flows.
struct LegacyBriefingPartnerEditorOverlay<Content: View>: View {
    let isPresented: Bool
    @ViewBuilder let content: Content

    init(
        isPresented: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.isPresented = isPresented
        self.content = content()
    }

    var body: some View {
        if isPresented {
            GeometryReader { geometry in
                ZStack {
                    Color.black.opacity(0.28)
                        .ignoresSafeArea()

                    content
                        .frame(
                            width: min(max(geometry.size.width - 92, 0), 1_180),
                            height: min(max(geometry.size.height - 32, 0), 840)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: .black.opacity(0.20), radius: 28, y: 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            .zIndex(10)
        }
    }
}

/// The legacy modal shell used while a worker or partner signs a briefing.
struct LegacyBriefingSignatureOverlay<Content: View>: View {
    let isPresented: Bool
    @ViewBuilder let content: Content

    init(isPresented: Bool, @ViewBuilder content: () -> Content) {
        self.isPresented = isPresented
        self.content = content()
    }

    var body: some View {
        if isPresented {
            GeometryReader { geometry in
                ZStack {
                    Color.black.opacity(0.55).ignoresSafeArea()
                    content
                        .frame(
                            // The legacy briefing sheet is a compact, centered iPad
                            // dialog. Keeping this limit here ensures every form that
                            // uses the shared sheet has the same signing affordance.
                            width: min(max(geometry.size.width - 64, 0), 860),
                            height: min(max(geometry.size.height - 70, 0), 430)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .shadow(color: .black.opacity(0.30), radius: 12, y: 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            .zIndex(20)
        }
    }
}

/// The exact title, canvas, and action-bar treatment from the legacy briefing
/// signature dialog. Forms provide only their signer label and completion work.
struct LegacyBriefingSignatureDialog: View {
    let signerTitle: LocalizedStringKey
    let onSave: (Data) -> Void
    let onCancel: () -> Void

    @State private var drawing = PKDrawing()

    var body: some View {
        VStack(spacing: 0) {
            Text("flEQ.briefing.signature.instructions")
                .font(.title3)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(Color(uiColor: .systemBackground))
                .overlay(alignment: .bottom) { Divider() }

            VStack(alignment: .leading, spacing: 8) {
                Text(signerTitle)
                    .font(.title3)
                    .foregroundStyle(.primary)

                BriefingSignatureCanvas(
                    drawing: $drawing,
                    backgroundColor: .systemGray4
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemBackground))

            HStack(spacing: 30) {
                Spacer()
                Button("flEQ.briefing.signature.clear") { drawing = PKDrawing() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .disabled(drawing.bounds.isEmpty)
                Button("flEQ.briefing.signature.confirm") {
                    guard let signatureData else { return }
                    onSave(signatureData)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .disabled(drawing.bounds.isEmpty)
                Button("app.button.cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 28)
            .frame(minHeight: 58)
            .background(Color(uiColor: .systemBackground))
            .overlay(alignment: .top) { Divider() }
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
    }

    private var signatureData: Data? {
        BriefingSignatureRasterizer.pngData(from: drawing)
    }
}

/// The complete legacy table used for partner-company value help. Both
/// briefing forms provide their data through this neutral presentation model,
/// keeping the header controls, filters, sorting and selection styling equal.
struct BriefingPartnerSelection: Identifiable, Equatable, Sendable {
    let id: String
    let client: String
    let function: String
    let name: String
    let searchTerm1: String
    let searchTerm2: String
}

struct BriefingPartnerSelectionTable: View {
    let partners: [BriefingPartnerSelection]
    @Binding var selectedPartnerID: String?

    @State private var sort = Sort.nameAscending
    @State private var activeColumnMenu: Column?
    @State private var columnFilters: [Column: String] = [:]

    var body: some View {
        GeometryReader { geometry in
            let widths = ColumnWidths(totalWidth: geometry.size.width)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    columnHeader(Text(verbatim: "MANDT"), width: widths.client, column: .client)
                    columnHeader(Text("externalCompany.parvw"), width: widths.function, column: .function)
                    columnHeader(Text("externalCompany.name"), width: widths.name, column: .name)
                    columnHeader(Text("externalCompany.SORT1"), width: widths.searchTerm1, column: .searchTerm1)
                    columnHeader(Text("externalCompany.SORT2"), width: widths.searchTerm2, column: .searchTerm2)
                }
                .background(FacilityTheme.canvas)

                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(displayedPartners) { partner in
                            Button {
                                selectedPartnerID = partner.id
                            } label: {
                                partnerRow(partner, widths: widths)
                                    .background(
                                        selectedPartnerID == partner.id
                                            ? FacilityTheme.accentSoft
                                            : FacilityTheme.surface
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(partner.name))
                            .accessibilityValue(
                                selectedPartnerID == partner.id
                                    ? Text("briefing.partnerPicker.selected")
                                    : Text("")
                            )
                        }

                        ForEach(0..<max(0, 9 - displayedPartners.count), id: \.self) { _ in
                            emptyRow(widths: widths)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.visible)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(FacilityTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.black.opacity(0.10))
            }
        }
    }

    private var displayedPartners: [BriefingPartnerSelection] {
        Self.filteredPartners(partners: partners, filters: columnFilters, sort: sort)
    }

    static func filteredPartners(
        partners: [BriefingPartnerSelection],
        filters: [Column: String],
        sort: Sort
    ) -> [BriefingPartnerSelection] {
        return partners
            .filter { partner in
                Column.allCases.allSatisfy { column in
                    let query = filters[column, default: ""]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return query.isEmpty || column.value(from: partner).localizedCaseInsensitiveContains(query)
                }
            }
            .sorted(by: sort.areInIncreasingOrder)
    }

    private func columnHeader(_ title: Text, width: CGFloat, column: Column) -> some View {
        HStack(spacing: 6) {
            title
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Spacer(minLength: 4)
            Button {
                activeColumnMenu = activeColumnMenu == column ? nil : column
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .foregroundStyle(hasFilter(for: column) ? Color.accentColor : .secondary)
                    .frame(width: 28, height: 44)
            }
            .buttonStyle(.plain)
            .facilityPopover(isPresented: columnMenuBinding(for: column), arrowEdge: .top) {
                columnMenu(column)
            }
        }
        .padding(.leading, 12)
        .frame(width: width)
        .frame(minHeight: 45)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color(uiColor: .separator)).frame(width: 0.5)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(uiColor: .separator)).frame(height: 0.5)
        }
    }

    private func columnMenu(_ column: Column) -> some View {
        VStack(spacing: 0) {
            menuButton("flEQ.briefing.partner.sort.ascending") {
                sort = column.ascendingSort
                activeColumnMenu = nil
            }
            Divider()
            menuButton("flEQ.briefing.partner.sort.descending") {
                sort = column.ascendingSort.descending
                activeColumnMenu = nil
            }
            Divider()
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal.decrease").foregroundStyle(.secondary)
                Text("flEQ.briefing.partner.filter")
                TextField("", text: filterBinding(for: column))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 8)
                    .frame(width: 170, height: 32)
                    .background(Color(uiColor: .systemBackground))
                    .overlay { RoundedRectangle(cornerRadius: 2).stroke(Color(uiColor: .separator), lineWidth: 1) }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
        }
        .font(.body)
        .frame(width: 350)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func menuButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: "line.3.horizontal.decrease")
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
    }

    private func columnMenuBinding(for column: Column) -> Binding<Bool> {
        Binding(
            get: { activeColumnMenu == column },
            set: { isPresented in
                if !isPresented, activeColumnMenu == column { activeColumnMenu = nil }
            }
        )
    }

    private func filterBinding(for column: Column) -> Binding<String> {
        Binding(
            get: { columnFilters[column, default: ""] },
            set: { columnFilters[column] = $0 }
        )
    }

    private func hasFilter(for column: Column) -> Bool {
        !columnFilters[column, default: ""].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func partnerRow(_ partner: BriefingPartnerSelection, widths: ColumnWidths) -> some View {
        HStack(spacing: 0) {
            cell(partner.client, width: widths.client)
            cell(partner.function, width: widths.function)
            cell(partner.name, width: widths.name)
            cell(partner.searchTerm1, width: widths.searchTerm1)
            cell(partner.searchTerm2, width: widths.searchTerm2)
        }
    }

    private func emptyRow(widths: ColumnWidths) -> some View {
        HStack(spacing: 0) {
            cell("", width: widths.client); cell("", width: widths.function)
            cell("", width: widths.name); cell("", width: widths.searchTerm1)
            cell("", width: widths.searchTerm2)
        }
        .accessibilityHidden(true)
    }

    private func cell(_ value: String, width: CGFloat) -> some View {
        Text(value)
            .foregroundStyle(.primary)
            .lineLimit(2)
            .padding(.horizontal, 12)
            .frame(width: width, alignment: .leading)
            .frame(minHeight: 41)
            .overlay(alignment: .trailing) {
                Rectangle().fill(Color(uiColor: .separator)).frame(width: 0.5)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color(uiColor: .separator)).frame(height: 0.5)
            }
    }

    private struct ColumnWidths {
        let client: CGFloat; let function: CGFloat; let name: CGFloat
        let searchTerm1: CGFloat; let searchTerm2: CGFloat
        init(totalWidth: CGFloat) {
            client = totalWidth * 0.14; function = totalWidth * 0.14; name = totalWidth * 0.24
            searchTerm1 = totalWidth * 0.24
            searchTerm2 = totalWidth - client - function - name - searchTerm1
        }
    }

    enum Column: CaseIterable, Hashable {
        case client, function, name, searchTerm1, searchTerm2
        var ascendingSort: Sort {
            switch self {
            case .client: .clientAscending; case .function: .functionAscending
            case .name: .nameAscending; case .searchTerm1: .searchTerm1Ascending
            case .searchTerm2: .searchTerm2Ascending
            }
        }
        func value(from partner: BriefingPartnerSelection) -> String {
            switch self {
            case .client: partner.client; case .function: partner.function; case .name: partner.name
            case .searchTerm1: partner.searchTerm1; case .searchTerm2: partner.searchTerm2
            }
        }
    }

    enum Sort: Equatable {
        case clientAscending, clientDescending, functionAscending, functionDescending
        case nameAscending, nameDescending, searchTerm1Ascending, searchTerm1Descending
        case searchTerm2Ascending, searchTerm2Descending
        var descending: Self {
            switch self {
            case .clientAscending: .clientDescending; case .functionAscending: .functionDescending
            case .nameAscending: .nameDescending; case .searchTerm1Ascending: .searchTerm1Descending
            case .searchTerm2Ascending: .searchTerm2Descending
            default: self
            }
        }
        func areInIncreasingOrder(_ lhs: BriefingPartnerSelection, _ rhs: BriefingPartnerSelection) -> Bool {
            let pair: (String, String, Bool)
            switch self {
            case .clientAscending: pair = (lhs.client, rhs.client, false); case .clientDescending: pair = (lhs.client, rhs.client, true)
            case .functionAscending: pair = (lhs.function, rhs.function, false); case .functionDescending: pair = (lhs.function, rhs.function, true)
            case .nameAscending: pair = (lhs.name, rhs.name, false); case .nameDescending: pair = (lhs.name, rhs.name, true)
            case .searchTerm1Ascending: pair = (lhs.searchTerm1, rhs.searchTerm1, false); case .searchTerm1Descending: pair = (lhs.searchTerm1, rhs.searchTerm1, true)
            case .searchTerm2Ascending: pair = (lhs.searchTerm2, rhs.searchTerm2, false); case .searchTerm2Descending: pair = (lhs.searchTerm2, rhs.searchTerm2, true)
            }
            let comparison = pair.0.localizedStandardCompare(pair.1)
            return pair.2 ? comparison == .orderedDescending : comparison == .orderedAscending
        }
    }
}

struct BriefingSignatureCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var backgroundColor: UIColor = .white
    var onDrawingChanged: ((PKDrawing) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(drawing: $drawing, onDrawingChanged: onDrawingChanged)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .black, width: 3)
        canvas.backgroundColor = backgroundColor
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.onDrawingChanged = onDrawingChanged
        guard canvas.drawing != drawing else { return }
        canvas.drawing = drawing
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        private var drawing: Binding<PKDrawing>
        var onDrawingChanged: ((PKDrawing) -> Void)?

        init(
            drawing: Binding<PKDrawing>,
            onDrawingChanged: ((PKDrawing) -> Void)?
        ) {
            self.drawing = drawing
            self.onDrawingChanged = onDrawingChanged
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let completedDrawing = canvasView.drawing
            drawing.wrappedValue = completedDrawing
            // Apple can deliver the final drawing change after the interaction
            // ends (for example, when final Pencil pressure data arrives). This
            // is the first point at which the signature must be persisted.
            onDrawingChanged?(completedDrawing)
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            // Keep SwiftUI's local drawing current. Do not serialize here:
            // PencilKit may not yet have committed the final stroke.
            drawing.wrappedValue = canvasView.drawing
        }
    }
}

/// Converts a tightly cropped PencilKit drawing into a fixed canvas. Every
/// signature then has identical source dimensions when the PDF renderer scales
/// it into a signature cell, preserving one visible pen thickness.
enum BriefingSignatureRasterizer {
    static let canvasSize = CGSize(width: 1_400, height: 300)

    static func pngData(from drawing: PKDrawing) -> Data? {
        let inkBounds = drawing.bounds.insetBy(dx: -12, dy: -12)
        guard !inkBounds.isEmpty else { return nil }

        let croppedSignature = drawing.image(from: inkBounds, scale: 2)
        return standardizedPNGData(from: croppedSignature)
    }

    static func standardizedPNGData(from croppedSignature: UIImage) -> Data? {
        guard croppedSignature.size.width > 0,
              croppedSignature.size.height > 0,
              croppedSignature.size.width <= canvasSize.width,
              croppedSignature.size.height <= canvasSize.height
        else {
            return nil
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = 2
        let image = UIGraphicsImageRenderer(size: canvasSize, format: format).image { _ in
            croppedSignature.draw(
                in: CGRect(
                    x: (canvasSize.width - croppedSignature.size.width) / 2,
                    y: (canvasSize.height - croppedSignature.size.height) / 2,
                    width: croppedSignature.size.width,
                    height: croppedSignature.size.height
                )
            )
        }
        return image.pngData()
    }
}

extension View {
    func briefingFieldChrome(invalid: Bool) -> some View {
        padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        invalid ? FacilityTheme.red : Color.black.opacity(0.11),
                        lineWidth: invalid ? 2 : 1
                    )
            }
            .shadow(color: Color.black.opacity(0.025), radius: 3, y: 1)
    }

    func briefingReadOnlyValue() -> some View {
        frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .padding(.horizontal, 14)
            .background(FacilityTheme.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.black.opacity(0.07), lineWidth: 1)
            }
    }
}
