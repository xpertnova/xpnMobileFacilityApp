import Observation
import PencilKit
import SwiftUI
import UIKit

struct BriefingWorkflowView: View {
    let workspace: FacilityDemoViewModel
    let onClose: () -> Void
    @State private var viewModel: BriefingWorkflowViewModel

    init(
        workspace: FacilityDemoViewModel,
        existingDraft: OfflineWorkItem? = nil,
        onClose: @escaping () -> Void
    ) {
        self.workspace = workspace
        self.onClose = onClose
        _viewModel = State(
            initialValue: BriefingWorkflowViewModel(
                source: .make(for: workspace),
                existingDraft: existingDraft
            )
        )
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        BriefingFormScreen(
            viewModel: viewModel,
            workspace: workspace,
            onClose: onClose
        )
        .background(FacilityTheme.canvas.ignoresSafeArea())
        .fullScreenCover(item: $viewModel.pdfArtifact) { artifact in
            BriefingPDFPreview(artifact: artifact) {
                Task {
                    if await viewModel.markPendingSynchronization(using: workspace.offlineWorkStore) {
                        onClose()
                    } else {
                        viewModel.pdfArtifact = nil
                    }
                }
            }
        }
        .overlay {
            if viewModel.isRenderingPDF {
                BriefingPDFRenderingOverlay()
            }
        }
    }
}

private struct BriefingFormScreen: View {
    let viewModel: BriefingWorkflowViewModel
    let workspace: FacilityDemoViewModel
    let onClose: () -> Void
    @State private var isShowingPartnerEditor = false
    @State private var isShowingBusinessEntityEditor = false
    @State private var isBuildingPickerPresented = false
    @State private var isOptionalSectionsExpanded = false

    var body: some View {
        @Bindable var viewModel = viewModel
        VStack(spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if !viewModel.hasRequiredMasterData {
                            unavailableBanner
                        }
                        briefingDataForm
                        optionalSectionsCard
                        checklist
                        signatureFields
                    }
                    .facilityPageContent()
                    // Do not disable ScrollView: completed forms must remain
                    // fully reviewable from Local work.
                    .disabled(viewModel.isReadOnly)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: viewModel.validationMessage) { _, message in
                    guard message == nil, let issue = viewModel.firstValidationIssue else { return }
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 180_000_000)
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(issue, anchor: .center)
                        }
                    }
                }
            }
        }
        .background(FacilityTheme.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            actionBar
        }
        .overlay {
            ZStack {
                LegacyBriefingPartnerEditorOverlay(isPresented: isShowingBusinessEntityEditor) {
                    BriefingBusinessEntitySelectionEditor(viewModel: viewModel) {
                        isShowingBusinessEntityEditor = false
                    }
                }

                LegacyBriefingPartnerEditorOverlay(isPresented: isShowingPartnerEditor) {
                    BriefingPartnerSelectionEditor(viewModel: viewModel) {
                        isShowingPartnerEditor = false
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.16), value: isShowingPartnerEditor)
        .animation(.easeOut(duration: 0.16), value: isShowingBusinessEntityEditor)
        .alert("forms.briefing.title", isPresented: Binding(
            get: { viewModel.validationMessage != nil },
            set: { if !$0 { viewModel.validationMessage = nil } }
        )) {
            Button("common.ok", role: .cancel) { viewModel.validationMessage = nil }
        } message: {
            Text(viewModel.validationMessage ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                Button(action: onClose) {
                    Label("forms.title", systemImage: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(FacilityTheme.blue)
                .frame(minHeight: 44, alignment: .leading)

                Text("briefing.form.title")
                    .facilityPageTitleFont()
                    .foregroundStyle(FacilityTheme.ink)

                Text("briefing.form.subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)
        }
        .facilityPageHorizontalPadding()
        .padding(.vertical, 18)
        .background(FacilityTheme.surface)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var unavailableBanner: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.title3.weight(.semibold))
                .foregroundStyle(FacilityTheme.orange)
                .frame(width: 42, height: 42)
                .background(FacilityTheme.orange.opacity(0.11), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("briefing.masterData.unavailable.title")
                    .font(.headline)
                    .foregroundStyle(FacilityTheme.ink)
                Text("briefing.masterData.unavailable.message")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(FacilityTheme.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(FacilityTheme.orange.opacity(0.22))
        }
    }

    private var briefingDataForm: some View {
        @Bindable var viewModel = viewModel
        return StandardFormHeader(
            partner: viewModel.selectedPartner,
            partnerInvalid: viewModel.isInvalid(.partner),
            partnerID: BriefingWorkflowViewModel.BriefingValidationIssue.partner,
            isPartnerSelectionEnabled: viewModel.selectedBusinessEntityID != nil,
            selectPartner: { isShowingPartnerEditor = true },
            instructorFirstName: viewModel.instructorFirstName,
            instructorLastName: viewModel.instructorLastName,
            coordinator: $viewModel.coordinator,
            coordinatorRequired: true,
            coordinatorInvalid: viewModel.isInvalid(.coordinator),
            coordinatorID: BriefingWorkflowViewModel.BriefingValidationIssue.coordinator,
            dateFrom: Binding(get: { viewModel.startDate }, set: viewModel.setStartDate),
            dateTo: $viewModel.endDate,
            dateRangeInvalid: viewModel.isInvalid(.executionRange),
            dateRangeID: BriefingWorkflowViewModel.BriefingValidationIssue.executionRange,
            workDescription: Binding(get: { viewModel.taskDescription }, set: viewModel.setTaskDescription),
            workDescriptionInvalid: viewModel.isInvalid(.taskDescription),
            workDescriptionID: BriefingWorkflowViewModel.BriefingValidationIssue.taskDescription,
            instructedPerson: Binding(get: { viewModel.instructedPerson }, set: viewModel.setInstructedPerson),
            instructedPersonInvalid: viewModel.isInvalid(.instructedPerson),
            instructedPersonID: BriefingWorkflowViewModel.BriefingValidationIssue.instructedPerson
        ) {
            VStack(alignment: .leading, spacing: 14) {
              SafetyFormField("briefing.businessEntity", required: true) {
                Button {
                    isShowingBusinessEntityEditor = true
                } label: {
                    valueHelpLabel(
                        viewModel.selectedBusinessEntity?.businessEntityTitle,
                        placeholder: "briefing.businessEntity.placeholder",
                        isEnabled: !viewModel.businessEntities.isEmpty
                    )
                    .briefingFieldChrome(invalid: viewModel.isInvalid(.businessEntity))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.businessEntities.isEmpty)
                .id(BriefingWorkflowViewModel.BriefingValidationIssue.businessEntity)
              }

              SafetyFormField("safetyInstrucForm.opertaionArea", required: true) {
                    Button {
                        isBuildingPickerPresented = true
                    } label: {
                        HStack(spacing: 12) {
                            Text(viewModel.selectedContext?.buildingTitle ?? String(localized: "briefing.building.placeholder"))
                                .foregroundStyle(viewModel.selectedContext == nil ? .secondary : .primary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(viewModel.selectedBusinessEntityID == nil ? .secondary : FacilityTheme.blue)
                        }
                        .briefingFieldChrome(invalid: viewModel.isInvalid(.building))
                    }
                    .buttonStyle(.plain)
                    .facilityPopover(
                        isPresented: $isBuildingPickerPresented,
                        arrowEdge: .top
                    ) {
                        buildingPicker
                    }
                    .disabled(viewModel.selectedBusinessEntityID == nil || viewModel.availableBuildings.isEmpty)
                    .id(BriefingWorkflowViewModel.BriefingValidationIssue.building)
              }
            }
        }
    }

    private var optionalSectionsCard: some View {
        let sections = viewModel.template?.sections.filter(\.isOptional) ?? []
        return Group {
            if !sections.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("briefing.optionalSections.title")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        let selectedSections = sections.filter { viewModel.selectedOptionalSectionIDs.contains($0.id) }
                        if selectedSections.isEmpty {
                            Button {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    isOptionalSectionsExpanded.toggle()
                                }
                            } label: {
                                Text("briefing.optionalSections.placeholder")
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(selectedSections) { section in
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.18)) {
                                                viewModel.setOptionalSection(section.id, selected: false)
                                            }
                                        } label: {
                                            HStack(spacing: 5) {
                                                Text(section.title)
                                                    .lineLimit(1)
                                                Image(systemName: "xmark")
                                                    .font(.caption2.weight(.bold))
                                                    .frame(width: 24, height: 24)
                                            }
                                            .font(.subheadline)
                                            .foregroundStyle(FacilityTheme.ink)
                                            .padding(.leading, 10)
                                            .padding(.trailing, 4)
                                            .padding(.vertical, 4)
                                            .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(Text("briefing.optionalSections.remove"))
                                        .accessibilityValue(section.title)
                                    }
                                }
                            }
                        }
                        Spacer(minLength: 0)
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                isOptionalSectionsExpanded.toggle()
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(FacilityTheme.blue)
                                .rotationEffect(.degrees(isOptionalSectionsExpanded ? 180 : 0))
                                .frame(width: 72, height: 54)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("briefing.optionalSections.title"))
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                    .background(FacilityTheme.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isOptionalSectionsExpanded ? FacilityTheme.accent.opacity(0.55) : Color.black.opacity(0.06))
                    }

                    if isOptionalSectionsExpanded {
                        VStack(spacing: 0) {
                            ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                                let isSelected = viewModel.selectedOptionalSectionIDs.contains(section.id)
                                Button {
                                    viewModel.setOptionalSection(section.id, selected: !isSelected)
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                            .font(.title3)
                                            .foregroundStyle(isSelected ? FacilityTheme.accent : .secondary)
                                        Text(section.title)
                                            .foregroundStyle(FacilityTheme.ink)
                                            .multilineTextAlignment(.leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 13)
                                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if index < sections.count - 1 {
                                    Divider().padding(.leading, 52)
                                }
                            }
                        }
                        .background(FacilityTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.black.opacity(0.08))
                        }
                    }
                }
                .facilityCard(padding: 20)
            }
        }
    }

    private var buildingPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "building.2")
                    .foregroundStyle(FacilityTheme.accent)
                Text("briefing.building.placeholder")
                    .font(.headline)
                    .foregroundStyle(FacilityTheme.ink)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.availableBuildings) { context in
                        let isSelected = context.buildingCode == viewModel.selectedBuildingCode

                        Button {
                            viewModel.selectBuilding(context.buildingCode)
                            isBuildingPickerPresented = false
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(context.buildingTitle)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(FacilityTheme.ink)
                                    if context.buildingTitle != context.buildingCode {
                                        Text(context.buildingCode)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer(minLength: 12)

                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(isSelected ? FacilityTheme.accent : .secondary)
                            }
                            .padding(.horizontal, 18)
                            .frame(minHeight: 58)
                            .background(isSelected ? FacilityTheme.accentSoft : FacilityTheme.surface)
                        }
                        .buttonStyle(.plain)

                        if context.id != viewModel.availableBuildings.last?.id {
                            Divider().padding(.leading, 18)
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 340)
        .background(FacilityTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("briefing.checklist.title", subtitle: "briefing.checklist.subtitle")
            VStack(spacing: 0) {
                BriefingChecklistTableHeader()
                ForEach(Array(viewModel.activeSections.enumerated()), id: \.element.id) { index, section in
                    BriefingChecklistSectionHeader(number: index + 1, title: section.title)
                    ForEach(section.items) { item in
                        BriefingChecklistRow(
                            item: item,
                            number: viewModel.number(for: item, in: section),
                            answerKey: viewModel.answerKeysByItemID[item.id],
                            comment: viewModel.commentsByItemID[item.id] ?? "",
                            setAnswer: { viewModel.answerKeysByItemID[item.id] = $0 },
                            setComment: { viewModel.commentsByItemID[item.id] = $0 }
                        )
                    }
                }
            }
            .background(FacilityTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(FacilityTheme.ink.opacity(0.12), lineWidth: 1)
            }
        }
    }

    private var signatureFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("briefing.signatures.title", subtitle: "briefing.signatures.subtitle")

            VStack(spacing: 16) {
                signatureField(for: .instructor)
                signatureField(for: .instructedPerson)
            }
        }
    }

    private func signatureField(for role: BriefingSignatureRole) -> some View {
        BriefingInlineSignatureField(
            title: LocalizedStringKey(role.titleKey),
            signatureData: Binding(
                get: {
                    role == .instructor
                        ? viewModel.instructorSignature
                        : viewModel.instructedPersonSignature
                },
                set: { viewModel.setSignature($0, for: role) }
            ),
            isInvalid: viewModel.isInvalid(role == .instructor ? .instructorSignature : .instructedPersonSignature)
        )
        .frame(maxWidth: .infinity)
        .id(
            role == .instructor
                ? BriefingWorkflowViewModel.BriefingValidationIssue.instructorSignature
                : BriefingWorkflowViewModel.BriefingValidationIssue.instructedPersonSignature
        )
    }

    private var actionBar: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 12)

            if viewModel.isReadOnly {
                Button("common.back", action: onClose)
                    .buttonStyle(.bordered)
                    .tint(FacilityTheme.ink)
            } else {
                Button("briefing.closeBriefing") { viewModel.requestCompletion() }
                    .buttonStyle(.borderedProminent)
                    .tint(FacilityTheme.accent)
                    .disabled(!viewModel.canComplete || viewModel.isRenderingPDF)
            }
        }
        .facilityPageHorizontalPadding()
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }


    private func valueHelpLabel(
        _ value: String?,
        placeholder: String,
        isEnabled: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Text(value ?? String(localized: String.LocalizationValue(placeholder)))
                .foregroundStyle(value == nil ? .secondary : .primary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "square.on.square")
                .foregroundStyle(isEnabled ? FacilityTheme.blue : .secondary)
        }
    }

}

struct SignatureInputRequirement: Equatable {
    let isSigningEnabled: Bool
    let requiredNameField: String

    init(signerName: String, requiredNameField: String) {
        isSigningEnabled = !signerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        self.requiredNameField = requiredNameField
    }

    var lockedMessage: String? {
        guard !isSigningEnabled else { return nil }
        return String(
            format: String(localized: "signature.prerequisite.prompt"),
            locale: .current,
            requiredNameField
        )
    }
}

/// The form keeps both signatures visible, while retaining the same
/// PencilKit input behavior and clear action as the legacy briefing dialog.
struct BriefingInlineSignatureField: View {
    let title: LocalizedStringKey
    @Binding private var signatureData: Data?
    let isInvalid: Bool
    let inputRequirement: SignatureInputRequirement?

    @State private var drawing = PKDrawing()
    @State private var showsStoredSignature: Bool

    init(
        title: LocalizedStringKey,
        signatureData: Binding<Data?>,
        isInvalid: Bool,
        inputRequirement: SignatureInputRequirement? = nil
    ) {
        self.title = title
        _signatureData = signatureData
        self.isInvalid = isInvalid
        self.inputRequirement = inputRequirement
        _showsStoredSignature = State(initialValue: signatureData.wrappedValue != nil)
    }

    private var isSigningEnabled: Bool {
        inputRequirement?.isSigningEnabled ?? true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(FacilityTheme.ink)

                Spacer(minLength: 12)

                Button("flEQ.briefing.signature.clear") {
                    drawing = PKDrawing()
                    showsStoredSignature = false
                    signatureData = nil
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FacilityTheme.blue)
                .frame(minHeight: 44)
                .disabled(drawing.bounds.isEmpty && !showsStoredSignature)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white)

                if showsStoredSignature,
                   let signatureData,
                   let image = UIImage(data: signatureData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(16)
                } else {
                    BriefingSignatureCanvas(
                        drawing: $drawing,
                        onDrawingChanged: persistSignature(from:)
                    )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .allowsHitTesting(isSigningEnabled)

                    if drawing.bounds.isEmpty {
                        Text(inputRequirement?.lockedMessage ?? String(localized: "briefing.signature.placeholder"))
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(minHeight: 160)
            .opacity(isSigningEnabled ? 1 : 0.62)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isInvalid && signatureData == nil ? FacilityTheme.red : Color.black.opacity(0.12),
                        lineWidth: isInvalid && signatureData == nil ? 2 : 1
                    )
            }
        }
        .padding(18)
        .background(FacilityTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.055))
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint(inputRequirement?.lockedMessage ?? "")
    }

    private func persistSignature(from drawing: PKDrawing) {
        guard !drawing.bounds.isEmpty else {
            if !showsStoredSignature {
                signatureData = nil
            }
            return
        }

        showsStoredSignature = false
        guard let data = BriefingSignatureRasterizer.pngData(from: drawing) else { return }
        signatureData = data
    }
}

private struct BriefingChecklistTableHeader: View {
    @Environment(\.facilityLayout) private var layout

    var body: some View {
        let metrics = BriefingChecklistMetrics(layout: layout)
        HStack(spacing: 0) {
            Text("briefing.checklist.number").frame(width: metrics.numberColumn)
            Text("briefing.checklist.type").frame(maxWidth: .infinity, alignment: .leading)
            Text("notifications.detail.result.no").frame(width: metrics.answerHalfColumn)
            Text("//").frame(width: metrics.answerSeparatorColumn)
            Text("notifications.detail.result.yes").frame(width: metrics.answerHalfColumn)
            Color.clear.frame(width: metrics.documentColumn)
            Text("briefing.checklist.info").frame(width: metrics.informationColumn)
            // "Kommentar" is slightly wider than the compact column.
            Text("briefing.checklist.comment")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: metrics.commentColumn)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(FacilityTheme.ink)
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
        .background(FacilityTheme.canvas)
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct BriefingChecklistSectionHeader: View {
    let number: Int
    let title: String

    var body: some View {
        Text("\(number). \(title)")
            .font(.subheadline.weight(.semibold))
            .lineSpacing(2)
            .foregroundStyle(FacilityTheme.ink)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(FacilityTheme.navy.opacity(0.06))
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityAddTraits(.isHeader)
    }
}

private struct BriefingChecklistRow: View {
    let item: SAPBriefingTemplateItem
    let number: String
    let answerKey: String?
    let comment: String
    let setAnswer: (String) -> Void
    let setComment: (String) -> Void
    @State private var referenceDocument: BriefingReferenceDocument?
    @State private var isEditingComment = false
    @Environment(\.facilityLayout) private var layout

    var body: some View {
        tableRow
            .background(FacilityTheme.surface)
        .overlay(alignment: .bottom) { Divider() }
        .fullScreenCover(item: $referenceDocument) { document in
            BriefingReferenceDocumentPreview(document: document)
        }
        .sheet(isPresented: $isEditingComment) {
            BriefingChecklistCommentEditor(initialComment: comment, onSave: setComment)
        }
    }

    private var tableRow: some View {
        let metrics = BriefingChecklistMetrics(layout: layout)
        return HStack(alignment: .center, spacing: 0) {
            Text(number)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: metrics.numberColumn)
            Text(item.title)
                .font(.subheadline)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .foregroundStyle(FacilityTheme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 20)
            answerControl
                .frame(width: metrics.answerColumn)
            documentControl
                .frame(width: metrics.documentColumn, height: 48)
            informationControl
                .frame(width: metrics.informationColumn, height: 48)
            commentControl
                .frame(width: metrics.commentColumn, height: 72)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 88, alignment: .top)
    }

    private var answerControl: some View {
        HStack(spacing: 4) {
            ForEach(item.answerOptions.normalizedForLegacyYesNoControl) { option in
                let isSelected = answerKey == option.key
                let isYes = option.isAffirmativeBriefingAnswer
                Button { setAnswer(option.key) } label: {
                    Text(verbatim: option.localizedControlTitle)
                        .lineLimit(1)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? .white : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(
                            isSelected ? (isYes ? FacilityTheme.accent : FacilityTheme.red) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(uiColor: .systemGray6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel("Answer")
    }

    @ViewBuilder private var documentControl: some View {
        if let document = BriefingReferenceDocument(symbolID: item.documentSymbolID) {
            Button { referenceDocument = document } label: {
                Image(systemName: "paperclip")
                    .font(.title2)
                    .foregroundStyle(FacilityTheme.blue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(document.title)
        } else {
            Color.clear
        }
    }

    @ViewBuilder private var informationControl: some View {
        if let assetName = BriefingSafetySymbol.assetName(for: item.warningSymbolID) {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .padding(7)
                .accessibilityLabel("briefing.checklist.safetySign")
        } else if item.warningSymbolID != nil {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(FacilityTheme.orange)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.clear
        }
    }

    private var commentControl: some View {
        Button { isEditingComment = true } label: {
            Image(systemName: comment.isEmpty ? "pencil" : "pencil.circle.fill")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(comment.isEmpty ? FacilityTheme.ink.opacity(0.75) : FacilityTheme.accent)
                .frame(width: 60, height: 60)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("briefing.checklist.comment")
        .accessibilityValue(
            Text(LocalizedStringKey(comment.isEmpty ? "briefing.comment.none" : "briefing.comment.added"))
        )
    }
}

private struct BriefingChecklistCommentEditor: View {
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var comment: String

    init(initialComment: String, onSave: @escaping (String) -> Void) {
        self.onSave = onSave
        _comment = State(initialValue: initialComment)
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $comment)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(FacilityTheme.canvas)
                .padding(24)
                .navigationTitle("briefing.checklist.comment")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("common.cancel", action: dismiss.callAsFunction)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("briefing.comment.save") { onSave(comment); dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}

private extension SAPBriefingAnswerOption {
    var isNegativeBriefingAnswer: Bool {
        Self.negativeValues.contains(normalizedBriefingAnswer)
            || Self.negativeValues.contains(title.normalizedBriefingAnswer)
    }

    var isAffirmativeBriefingAnswer: Bool {
        Self.affirmativeValues.contains(normalizedBriefingAnswer)
            || Self.affirmativeValues.contains(title.normalizedBriefingAnswer)
    }

    /// The legacy briefing control is always a localized Nein/Ja pair. SAP's
    /// key stays untouched so local drafts and generated PDFs retain the
    /// source value rather than a translated display value.
    var localizedControlTitle: String {
        isNegativeBriefingAnswer
            ? String(localized: "notifications.detail.result.no")
            : String(localized: "notifications.detail.result.yes")
    }

    private var normalizedBriefingAnswer: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static let negativeValues = ["0", "FALSE", "N", "NEIN", "NO"]
    private static let affirmativeValues = ["1", "TRUE", "J", "JA", "YES"]
}

private extension String {
    var normalizedBriefingAnswer: String {
        trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

private extension Array where Element == SAPBriefingAnswerOption {
    /// SAP occasionally supplies only one side of the boolean pair. The
    /// reference briefing app completes it for display and preserves supplied
    /// keys wherever they are available.
    var normalizedForLegacyYesNoControl: [SAPBriefingAnswerOption] {
        [
            first(where: \.isNegativeBriefingAnswer)
                ?? SAPBriefingAnswerOption(key: "NO", title: "No"),
            first(where: \.isAffirmativeBriefingAnswer)
                ?? SAPBriefingAnswerOption(key: "YES", title: "Yes")
        ]
    }
}

private enum BriefingSafetySymbol {
    static func assetName(for identifier: String?) -> String? {
        switch identifier?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "I001": "BriefingSafety_I001"
        case "M014": "BriefingSafety_M014"
        case "P002": "BriefingSafety_P002"
        case "W001": "BriefingSafety_W001"
        case "W002": "BriefingSafety_W002"
        case "W003": "BriefingSafety_W003"
        case "X001": "BriefingSafety_X001"
        default: nil
        }
    }
}

struct BriefingReferenceDocument: Identifiable {
    let symbolID: String
    let fileName: String
    let title: String
    var id: String { symbolID }

    init?(symbolID: String?) {
        guard let symbolID else { return nil }
        switch symbolID {
        case "1": self.init(symbolID: symbolID, fileName: "EinweisungsDienstleistungen", title: "Einweisungsformular nur für Dienstleistungen")
        case "2": self.init(symbolID: symbolID, fileName: "SichOrdnEnerUmwelt", title: "Sicherheits-, Ordnungs-, Energie- und Umweltvorschriften")
        case "3": self.init(symbolID: symbolID, fileName: "SicherheitsCheckliste", title: "Sicherheits-Checkliste")
        case "4": self.init(symbolID: symbolID, fileName: "Matrix", title: "Matrix")
        case "5": self.init(symbolID: symbolID, fileName: "GasFeuerLoeschanlage", title: "Gas-Feuerlöschanlage")
        case "6": self.init(symbolID: symbolID, fileName: "Sicherheitsbereich", title: "Sicherheitsbereich")
        case "7": self.init(symbolID: symbolID, fileName: "Qualifikationsnachweis", title: "Qualifikationsnachweis")
        default: return nil
        }
    }

    private init(symbolID: String, fileName: String, title: String) {
        self.symbolID = symbolID
        self.fileName = fileName
        self.title = title
    }
}

enum BriefingSignatureRole: String, Identifiable {
    case instructor
    case instructedPerson

    var id: String { rawValue }
    var titleKey: String {
        self == .instructor
            ? "flEQ.briefing.signature.instructor"
            : "flEQ.briefing.signature.instructedPerson"
    }
}

@MainActor
@Observable
final class BriefingWorkflowViewModel {
    struct Context: Identifiable, Hashable {
        let businessEntityID: String
        let businessEntityTitle: String
        let buildingCode: String
        let buildingTitle: String
        var id: String { "\(businessEntityID)|\(buildingCode)" }
    }
    struct Source {
        let isDemo: Bool
        let contexts: [Context]
        let partners: [SAPBriefingPartner]
        let templates: [SAPBriefingTemplate]
        let workerProfile: SAPWorkerProfile?
        let workerName: String
        let offlineWorkStore: OfflineWorkStore

        @MainActor static func make(for workspace: FacilityDemoViewModel) -> Self {
            if workspace.isDemoMode { return .demo(workspace.offlineWorkStore, workerName: workspace.effectiveWorkerDisplayName) }
            let contexts: [Context] = Dictionary(grouping: workspace.notificationFilterMetadata, by: { "\($0.businessEntityID)|\($0.buildingCode)" })
                .values.compactMap { group in
                    guard let first = group.first, !first.buildingCode.isEmpty else { return nil }
                    return Context(businessEntityID: first.businessEntityID, businessEntityTitle: first.businessEntityID, buildingCode: first.buildingCode, buildingTitle: "\(first.buildingCode) · \(first.functionalLocationName)")
                }.sorted { $0.id < $1.id }
            return Self(isDemo: false, contexts: contexts, partners: workspace.sapDataStore.cachedData.briefingPartners, templates: workspace.sapDataStore.cachedData.briefingTemplates, workerProfile: workspace.sapDataStore.workerProfile, workerName: workspace.effectiveWorkerDisplayName, offlineWorkStore: workspace.offlineWorkStore)
        }

        static func demo(_ store: OfflineWorkStore, workerName: String) -> Self {
            let partner = SAPBriefingPartner(id: "1000001", client: "100", function: "ZT", name: "Test Adresse für IT Zwecke", contactName: "sdfsdfsdfsdf", searchTerm1: "Westnetz", searchTerm2: "", street: "", houseNumber: "", postalCode: "", city: "", country: "DE", email: "service@westnetz.example")
            let options = [SAPBriefingAnswerOption(key: "NO", title: "Nein"), SAPBriefingAnswerOption(key: "YES", title: "Ja")]
            let template = SAPBriefingTemplate(id: "TFMINSTRUC|I3|A|TFMB_001", equipmentType: "TFMINSTRUC", plannerGroup: "I3", planType: "A", planNumber: "TFMB_001", sections: [
                SAPBriefingTemplateSection(
                    id: "0010",
                    title: "Fachliche und persönliche Eignung",
                    subtitle: "Die Mitarbeiter des Auftragnehmers müssen für den Einsatz an den Orten der Leistungserbringung, in den\nBetriebsstätten, auf den Baustellen und an sonstigen Einrichtungen des Auftraggebers fachlich und persönlich geeignet sein.",
                    isOptional: false,
                    items: [
                        SAPBriefingTemplateItem(id: "0010-01", orderIdentifier: "0010", rowType: .position, title: "Sicherheitspass vorgelegt\nDie fachliche und persönliche Eignung aller eingesetzten Mitarbeiter wurde durch den Auftragnehmer bestätigt.\nHinweis: Die Sicherstellung sowie der Nachweis (z.B. Sicherheitspass) dieser Eignung obliegt dem Auftragnehmer und kann bei Bedarf durch den Auftraggeber zur Einsicht angefordert werden. Bei fehlender bzw. unvollständiger Dokumentation, können die Mitarbeiter des Einsatzortes verwiesen werden (ggf. zeitnahe Nachreichung prüfen).", answerOptions: options, documentSymbolID: nil, warningSymbolID: nil),
                        SAPBriefingTemplateItem(id: "0010-02", orderIdentifier: "0020", rowType: .position, title: "Partnerfirma bestätigt aktuelle Angaben\nDie Partnerfirma bestätigt, dass der Nachweis, unberührt von anderen Dokumentationspflichten, alle für die beauftragte Tätigkeit maßgeblichen aktuellen Angaben enthält.", answerOptions: options, documentSymbolID: nil, warningSymbolID: nil)
                    ]
                ),
                SAPBriefingTemplateSection(
                    id: "0020",
                    title: "Notfallmanagement",
                    subtitle: nil,
                    isOptional: false,
                    items: [
                        SAPBriefingTemplateItem(id: "0020-01", orderIdentifier: "0010", rowType: .position, title: "Aushang Teil A im gezeigt / erläutert\nDen Aushang Teil A im Gebäude gezeigt und erläutert", answerOptions: options, documentSymbolID: nil, warningSymbolID: nil),
                        SAPBriefingTemplateItem(id: "0020-02", orderIdentifier: "0020", rowType: .position, title: "Brandschutzordnung Teil B erläutert\nBrandschutzordnung Teil B bzw. das Verhalten im Gefahrenfall ist bekannt und die Inhalte wurden besprochen", answerOptions: options, documentSymbolID: nil, warningSymbolID: nil),
                        SAPBriefingTemplateItem(id: "0020-03", orderIdentifier: "0030", rowType: .position, title: "Ansprechperson im Gefahrenfall erläutert\nDie Ansprechpartner/in für den Gefahrenfall z.B. „Gebäudespezifischen Anhang“ (erste Seite) sind bekannt und die Inhalte wurden besprochen.", answerOptions: options, documentSymbolID: nil, warningSymbolID: nil),
                        SAPBriefingTemplateItem(id: "0020-04", orderIdentifier: "0040", rowType: .position, title: "Ablauf Notruf (Tel/Adresse) erläutert\nIm Fall eines Notrufs, auf die Reihenfolge zuerst 112 dann „Interne Notrufnummer“ wählen, hingewiesen. Die Adresse des Arbeitsortes für den Fall eines Notrufes wurde besprochen.", answerOptions: options, documentSymbolID: nil, warningSymbolID: nil),
                        SAPBriefingTemplateItem(id: "0020-05", orderIdentifier: "0050", rowType: .position, title: "Art der Alarmierung erläutert", answerOptions: options, documentSymbolID: nil, warningSymbolID: nil),
                        SAPBriefingTemplateItem(id: "0020-06", orderIdentifier: "0060", rowType: .position, title: "Alarmierung, Erste Hilfe erläutert\nDie vorhandenen Einrichtungen zur Alarmierung (Druckknopfmelder oder Hausalarm), Ersten Hilfe und Brandbekämpfung im Gebäude gezeigt", answerOptions: options, documentSymbolID: nil, warningSymbolID: nil),
                        SAPBriefingTemplateItem(id: "0020-07", orderIdentifier: "0070", rowType: .position, title: "Handout \"Vorschriften\" ausgehändigt\nDas Handout \"Sicherheits-, Ordnungs-, Energie- und Umweltvorschriften\" wurde dem Auftragnehmer ausgehändigt", answerOptions: options, documentSymbolID: nil, warningSymbolID: nil),
                        SAPBriefingTemplateItem(id: "0020-08", orderIdentifier: "0080", rowType: .position, title: "Hausordnung gezeigt und erläutert", answerOptions: options, documentSymbolID: nil, warningSymbolID: nil)
                    ]
                ),
                SAPBriefingTemplateSection(
                    id: "0030",
                    title: "Flucht und Rettungswege/Sammelplatz",
                    subtitle: nil,
                    isOptional: false,
                    items: [
                        SAPBriefingTemplateItem(id: "0030-01", orderIdentifier: "0010", rowType: .position, title: "Flucht-/Rettungspläne erläutert\nDen Verlauf des Flucht- und Rettungsweges gezeigt", answerOptions: options, documentSymbolID: nil, warningSymbolID: nil),
                        SAPBriefingTemplateItem(id: "0030-02", orderIdentifier: "0020", rowType: .position, title: "Die Lage des Sammelplatzes gezeigt", answerOptions: options, documentSymbolID: nil, warningSymbolID: nil),
                        SAPBriefingTemplateItem(id: "0030-03", orderIdentifier: "0030", rowType: .position, title: "Verhaltensweisen im Gebäude erläutert\nAuf folgende Verhaltensweisen hingewiesen: Flucht- und Rettungswege (Flure, Treppen und Ausgänge) dürfen weder zugestellt noch mit Gegenständen eingeengt werden Das Abstellen von brennbaren Stoffen ist grundsätzlich verboten Brandschutztüren dürfen nicht verkeilt werden Notausgänge sind stets frei und benutzbar zu halten", answerOptions: options, documentSymbolID: nil, warningSymbolID: nil)
                    ]
                ),
                SAPBriefingTemplateSection(
                    id: "0040",
                    title: "Sicherheitskennzeichnung",
                    subtitle: nil,
                    isOptional: false,
                    items: [
                        SAPBriefingTemplateItem(id: "0040-01", orderIdentifier: "0010", rowType: .position, title: "Innerbetriebliche Verbote erläutert", answerOptions: options, documentSymbolID: nil, warningSymbolID: nil),
                        SAPBriefingTemplateItem(id: "0040-02", orderIdentifier: "0020", rowType: .position, title: "Innerbetriebliche Gebote erläutert", answerOptions: options, documentSymbolID: nil, warningSymbolID: nil),
                        SAPBriefingTemplateItem(id: "0040-03", orderIdentifier: "0030", rowType: .position, title: "Innerbetriebliche Warnungen erläutert", answerOptions: options, documentSymbolID: nil, warningSymbolID: nil),
                        SAPBriefingTemplateItem(id: "0040-04", orderIdentifier: "0040", rowType: .position, title: "Nutzung von innerbetriebl. PSA erläutert\nAuf die Nutzung von innerbetrieblicher PSA hingewiesen (nicht tätigkeitsbezogen)", answerOptions: options, documentSymbolID: nil, warningSymbolID: nil),
                        SAPBriefingTemplateItem(id: "0040-04-1", orderIdentifier: "0041", rowType: .subposition, title: "Schutzbrille", answerOptions: options, documentSymbolID: nil, warningSymbolID: "M004"),
                        SAPBriefingTemplateItem(id: "0040-04-2", orderIdentifier: "0042", rowType: .subposition, title: "Schutzhelm", answerOptions: options, documentSymbolID: nil, warningSymbolID: "M014"),
                        SAPBriefingTemplateItem(id: "0040-04-3", orderIdentifier: "0043", rowType: .subposition, title: "Sicherheitsschuh", answerOptions: options, documentSymbolID: nil, warningSymbolID: "M008"),
                        SAPBriefingTemplateItem(id: "0040-04-4", orderIdentifier: "0044", rowType: .subposition, title: "Gehörschutz", answerOptions: options, documentSymbolID: nil, warningSymbolID: "M003"),
                        SAPBriefingTemplateItem(id: "0040-04-5", orderIdentifier: "0045", rowType: .subposition, title: "Sonstiges", answerOptions: options, documentSymbolID: nil, warningSymbolID: nil),
                        SAPBriefingTemplateItem(id: "0040-05", orderIdentifier: "0050", rowType: .position, title: "Innerbetriebl. Verkehrszeichen erläutert", answerOptions: options, documentSymbolID: nil, warningSymbolID: nil),
                        SAPBriefingTemplateItem(id: "0040-06", orderIdentifier: "0060", rowType: .position, title: "Innerbetriebli. Gefahrstoffe erläutert", answerOptions: options, documentSymbolID: nil, warningSymbolID: nil),
                        SAPBriefingTemplateItem(id: "0040-07", orderIdentifier: "0070", rowType: .position, title: "Baustellenschutz erläutert\nDie Baustelle inkl. aller Baustelleneinrichtungen sind vor Zutritt unbefugter Dritter zu schützen (u.a. Gerüste, Treppentürme)", answerOptions: options, documentSymbolID: nil, warningSymbolID: nil)
                    ]
                ),
                SAPBriefingTemplateSection(
                    id: "0050",
                    title: "Brandschutz",
                    subtitle: nil,
                    isOptional: true,
                    items: [
                        SAPBriefingTemplateItem(id: "0050-01", orderIdentifier: "0010", rowType: .position, title: "Standorte der Feuerlöscher wurden erläutert.", answerOptions: options, documentSymbolID: nil, warningSymbolID: "F001")
                    ]
                ),
                SAPBriefingTemplateSection(
                    id: "0060",
                    title: "Arbeitsplatz/-einrichtung",
                    subtitle: nil,
                    isOptional: false,
                    items: [
                        SAPBriefingTemplateItem(id: "0060-01", orderIdentifier: "0010", rowType: .position, title: "Arbeitsplatz erläutert\nArbeitsplatz/-ort wurde begangen und erläutert", answerOptions: options, documentSymbolID: nil, warningSymbolID: nil),
                        SAPBriefingTemplateItem(id: "0060-02", orderIdentifier: "0020", rowType: .position, title: "Einrichtungen/Maschinen erläutert\nDer Eingewiesene wurde an Ort und Stelle mit allen Einrichtungen/Maschinen vertraut gemacht", answerOptions: options, documentSymbolID: nil, warningSymbolID: nil),
                        SAPBriefingTemplateItem(id: "0060-03", orderIdentifier: "0030", rowType: .position, title: "Einrichtungen/Maschinen erläutert", answerOptions: options, documentSymbolID: nil, warningSymbolID: nil),
                        SAPBriefingTemplateItem(id: "0060-04", orderIdentifier: "0040", rowType: .position, title: "Bed.-Anleitungen zur Verfügung gestellt\nBetriebsanweisungen/Bedienungsanleitungen für Einrichtungen/Maschinen des Einweisers/Abnehmers stehen der Partnerfirma zur Verfügung", answerOptions: options, documentSymbolID: nil, warningSymbolID: nil),
                        SAPBriefingTemplateItem(id: "0060-05", orderIdentifier: "0050", rowType: .position, title: "Masch.-Sicherheitseinrichtungen\nSicherheitseinrichtungen an Maschinen wurden erläutert", answerOptions: options, documentSymbolID: nil, warningSymbolID: nil),
                        SAPBriefingTemplateItem(id: "0060-06", orderIdentifier: "0060", rowType: .position, title: "Nutzung/Lagerung von Druckgasflaschen\nBei Nutzung von Druckgasflaschen sind der Umgang sowie die Lagerung mit dem Einweiser/Abnehmer gesondert abzustimmen", answerOptions: options, documentSymbolID: nil, warningSymbolID: nil),
                        SAPBriefingTemplateItem(id: "0060-07", orderIdentifier: "0070", rowType: .position, title: "Absicherung der Arbeitsstätte besprochen\nDie Absicherung der Arbeitsstätte wurde eindeutig besprochen z.B.Sekuranten auf Flachdächern für PSAgA vorhanden /nicht vorhanden, Leitern und Aufstiege, Gerüste inkl. Freigabe)", answerOptions: options, documentSymbolID: nil, warningSymbolID: nil),
                        SAPBriefingTemplateItem(id: "0060-08", orderIdentifier: "0080", rowType: .position, title: "Arbeiten mit Absturzgefahr / PSAgA\nBei folgenden Absturzhöhen ist eine Sicherung gegen Absturz von Personen vorzusehen: - ab 0,00 m Höhe über Wasser oder anderen relevanten Stoffen, in denen man versinken kann - ab 1,00 m Höhe - Arbeiten < 2,0 m zur Absturzkante Hinweis: Bei ungünstigen Wetterverhältnissen (z.B. Gewitter, starkem Wind, Reif- oder Vereisungsgefahr) dürfen Arbeiten in Höhen nicht durchgeführt werden. Sekuranten auf Flachdächern für PSAgA, Leitern/Aufstiege und Gerüste sind ordnungsgemäß anzuwenden.\nEine Gefährdung anderer Arbeitnehmer durch die auszuführenden Arbeiten ist ausgeschlossen\nHinweis, Stäube und Fasern : Werden bei Arbeiten asbesthaltige Stoffe oder „Künstliche Mineralfasern\" (KMF) gefunden, ist dieses unverzüglich dem AG mitzuteilen und die Arbeit ist einzustellen.", answerOptions: options, documentSymbolID: nil, warningSymbolID: nil),
                        SAPBriefingTemplateItem(id: "0060-09", orderIdentifier: "0090", rowType: .position, title: "Meldung defekte Einrichtungen/Maschinen\nDefekte Einrichtungen/Maschinen werden durch die Partnerfirma unverzüglich an den Abnehmer gemeldet und der weiteren Benutzung entzogen", answerOptions: options, documentSymbolID: nil, warningSymbolID: nil),
                        SAPBriefingTemplateItem(id: "0060-10", orderIdentifier: "0100", rowType: .position, title: "Ordnungsgemäßer Zustand d. Arbeitsstätte\nDer Arbeitsort ist während und nach Beendigung der Arbeiten in einem ordnungsgemäßen Zustand zu halten, angemessen aufzuräumen und zu säubern", answerOptions: options, documentSymbolID: nil, warningSymbolID: nil)
                    ]
                ),
                SAPBriefingTemplateSection(
                    id: "0070",
                    title: "Arbeitsaufgabe/-ablauf",
                    subtitle: nil,
                    isOptional: false,
                    items: [
                        SAPBriefingTemplateItem(id: "0070-01", orderIdentifier: "0010", rowType: .position, title: "Konkreter Auftragsablauf besprochen\nDer konkrete Auftragsablauf wurde besprochen", answerOptions: options, documentSymbolID: nil, warningSymbolID: nil),
                        SAPBriefingTemplateItem(id: "0070-02", orderIdentifier: "0020", rowType: .position, title: "Freigabeverfahren zur Arbeit besprochen\nDas Freigabeverfahren zur Arbeit wurde eindeutig besprochen", answerOptions: options, documentSymbolID: nil, warningSymbolID: nil),
                        SAPBriefingTemplateItem(id: "0070-03", orderIdentifier: "0030", rowType: .position, title: "Arbeiten an/i.d.N, elektrischer Anlagen\nArbeiten an, in oder in der Nähe von elektrischen Anlagen", answerOptions: options, documentSymbolID: nil, warningSymbolID: nil),
                        SAPBriefingTemplateItem(id: "0070-04", orderIdentifier: "0040", rowType: .position, title: "Benennung d. Koordinator des Einweisers\nDer Koordinator des Einweisers/Abnehmers (falls erforderlich) wurde eindeutig benannt", answerOptions: options, documentSymbolID: nil, warningSymbolID: nil)
                    ]
                ),
                SAPBriefingTemplateSection(
                    id: "0075",
                    title: "Sicherheitscheckliste für Erdarbeiten",
                    subtitle: "Die Sicherheitscheckliste Erdarbeiten in der Nähe erdverlegter Kabel und Rohrleitungen wurde ausgefüllt.",
                    isOptional: false,
                    items: []
                ),
                SAPBriefingTemplateSection(
                    id: "0080",
                    title: "Unfälle",
                    subtitle: nil,
                    isOptional: false,
                    items: [
                        SAPBriefingTemplateItem(id: "0080-01", orderIdentifier: "0010", rowType: .position, title: "Hinweis auf betriebl. Arbeitsmedizin\nAuf die betriebliche Arbeitsmedizin/Sanitätsstation wurde hingewiesen(soweit vor Ort vorhanden)", answerOptions: options, documentSymbolID: nil, warningSymbolID: nil),
                        SAPBriefingTemplateItem(id: "0080-02", orderIdentifier: "0020", rowType: .position, title: "Aufsuchen „Arbeitsmedizin“ bei Unfall\nDer Verletzte hat sich, soweit möglich, in der örtlichen Arbeitsmedizin/Sanitätsstation des Abnehmers vorzustellen", answerOptions: options, documentSymbolID: nil, warningSymbolID: nil),
                        SAPBriefingTemplateItem(id: "0080-03", orderIdentifier: "0030", rowType: .position, title: "Meldung von Unfällen bei Partnerfirma\nUnfälle der Partnerfirma müssen unverzüglich dem Abnehmer gemeldet werden", answerOptions: options, documentSymbolID: nil, warningSymbolID: nil)
                    ]
                )
            ])
            return Self(isDemo: true, contexts: [Context(businessEntityID: "DE-ANR-17705-01", businessEntityTitle: "DE-ANR-17705-01", buildingCode: "GB01", buildingTitle: "GB01_Völlinghauser Str. 15_Büro-/H_(oA)\nVöllinghauser Str. 15,\n59609, Anröchte (DE)")], partners: [partner], templates: [template], workerProfile: nil, workerName: workerName, offlineWorkStore: store)
        }
    }

    let source: Source
    var selectedBusinessEntityID: String?
    var selectedBuildingCode: String?
    var selectedTemplateID: String = ""
    var coordinator = ""
    var instructedPerson = ""
    var selectedPartnerID = ""
    var partnerEmail = ""
    var taskDescription = ""
    var startDate = Date.now
    var endDate = Date.now
    var selectedOptionalSectionIDs: Set<String> = []
    var answerKeysByItemID: [String: String] = [:]
    var commentsByItemID: [String: String] = [:]
    var instructorSignature: Data?
    var instructedPersonSignature: Data?
    var pdfArtifact: BriefingPDFArtifact?
    var isRenderingPDF = false
    var validationMessage: String?

    var hasAttemptedCompletion = false

    enum BriefingValidationIssue {
        case instructedPerson
        case businessEntity
        case building
        case coordinator
        case partner
        case executionRange
        case taskDescription
        case instructorSignature
        case instructedPersonSignature
    }

    var validationIssues: Set<BriefingValidationIssue> {
        var issues: Set<BriefingValidationIssue> = []
        if selectedBusinessEntityID == nil { issues.insert(.businessEntity) }
        if selectedContext == nil { issues.insert(.building) }
        if coordinator.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.insert(.coordinator) }
        if selectedPartnerID.isEmpty { issues.insert(.partner) }
        if instructedPerson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.insert(.instructedPerson) }
        if taskDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.insert(.taskDescription) }
        if endDate < startDate { issues.insert(.executionRange) }
        if instructorSignature == nil { issues.insert(.instructorSignature) }
        if instructedPersonSignature == nil { issues.insert(.instructedPersonSignature) }
        return issues
    }

    var firstValidationIssue: BriefingValidationIssue? {
        let ordered: [BriefingValidationIssue] = [
            .partner,
            .businessEntity,
            .building,
            .coordinator,
            .executionRange,
            .taskDescription,
            .instructedPerson,
            .instructorSignature,
            .instructedPersonSignature
        ]
        return ordered.first { validationIssues.contains($0) }
    }

    func isInvalid(_ issue: BriefingValidationIssue) -> Bool {
        hasAttemptedCompletion && validationIssues.contains(issue)
    }

    var partners: [SAPBriefingPartner]
    var temporaryPartner: BriefingTemporaryPartner?
    var partnerSearchTerm2 = ""
    private(set) var itemStatus: OfflineWorkStatus?
    private var savedWorkID: UUID?

    init(source: Source, existingDraft: OfflineWorkItem? = nil, draftID: UUID? = nil) {
        self.source = source
        partners = source.partners
        selectedTemplateID = source.templates.first(where: \.isStandardBriefing)?.id ?? source.templates.first?.id ?? ""
        savedWorkID = existingDraft?.id ?? draftID
        itemStatus = existingDraft?.status
        guard let existingDraft, let draft = existingDraft.payload.briefing else { return }
        selectedBusinessEntityID = draft.businessEntityID
        if !draft.businessEntityID.isEmpty {
            partnerSearchTerm2 = Self.extractPropertyNumber(from: draft.businessEntityID)
        }
        selectedBuildingCode = draft.buildingCode
        selectedTemplateID = draft.templateID
        coordinator = draft.coordinator
        instructedPerson = draft.instructedPerson
        selectedPartnerID = draft.selectedPartnerID
        temporaryPartner = draft.temporaryPartner
        if let temporaryPartner { partners.append(temporaryPartner.asSAPPartner) }
        partnerEmail = draft.partnerEmail
        taskDescription = draft.taskDescription
        startDate = draft.startDate
        endDate = draft.endDate
        selectedOptionalSectionIDs = draft.selectedOptionalSectionIDs
        answerKeysByItemID = draft.answerKeysByItemID
        commentsByItemID = draft.commentsByItemID
        instructorSignature = draft.instructorSignature
        instructedPersonSignature = draft.instructedPersonSignature
    }
    var businessEntities: [Context] { Array(Dictionary(grouping: source.contexts, by: \.businessEntityID).values.compactMap(\.first)).sorted { $0.businessEntityTitle < $1.businessEntityTitle } }
    var availableBuildings: [Context] { source.contexts.filter { $0.businessEntityID == selectedBusinessEntityID }.sorted { $0.buildingTitle < $1.buildingTitle } }
    var selectedBusinessEntity: Context? { businessEntities.first { $0.businessEntityID == selectedBusinessEntityID } }
    var selectedContext: Context? { source.contexts.first { $0.businessEntityID == selectedBusinessEntityID && $0.buildingCode == selectedBuildingCode } }
    var defaultWorkPropertyNumber: String { partnerSearchTerm2 }

    nonisolated static func extractPropertyNumber(from businessEntityID: String) -> String {
        let segments = businessEntityID.split(separator: "-")
        for segment in segments.reversed() {
            let digits = segment.filter(\.isNumber)
            if !digits.isEmpty {
                return String(digits)
            }
        }
        return String(businessEntityID.filter(\.isNumber))
    }
    var template: SAPBriefingTemplate? { source.templates.first { $0.id == selectedTemplateID } }
    var selectedPartner: SAPBriefingPartner? { partners.first { $0.id == selectedPartnerID } }
    var instructorFirstName: String {
        source.workerProfile?.firstName.nonEmpty ?? source.workerName.nameParts.first
    }
    var instructorLastName: String {
        source.workerProfile?.lastName.nonEmpty ?? source.workerName.nameParts.last
    }
    var instructorName: String {
        let name = [instructorFirstName, instructorLastName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return name.isEmpty ? source.workerName : name
    }
    var organizationUnit: String { source.workerProfile?.organizationUnit ?? (source.isDemo ? "XPN Facility Management" : "") }
    var hasRequiredMasterData: Bool { !source.contexts.isEmpty && template != nil }
    var canSaveDraft: Bool { selectedContext != nil && template != nil }
    var canComplete: Bool { selectedContext != nil && template != nil }
    var isReadOnly: Bool {
        guard let itemStatus else { return false }
        return itemStatus != .draft
    }
    var activeSections: [SAPBriefingTemplateSection] { (template?.sections ?? []).filter { !$0.isOptional || selectedOptionalSectionIDs.contains($0.id) } }

    func selectBusinessEntity(_ value: String) {
        let selection = value.isEmpty ? nil : value
        guard selectedBusinessEntityID != selection else { return }
        selectedBusinessEntityID = selection
        selectedBuildingCode = nil
        selectedPartnerID = ""
        partnerEmail = ""
        if let selection {
            partnerSearchTerm2 = Self.extractPropertyNumber(from: selection)
        } else {
            partnerSearchTerm2 = ""
        }
    }
    func selectBuilding(_ value: String) { selectedBuildingCode = value.isEmpty ? nil : value }
    func setStartDate(_ value: Date) {
        startDate = value
        if endDate < value {
            endDate = value
        }
    }
    func setInstructedPerson(_ value: String) { instructedPerson = String(value.prefix(29)) }
    func setTaskDescription(_ value: String) { taskDescription = String(value.prefix(300)) }
    func selectPartner(_ value: String) {
        selectedPartnerID = value
        partnerEmail = selectedPartner?.email ?? ""
    }
    func addTemporaryPartner(_ partner: BriefingTemporaryPartner) {
        temporaryPartner = partner
        partners.append(partner.asSAPPartner)
        partners.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        selectedPartnerID = partner.id
        partnerEmail = partner.email
    }
    func setOptionalSection(_ id: String, selected: Bool) { if selected { selectedOptionalSectionIDs.insert(id) } else { selectedOptionalSectionIDs.remove(id) } }
    func number(for item: SAPBriefingTemplateItem, in section: SAPBriefingTemplateSection) -> String { guard item.rowType != .subposition else { return "" }; let itemIndex = section.items.firstIndex(where: { $0.id == item.id }) ?? 0; let number = section.items.prefix(itemIndex + 1).filter { $0.rowType != .subposition }.count; let sectionNumber = activeSections.firstIndex(where: { $0.id == section.id }).map { $0 + 1 } ?? 1; return "\(sectionNumber).\(String(format: "%02d", number))" }
    func setSignature(_ data: Data?, for role: BriefingSignatureRole) {
        if role == .instructor {
            instructorSignature = data
        } else {
            instructedPersonSignature = data
        }
    }
    func requestCompletion() {
        guard !isReadOnly, !isRenderingPDF else { return }
        finishCompletionRequest()
    }

    private func finishCompletionRequest() {
        guard !isRenderingPDF, validate(), let payload = makePDFPayload() else { return }
        isRenderingPDF = true
        Task {
            let artifact = await Task.detached(priority: .userInitiated) {
                try? LegacyBriefingPDFRenderer().render(payload)
            }.value
            isRenderingPDF = false
            guard let artifact else {
                instructorSignature = nil
                instructedPersonSignature = nil
                validationMessage = String(localized: "briefing.pdf.createFailed")
                return
            }
            pdfArtifact = artifact
        }
    }
    func saveDraft(using store: OfflineWorkStore) async {
        guard !isReadOnly else { return }
        guard let payload = draftPayload() else {
            validationMessage = String(localized: "briefing.draft.contextRequired")
            return
        }
        do {
            let item = try await store.saveBriefing(id: savedWorkID, payload: payload, status: .draft)
            savedWorkID = item.id
            itemStatus = item.status
            validationMessage = String(localized: "briefing.draft.saved")
        } catch {
            validationMessage = String(localized: "briefing.draft.saveFailed")
        }
    }
    func markPendingSynchronization(using store: OfflineWorkStore) async -> Bool {
        guard !isReadOnly, var payload = draftPayload() else { return false }
        payload.completedAt = pdfArtifact?.createdAt ?? .now
        do {
            let item = try await store.saveBriefing(
                id: savedWorkID,
                payload: payload,
                status: .pendingSynchronization
            )
            savedWorkID = item.id
            itemStatus = item.status
            return true
        } catch {
            validationMessage = String(localized: "briefing.completed.saveFailed")
            return false
        }
    }

    private func validate() -> Bool {
        hasAttemptedCompletion = true
        let isValid = validationIssues.isEmpty
        if !isValid {
            validationMessage = String(localized: "briefing.validation.message")
        }
        return isValid
    }
    private func draftPayload() -> BriefingDraftPayload? { guard let context = selectedContext, let template else { return nil }; return BriefingDraftPayload(templateID: template.id, businessEntityID: context.businessEntityID, businessEntityTitle: context.businessEntityTitle, buildingCode: context.buildingCode, buildingTitle: context.buildingTitle, coordinator: coordinator, instructedPerson: instructedPerson, selectedPartnerID: selectedPartnerID, temporaryPartner: temporaryPartner, partnerEmail: partnerEmail, taskDescription: taskDescription, startDate: startDate, endDate: endDate, selectedOptionalSectionIDs: selectedOptionalSectionIDs, answerKeysByItemID: answerKeysByItemID, commentsByItemID: commentsByItemID, instructorSignature: instructorSignature, instructedPersonSignature: instructedPersonSignature, completedAt: nil) }
    func makePDFPayload() -> BriefingPDFPayload? {
        guard
            let draft = draftPayload(),
            let template,
            let partner = selectedPartner,
            let instructorSignature,
            let instructedPersonSignature
        else {
            validationMessage = String(localized: "briefing.pdf.createFailed")
            return nil
        }

        let renderedSections = activeSections.enumerated().map { sectionOffset, section in
            let originalIndex = template.sections.firstIndex(where: { $0.id == section.id }) ?? sectionOffset
            let sectionNumber = section.items.isEmpty ? 0 : (originalIndex + 1)
            let renderedItems = section.items.enumerated().map { itemOffset, item in
                let number: String
                if item.rowType == .subposition {
                    number = ""
                } else {
                    let positionNumber = section.items
                        .prefix(itemOffset + 1)
                        .filter { $0.rowType != .subposition }
                        .count
                    number = "\(sectionOffset + 1).\(String(format: "%02d", positionNumber))"
                }
                return BriefingPDFPayload.Item(
                    id: item.id,
                    number: number,
                    rowType: item.rowType,
                    title: item.title,
                    answer: pdfAnswer(for: item),
                    comment: commentsByItemID[item.id] ?? "",
                    warningSymbolID: item.warningSymbolID
                )
            }
            return BriefingPDFPayload.Section(
                id: section.id,
                title: section.title,
                subtitle: section.subtitle,
                number: sectionNumber,
                items: renderedItems
            )
        }

        return BriefingPDFPayload(
            planNumber: template.planNumber,
            instructorName: instructorName,
            organizationUnit: organizationUnit,
            coordinator: draft.coordinator,
            partnerName: partner.name,
            partnerAddress: partner.address,
            instructedPerson: draft.instructedPerson,
            businessEntity: draft.businessEntityTitle,
            workLocation: draft.buildingTitle,
            taskDescription: draft.taskDescription,
            startDate: draft.startDate,
            endDate: draft.endDate,
            completedAt: .now,
            instructorSignature: instructorSignature,
            instructedPersonSignature: instructedPersonSignature,
            sections: renderedSections
        )
    }

    private func pdfAnswer(
        for item: SAPBriefingTemplateItem
    ) -> BriefingPDFPayload.Item.Answer {
        guard
            let selectedKey = answerKeysByItemID[item.id],
            let option = item.answerOptions.first(where: { $0.key == selectedKey })
        else {
            return .notApplicable
        }
        if option.isAffirmativeBriefingAnswer {
            return .yes(key: option.key, title: option.title)
        }
        return .no(key: option.key, title: option.title)
    }
}
