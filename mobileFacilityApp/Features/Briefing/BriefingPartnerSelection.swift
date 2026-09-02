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
                            height: min(max(geometry.size.height - 76, 0), 760)
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
        guard !drawing.bounds.isEmpty else { return nil }
        return drawing.image(from: drawing.bounds.insetBy(dx: -12, dy: -12), scale: 2).pngData()
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
    var emptyRowCount = 0

    @State private var sort = Sort.nameAscending
    @State private var activeColumnMenu: Column?
    @State private var columnFilters: [Column: String] = [:]
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("briefing.partnerPicker.search", text: $searchText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(FacilityTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.black.opacity(0.09))
                }

                Menu {
                    Button("notifications.sort.ascending") { sort = .nameAscending }
                    Button("notifications.sort.descending") { sort = .nameDescending }
                    Divider()
                    Button("briefing.partnerPicker.sort.client") { sort = .clientAscending }
                    Button("briefing.partnerPicker.sort.function") { sort = .functionAscending }
                } label: {
                    Label("briefing.partnerPicker.sort", systemImage: "arrow.up.arrow.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FacilityTheme.ink)
                        .frame(minWidth: 126, minHeight: 48)
                        .background(FacilityTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.black.opacity(0.09))
                        }
                }
            }

            HStack {
                Text("briefing.partnerPicker.available")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FacilityTheme.ink)
                Spacer()
                Text("\(displayedPartners.count)")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(FacilityTheme.accent)
                Text("briefing.partnerPicker.results")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            if displayedPartners.isEmpty {
                ContentUnavailableView(
                    "briefing.partnerPicker.empty.title",
                    systemImage: "building.2",
                    description: Text("briefing.partnerPicker.empty.message")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(displayedPartners) { partner in
                            partnerCard(partner)
                        }
                    }
                    .padding(2)
                }
            }
        }
    }

    private var displayedPartners: [BriefingPartnerSelection] {
        let searchQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return partners
            .filter { partner in
                Column.allCases.allSatisfy { column in
                    let query = columnFilters[column, default: ""]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return (query.isEmpty || column.value(from: partner).localizedCaseInsensitiveContains(query))
                        && (searchQuery.isEmpty || column.value(from: partner).localizedCaseInsensitiveContains(searchQuery))
                }
            }
            .sorted(by: sort.areInIncreasingOrder)
    }

    private func partnerCard(_ partner: BriefingPartnerSelection) -> some View {
        let isSelected = selectedPartnerID == partner.id

        return Button {
            selectedPartnerID = partner.id
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "building.2.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? FacilityTheme.accent : FacilityTheme.blue)
                    .frame(width: 44, height: 44)
                    .background(
                        (isSelected ? FacilityTheme.accent : FacilityTheme.blue).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text(partner.name.isEmpty ? partner.searchTerm1 : partner.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(FacilityTheme.ink)
                        .lineLimit(1)

                    HStack(spacing: 10) {
                        if !partner.function.isEmpty {
                            Text(partner.function)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(FacilityTheme.blue)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(FacilityTheme.blue.opacity(0.10), in: Capsule())
                        }
                        if !partner.searchTerm1.isEmpty {
                            Text(partner.searchTerm1)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if !partner.searchTerm2.isEmpty {
                            Text(partner.searchTerm2)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 8)

                if !partner.client.isEmpty {
                    Text(partner.client)
                        .font(.caption.monospaced().weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(FacilityTheme.canvas, in: Capsule())
                }

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? FacilityTheme.accent : Color.secondary.opacity(0.65))
                    .frame(width: 28)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
            .background(isSelected ? FacilityTheme.accentSoft : FacilityTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? FacilityTheme.accent.opacity(0.45) : Color.black.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(partner.name))
        .accessibilityValue(isSelected ? Text("briefing.partnerPicker.selected") : Text(""))
    }

    private func columnHeader(_ title: Text, width: CGFloat, column: Column) -> some View {
        HStack(spacing: 6) {
            title.lineLimit(1)
            Spacer(minLength: 4)
            Button {
                activeColumnMenu = activeColumnMenu == column ? nil : column
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .foregroundStyle(hasFilter(for: column) ? Color.accentColor : .secondary)
                    .frame(width: 28, height: 44)
            }
            .buttonStyle(.plain)
            .popover(isPresented: columnMenuBinding(for: column), attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                columnMenu(column).presentationCompactAdaptation(.popover)
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
            menuButton("notifications.sort.ascending") {
                sort = column.ascendingSort
                activeColumnMenu = nil
            }
            Divider()
            menuButton("notifications.sort.descending") {
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
            client = totalWidth * 0.13; function = totalWidth * 0.085; name = totalWidth * 0.26
            searchTerm1 = totalWidth * 0.2625
            searchTerm2 = totalWidth - client - function - name - searchTerm1
        }
    }

    private enum Column: CaseIterable, Hashable {
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

    private enum Sort: Equatable {
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

    func makeCoordinator() -> Coordinator { Coordinator(drawing: $drawing) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .black, width: 3)
        canvas.backgroundColor = backgroundColor
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        guard canvas.drawing != drawing else { return }
        canvas.drawing = drawing
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        private var drawing: Binding<PKDrawing>

        init(drawing: Binding<PKDrawing>) { self.drawing = drawing }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing.wrappedValue = canvasView.drawing
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            // PencilKit can batch the last drawing-change callback. Updating the
            // local binding here guarantees that SwiftUI persists the completed
            // stroke before a worker can close the form.
            drawing.wrappedValue = canvasView.drawing
        }
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
