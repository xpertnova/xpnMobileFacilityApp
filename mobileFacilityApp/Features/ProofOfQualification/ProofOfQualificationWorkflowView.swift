import SwiftUI

struct ProofOfQualificationWorkflowView: View {
  let workspace: FacilityDemoViewModel
  let onClose: () -> Void
  @State private var viewModel: ProofOfQualificationViewModel

  init(
    workspace: FacilityDemoViewModel,
    existingDraft: OfflineWorkItem? = nil,
    onClose: @escaping () -> Void
  ) {
    self.workspace = workspace
    self.onClose = onClose
    _viewModel = State(
      initialValue: ProofOfQualificationViewModel(
        source: .make(for: workspace),
        existingDraft: existingDraft
      )
    )
  }

  var body: some View {
    @Bindable var viewModel = viewModel
    ProofOfQualificationFormScreen(
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
      if viewModel.isRenderingPDF || viewModel.isSaving {
        BriefingPDFRenderingOverlay()
      }
    }
  }
}

private struct ProofOfQualificationFormScreen: View {
  let viewModel: ProofOfQualificationViewModel
  let workspace: FacilityDemoViewModel
  let onClose: () -> Void
  @State private var isShowingBusinessEntityPicker = false
  @State private var isShowingPartnerPicker = false

  var body: some View {
    @Bindable var viewModel = viewModel
    VStack(spacing: 0) {
      SafetyFormPageHeader(
        title: "qualification.form.title",
        subtitle: "qualification.form.subtitle",
        isSidebarVisible: workspace.isSidebarVisible,
        onClose: onClose
      )

      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            if !viewModel.hasRequiredMasterData {
              masterDataBanner
            }
            formCard
            checklist
            signatures
          }
          .padding(28)
          .frame(maxWidth: 1280, alignment: .leading)
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
    .safeAreaInset(edge: .bottom) {
      SafetyFormActionBar(
        canSaveDraft: false,
        isBusy: viewModel.isRenderingPDF || viewModel.isSaving,
        saveDraft: nil,
        complete: viewModel.requestCompletion
      )
    }
    .overlay {
      ZStack {
        LegacyBriefingPartnerEditorOverlay(isPresented: isShowingBusinessEntityPicker) {
          SafetyFormBusinessEntityPicker(
            contexts: viewModel.contexts,
            selectedBusinessEntityID: viewModel.selectedBusinessEntityID,
            onCancel: { isShowingBusinessEntityPicker = false },
            onSelect: {
              viewModel.selectBusinessEntity($0)
              isShowingBusinessEntityPicker = false
            }
          )
        }

        LegacyBriefingPartnerEditorOverlay(isPresented: isShowingPartnerPicker) {
          SafetyFormPartnerPicker(
            partners: viewModel.partners,
            onCancel: { isShowingPartnerPicker = false },
            onSelect: {
              viewModel.selectPartner($0)
              isShowingPartnerPicker = false
            }
          )
        }
      }
    }
    .animation(.easeOut(duration: 0.16), value: isShowingBusinessEntityPicker)
    .animation(.easeOut(duration: 0.16), value: isShowingPartnerPicker)
    .alert(
      "qualification.form.title",
      isPresented: Binding(
        get: { viewModel.validationMessage != nil },
        set: { if !$0 { viewModel.validationMessage = nil } }
      )
    ) {
      Button("common.ok", role: .cancel) { viewModel.validationMessage = nil }
    } message: {
      Text(viewModel.validationMessage ?? "")
    }
  }

  private var masterDataBanner: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: "arrow.triangle.2.circlepath")
        .font(.title3.weight(.semibold))
        .foregroundStyle(FacilityTheme.orange)
        .frame(width: 42, height: 42)
        .background(
          FacilityTheme.orange.opacity(0.11),
          in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      VStack(alignment: .leading, spacing: 4) {
        Text("qualification.masterData.unavailable.title")
          .font(.headline)
          .foregroundStyle(FacilityTheme.ink)
        Text("qualification.masterData.unavailable.message")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
    .padding(18)
    .background(
      FacilityTheme.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(FacilityTheme.orange.opacity(0.22))
    }
    .id(ProofOfQualificationValidationIssue.template)
  }

  private var formCard: some View {
    SafetyFormCard {
      SafetyFormFieldPair {
        SafetyFormField("externalCompany.name", required: true) {
          SafetyFormPartnerField(
            partner: viewModel.selectedPartner,
            isInvalid: viewModel.isInvalid(.partner),
            action: { isShowingPartnerPicker = true }
          )
          .id(ProofOfQualificationValidationIssue.partner)
        }
      } trailing: {
        SafetyFormField("qualification.instructor") {
          Text(viewModel.instructorName)
            .lineLimit(2)
            .briefingReadOnlyValue()
        }
      }

      SafetyFormContextCard(
        businessEntities: viewModel.businessEntities,
        buildings: viewModel.buildings,
        functionalLocations: viewModel.functionalLocations,
        selectedBusinessEntityID: viewModel.selectedBusinessEntityID,
        selectedBuildingCode: viewModel.selectedBuildingCode,
        selectedContext: viewModel.selectedContext,
        isInvalid: viewModel.isInvalid(.context),
        showBusinessEntityPicker: { isShowingBusinessEntityPicker = true },
        selectBuilding: viewModel.selectBuilding,
        selectContext: viewModel.selectContext
      )
      .id(ProofOfQualificationValidationIssue.context)

      SafetyFormFieldPair {
        SafetyFormField("qualification.instructedEmployee", required: true) {
          TextField(
            "qualification.instructedEmployee",
            text: Binding(
              get: { viewModel.contactPerson },
              set: viewModel.setContactPerson
            )
          )
          .briefingFieldChrome(invalid: viewModel.isInvalid(.contactPerson))
          .id(ProofOfQualificationValidationIssue.contactPerson)
        }
      } trailing: {
        SafetyFormField("externalCompany.eMail") {
          TextField(
            "externalCompany.eMail",
            text: Binding(
              get: { viewModel.partnerEmail },
              set: { viewModel.partnerEmail = $0 }
            )
          )
          .keyboardType(.emailAddress)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .briefingFieldChrome(invalid: false)
        }
      }

      SafetyFormField("externalCompany.address") {
        Text(viewModel.selectedPartner?.address ?? "")
          .lineLimit(3)
          .briefingReadOnlyValue()
      }

      SafetyFormFieldPair {
        SafetyFormField("qualification.organizationUnit") {
          Text(viewModel.organizationUnit)
            .lineLimit(2)
            .briefingReadOnlyValue()
        }
      } trailing: {
        SafetyFormField("qualification.coordinator") {
          TextField(
            "qualification.coordinator",
            text: Binding(
              get: { viewModel.coordinator },
              set: { viewModel.coordinator = $0 }
            )
          )
          .briefingFieldChrome(invalid: false)
        }
      }

      SafetyFormField("safetyInstrucForm.workOrder", required: true) {
        TextField(
          "safetyInstrucForm.workOrder",
          text: Binding(
            get: { viewModel.taskDescription },
            set: viewModel.setTaskDescription
          )
        )
        .briefingFieldChrome(invalid: viewModel.isInvalid(.taskDescription))
        .id(ProofOfQualificationValidationIssue.taskDescription)
      }

      SafetyFormFieldPair {
        SafetyFormField("qualification.executionStart", required: true) {
          DatePicker(
            "qualification.executionStart",
            selection: Binding(
              get: { viewModel.executionStart },
              set: {
                viewModel.executionStart = $0
                if viewModel.executionEnd < $0 { viewModel.executionEnd = $0 }
              }
            ),
            displayedComponents: .date
          )
          .labelsHidden()
          .frame(maxWidth: .infinity, alignment: .leading)
          .briefingFieldChrome(invalid: viewModel.isInvalid(.executionRange))
        }
      } trailing: {
        SafetyFormField("qualification.executionEnd", required: true) {
          DatePicker(
            "qualification.executionEnd",
            selection: Binding(
              get: { viewModel.executionEnd },
              set: { viewModel.executionEnd = $0 }
            ),
            displayedComponents: .date
          )
          .labelsHidden()
          .frame(maxWidth: .infinity, alignment: .leading)
          .briefingFieldChrome(invalid: viewModel.isInvalid(.executionRange))
          .id(ProofOfQualificationValidationIssue.executionRange)
        }
      }
    }
  }

  @ViewBuilder
  private var checklist: some View {
    if let template = viewModel.template {
      VStack(alignment: .leading, spacing: 12) {
        SectionTitle("qualification.checklist.title", subtitle: "qualification.checklist.subtitle")
        VStack(spacing: 0) {
          QualificationChecklistHeader()
          ForEach(Array(template.sections.enumerated()), id: \.element.id) { index, section in
            QualificationChecklistSectionHeader(number: index + 1, title: section.title)
            ForEach(section.items) { item in
              QualificationChecklistRow(
                item: item,
                number: viewModel.number(for: item, in: section),
                answerKey: viewModel.answerKeysByItemID[item.id],
                comment: viewModel.commentsByItemID[item.id] ?? "",
                setAnswer: { viewModel.setAnswer($0, itemID: item.id) },
                setComment: { viewModel.setComment($0, itemID: item.id) }
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
  }

  private var signatures: some View {
    VStack(alignment: .leading, spacing: 12) {
      SectionTitle("qualification.signatures.title", subtitle: "qualification.signatures.subtitle")
      VStack(spacing: 16) {
        signatureField(.coordinator)
        signatureField(.instructedPerson)
      }
    }
  }

  private func signatureField(_ role: ProofOfQualificationSignatureRole) -> some View {
    let issue: ProofOfQualificationValidationIssue =
      role == .coordinator
      ? .coordinatorSignature
      : .instructedPersonSignature
    return BriefingInlineSignatureField(
      title: LocalizedStringKey(role.titleKey),
      signatureData: Binding(
        get: {
          role == .coordinator
            ? viewModel.coordinatorSignature
            : viewModel.instructedPersonSignature
        },
        set: { viewModel.setSignature($0, for: role) }
      ),
      isInvalid: viewModel.isInvalid(issue)
    )
    .id(issue)
  }
}

private struct QualificationChecklistHeader: View {
  var body: some View {
    HStack(spacing: 0) {
      Text("briefing.checklist.number").frame(width: 70)
      Text("briefing.checklist.type").frame(maxWidth: .infinity, alignment: .leading)
      Text("qualification.checklist.answer").frame(width: 220)
      Text("briefing.checklist.info").frame(width: 64)
      Text("briefing.checklist.comment").frame(width: 96)
    }
    .font(.subheadline.weight(.medium))
    .foregroundStyle(FacilityTheme.ink)
    .padding(.horizontal, 12)
    .frame(minHeight: 52)
    .background(FacilityTheme.canvas)
    .overlay(alignment: .bottom) { Divider() }
  }
}

private struct QualificationChecklistSectionHeader: View {
  let number: Int
  let title: String
  @State private var isExpanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      let parts = title.components(separatedBy: "\n")
      let shortText = parts.first ?? title
      let hasDetails = parts.count > 1

      if hasDetails {
        Button {
          withAnimation(.easeInOut(duration: 0.2)) {
            isExpanded.toggle()
          }
        } label: {
          HStack(alignment: .top, spacing: 8) {
            Text("\(number). \(shortText)")
              .font(.headline)
              .foregroundStyle(FacilityTheme.ink)
              .fixedSize(horizontal: false, vertical: true)
              .multilineTextAlignment(.leading)
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
              .font(.caption.weight(.bold))
              .foregroundStyle(FacilityTheme.blue)
              .padding(.top, 4)
          }
        }
        .buttonStyle(.plain)
      } else {
        Text("\(number). \(shortText)")
          .font(.headline)
          .foregroundStyle(FacilityTheme.ink)
          .fixedSize(horizontal: false, vertical: true)
          .multilineTextAlignment(.leading)
      }

      if isExpanded, hasDetails {
        Text(parts.dropFirst().joined(separator: "\n"))
          .font(.subheadline)
          .lineSpacing(3)
          .foregroundStyle(FacilityTheme.ink)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
    .padding(.horizontal, 18)
    .padding(.vertical, 12)
    .background(FacilityTheme.navy.opacity(0.06))
    .overlay(alignment: .bottom) { Divider() }
    .accessibilityAddTraits(.isHeader)
  }
}

private struct QualificationChecklistRow: View {
  let item: SAPBriefingTemplateItem
  let number: String
  let answerKey: String?
  let comment: String
  let setAnswer: (String) -> Void
  let setComment: (String) -> Void
  @State private var referenceDocument: BriefingReferenceDocument?
  @State private var isEditingComment = false
  @State private var isExpanded = false

  var body: some View {
    HStack(alignment: .center, spacing: 0) {
      Text(number)
        .font(.subheadline.monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(width: 70)
      itemText
        .padding(.vertical, 20)
      answerControl.frame(width: 220)
      documentControl.frame(width: 64, height: 48)
      commentControl.frame(width: 96, height: 72)
    }
    .padding(.horizontal, 12)
    .frame(minHeight: 88, alignment: .top)
    .background(FacilityTheme.surface)
    .overlay(alignment: .bottom) { Divider() }
    .fullScreenCover(item: $referenceDocument) {
      BriefingReferenceDocumentPreview(document: $0)
    }
    .sheet(isPresented: $isEditingComment) {
      QualificationCommentEditor(initialComment: comment, onSave: setComment)
    }
  }

  private var itemText: some View {
    VStack(alignment: .leading, spacing: 6) {
      let parts = item.title.components(separatedBy: "\n")
      let shortText = parts.first ?? item.title
      let hasDetails = parts.count > 1

      if hasDetails {
        Button {
          withAnimation(.easeInOut(duration: 0.2)) {
            isExpanded.toggle()
          }
        } label: {
          HStack(alignment: .top, spacing: 8) {
            Text(shortText)
              .font(.body)
              .foregroundStyle(FacilityTheme.ink)
              .fixedSize(horizontal: false, vertical: true)
              .multilineTextAlignment(.leading)
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
              .font(.caption.weight(.bold))
              .foregroundStyle(FacilityTheme.blue)
              .padding(.top, 4)
          }
        }
        .buttonStyle(.plain)
      } else {
        Text(shortText)
          .font(.body)
          .foregroundStyle(FacilityTheme.ink)
          .fixedSize(horizontal: false, vertical: true)
          .multilineTextAlignment(.leading)
      }

      if isExpanded, hasDetails {
        Text(parts.dropFirst().joined(separator: "\n"))
          .font(.body)
          .lineSpacing(3)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var answerControl: some View {
    HStack(spacing: 4) {
      ForEach(item.answerOptions) { option in
        let isSelected = answerKey == option.key
        Button {
          setAnswer(option.key)
        } label: {
          Text(verbatim: option.title)
            .lineLimit(1)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? .white : .secondary)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(
              isSelected ? FacilityTheme.accent : Color.clear,
              in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
        }
        .buttonStyle(.plain)
      }
    }
    .padding(4)
    .background(
      Color(uiColor: .systemGray6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  @ViewBuilder
  private var documentControl: some View {
    if let document = BriefingReferenceDocument(symbolID: item.documentSymbolID) {
      Button {
        referenceDocument = document
      } label: {
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

  private var commentControl: some View {
    Button {
      isEditingComment = true
    } label: {
      Image(systemName: comment.isEmpty ? "pencil" : "pencil.circle.fill")
        .font(.system(size: 30, weight: .medium))
        .foregroundStyle(comment.isEmpty ? FacilityTheme.ink.opacity(0.75) : FacilityTheme.accent)
        .frame(width: 60, height: 60)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("briefing.checklist.comment")
  }
}

private struct QualificationCommentEditor: View {
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
        .background(FacilityTheme.canvas)
        .padding(24)
        .navigationTitle("briefing.checklist.comment")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("common.cancel", action: dismiss.callAsFunction)
          }
          ToolbarItem(placement: .confirmationAction) {
            Button("briefing.comment.save") {
              onSave(comment)
              dismiss()
            }
          }
        }
    }
    .presentationDetents([.medium, .large])
  }
}
