import SwiftUI

struct ElectricalSafetyWorkflowView: View {
    let workspace: FacilityDemoViewModel
    let onClose: () -> Void
    @State private var viewModel: ElectricalSafetyViewModel
    @State private var isSaveDraftConfirmationPresented = false
    @State private var isShowingPartnerPicker = false
    @State private var isShowingBusinessEntityPicker = false
    @State private var isEditingInstructionNotes = false

    init(
        workspace: FacilityDemoViewModel,
        existingDraft: OfflineWorkItem? = nil,
        onClose: @escaping () -> Void
    ) {
        self.workspace = workspace
        self.onClose = onClose
        _viewModel = State(
            initialValue: ElectricalSafetyViewModel(
                source: .make(for: workspace),
                existingDraft: existingDraft
            )
        )
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        VStack(spacing: 0) {
            SafetyFormPageHeader(
                title: "electricalSafety.form.title",
                subtitle: "electricalSafety.form.subtitle",
                onClose: onClose
            )

            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if viewModel.source.contexts.isEmpty || viewModel.source.partners.isEmpty {
                        masterDataBanner
                    }
                    commonHeader
                    workplace
                    plannedMethods
                    briefing
                    signatureStage(
                        title: "electricalSafety.handover",
                        date: $viewModel.draft.handoverDate,
                        first: .handoverSystemResponsible,
                        second: .handoverWorkResponsible
                    )
                    signatureStage(
                        title: "electricalSafety.return",
                        date: $viewModel.draft.returnDate,
                        first: .returnSystemResponsible,
                        second: .returnWorkResponsible
                    )
                }
                .facilityPageContent()
                // Keep the parent ScrollView interactive so a closed form can
                // still be reviewed from Local work.
                .disabled(viewModel.isReadOnly)
            }
            .scrollDismissesKeyboard(.interactively)
            .alert(viewModel.alertTitle, isPresented: Binding(
                get: { viewModel.validationMessage != nil },
                set: { if !$0 { viewModel.dismissAlert() } }
            )) {
                Button("common.ok", role: .cancel) {
                    dismissValidationAndScroll(using: proxy)
                }
            } message: {
                Text(viewModel.validationMessage ?? "")
            }
            }
        }
        .background(FacilityTheme.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            SafetyFormActionBar(
                canSaveDraft: true,
                canComplete: viewModel.draft.context != nil,
                isBusy: viewModel.isSaving,
                saveDraft: {
                    isSaveDraftConfirmationPresented = true
                },
                complete: {
                    Task { await viewModel.complete() }
                },
                isReadOnly: viewModel.isReadOnly,
                back: onClose
            )
        }
        .facilitySaveDraftConfirmation(isPresented: $isSaveDraftConfirmationPresented) {
            Task {
                if await viewModel.saveDraft(using: workspace.offlineWorkStore) {
                    viewModel.dismissAlert()
                    onClose()
                }
            }
        }
        .overlay {
            ZStack {
                LegacyBriefingPartnerEditorOverlay(isPresented: isShowingBusinessEntityPicker) {
                    SafetyFormBusinessEntityPicker(
                        contexts: viewModel.source.contexts,
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
                        partners: viewModel.source.partners,
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
        .overlay {
            if isEditingInstructionNotes {
                NotificationCommentEditorOverlay(
                    comment: $viewModel.draft.instructionNotes,
                    dismiss: { isEditingInstructionNotes = false }
                )
            }
        }
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
    }

    private func dismissValidationAndScroll(using proxy: ScrollViewProxy) {
        let issue = viewModel.validationIssueToReveal
        viewModel.dismissAlert()

        guard let issue else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(issue, anchor: .center)
            }
        }
    }

    private var masterDataBanner: some View {
        Label("safetyForms.masterData.unavailable", systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(FacilityTheme.orange)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FacilityTheme.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var commonHeader: some View {
        @Bindable var viewModel = viewModel
        return StandardFormHeader(
            partner: viewModel.draft.partner,
            partnerInvalid: viewModel.isInvalid(.partner),
            partnerID: ElectricalSafetyValidationIssue.partner,
            isPartnerSelectionEnabled: viewModel.selectedBusinessEntityID != nil,
            selectPartner: { isShowingPartnerPicker = true },
            instructorFirstName: viewModel.source.instructorFirstName,
            instructorLastName: viewModel.source.instructorLastName,
            coordinator: $viewModel.draft.coordinator,
            coordinatorRequired: true,
            coordinatorInvalid: viewModel.isInvalid(.coordinator),
            coordinatorID: ElectricalSafetyValidationIssue.coordinator,
            dateFrom: Binding(get: { viewModel.draft.executionStart }, set: viewModel.setExecutionStart),
            dateTo: $viewModel.draft.executionEnd,
            dateRangeInvalid: viewModel.isInvalid(.executionRange),
            dateRangeID: ElectricalSafetyValidationIssue.executionRange,
            workDescription: Binding(get: { viewModel.draft.workDescription }, set: viewModel.setWorkDescription),
            workDescriptionInvalid: viewModel.isInvalid(.workDescription),
            workDescriptionID: ElectricalSafetyValidationIssue.workDescription,
            instructedPerson: Binding(get: { viewModel.draft.instructedPerson }, set: viewModel.setInstructedPerson),
            instructedPersonInvalid: viewModel.isInvalid(.instructedPerson),
            instructedPersonID: ElectricalSafetyValidationIssue.instructedPerson
        ) {
            SafetyFormContextCard(
                businessEntities: viewModel.businessEntities,
                buildings: viewModel.buildings,
                selectedBusinessEntityID: viewModel.selectedBusinessEntityID,
                selectedBuildingCode: viewModel.selectedBuildingCode,
                selectedContext: viewModel.draft.context,
                isInvalid: viewModel.isInvalid(.context),
                showBusinessEntityPicker: { isShowingBusinessEntityPicker = true },
                selectBuilding: viewModel.selectBuilding
            )
            .id(ElectricalSafetyValidationIssue.context)
        }
    }

    private var workplace: some View {
        @Bindable var viewModel = viewModel
        return SafetyFormCard("electricalSafety.workplace") {
            SafetyFormFieldPair {
                SafetyFormField("firePermit.businessEntity") {
                    Text(viewModel.draft.context?.businessEntityTitle ?? "").briefingReadOnlyValue()
                }
            } trailing: {
                SafetyFormField("firePermit.building") {
                    Text(viewModel.draft.context?.buildingTitle ?? "").briefingReadOnlyValue()
                }
            }
            SafetyFormField("firePermit.functionalLocation") {
                Text(viewModel.draft.context?.functionalLocationTitle ?? "").briefingReadOnlyValue()
            }
            SafetyFormField("electricalSafety.workplaceDetails") {
                SafetyFormTextEditor(text: $viewModel.draft.workplace)
            }
            SafetyFormField("electricalSafety.electricalWork") {
                SafetyFormTextEditor(text: $viewModel.draft.electricalWork)
            }
            responsiblePerson(
                title: "electricalSafety.systemResponsible",
                person: $viewModel.draft.systemResponsible,
                invalid: viewModel.isInvalid(.systemResponsibleName),
                id: .systemResponsibleName,
                setName: viewModel.updateSystemResponsibleName
            )
            responsiblePerson(
                title: "electricalSafety.workResponsible",
                person: $viewModel.draft.workResponsible,
                invalid: viewModel.isInvalid(.workResponsibleName),
                id: .workResponsibleName,
                setName: viewModel.updateWorkResponsibleName
            )
        }
    }

    private var plannedMethods: some View {
        @Bindable var viewModel = viewModel
        return SafetyFormCard("electricalSafety.plannedMethods") {
            Toggle("electricalSafety.method.deEnergized", isOn: $viewModel.draft.workDeEnergized)
            Toggle("electricalSafety.method.live", isOn: $viewModel.draft.workLive)
            Toggle("electricalSafety.method.nearLive", isOn: $viewModel.draft.workNearLiveParts)
        }
    }

    private var briefing: some View {
        @Bindable var viewModel = viewModel
        return SafetyFormCard("electricalSafety.briefing") {
            Text("electricalSafety.briefing.explanation")
            Toggle("electricalSafety.workResponsible", isOn: $viewModel.draft.instructedWorkResponsible)
            Toggle("electricalSafety.additionalWorkers", isOn: $viewModel.draft.instructedAdditionalWorkers)
            SafetyFormField("electricalSafety.notes") {
                HStack(alignment: .center, spacing: 14) {
                    NotificationCommentButton(
                        hasComment: !viewModel.draft.instructionNotes.isEmpty,
                        isReadOnly: viewModel.isReadOnly,
                        action: { isEditingInstructionNotes = true }
                    )
                    Text(viewModel.draft.instructionNotes.isEmpty
                         ? String(localized: "notifications.detail.commentEditor.placeholder")
                         : viewModel.draft.instructionNotes)
                        .foregroundStyle(viewModel.draft.instructionNotes.isEmpty ? .secondary : .primary)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
        }
    }

    private func responsiblePerson(
        title: LocalizedStringKey,
        person: Binding<ElectricalSafetyDraftPayload.ResponsiblePerson>,
        invalid: Bool,
        id: ElectricalSafetyValidationIssue,
        setName: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Text(title).font(.headline).foregroundStyle(FacilityTheme.blue)
            SafetyFormField("electricalSafety.name", required: true) {
                TextField(
                    "electricalSafety.name",
                    text: Binding(get: { person.wrappedValue.name }, set: setName)
                )
                .briefingFieldChrome(invalid: invalid)
                .id(id)
            }
            SafetyFormFieldPair {
                SafetyFormField("electricalSafety.company") {
                    TextField("electricalSafety.company", text: person.company)
                        .briefingFieldChrome(invalid: false)
                }
            } trailing: {
                SafetyFormField("electricalSafety.phone") {
                    TextField("electricalSafety.phone", text: person.telephone)
                        .keyboardType(.phonePad)
                        .briefingFieldChrome(invalid: false)
                }
            }
        }
    }

    private func signatureStage(
        title: LocalizedStringKey,
        date: Binding<Date>,
        first: ElectricalSafetySignatureSlot,
        second: ElectricalSafetySignatureSlot
    ) -> some View {
        SafetyFormCard(title) {
            SafetyFormField("electricalSafety.dateTime") {
                DatePicker(
                    "electricalSafety.dateTime",
                    selection: date,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .briefingFieldChrome(invalid: false)
            }
            VStack(spacing: 16) {
                signature(first)
                signature(second)
            }
        }
    }

    private func signature(_ slot: ElectricalSafetySignatureSlot) -> some View {
        let signerName = viewModel.signerName(for: slot)
        return BriefingInlineSignatureField(
            title: LocalizedStringKey(slot.titleKey),
            signatureData: Binding(
                get: { viewModel.draft.signatures[slot]?.pngData },
                set: { viewModel.setSignature($0, for: slot) }
            ),
            isInvalid: viewModel.isInvalid(.signature(slot)),
            inputRequirement: SignatureInputRequirement(
                signerName: signerName,
                requiredNameField: String(localized: String.LocalizationValue(slot.signerNameFieldKey))
            )
        )
        .frame(maxWidth: .infinity)
        .id(ElectricalSafetyValidationIssue.signature(slot))
    }
}
