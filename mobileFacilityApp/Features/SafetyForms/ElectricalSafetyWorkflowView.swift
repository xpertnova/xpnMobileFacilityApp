import SwiftUI

struct ElectricalSafetyWorkflowView: View {
    let workspace: FacilityDemoViewModel
    let onClose: () -> Void
    @State private var viewModel: ElectricalSafetyViewModel
    @State private var isShowingPartnerPicker = false
    @State private var isShowingBusinessEntityPicker = false

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
                isSidebarVisible: workspace.isSidebarVisible,
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
                .padding(28)
                .frame(maxWidth: 1280, alignment: .leading)
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
                isBusy: viewModel.isSaving,
                saveDraft: {
                    Task {
                        _ = await viewModel.saveDraft(using: workspace.offlineWorkStore)
                    }
                },
                complete: {
                    Task { await viewModel.complete() }
                }
            )
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
        return SafetyFormCard {
            SafetyFormFieldPair {
                SafetyFormField("externalCompany.name", required: true) {
                    SafetyFormPartnerField(
                        partner: viewModel.draft.partner,
                        isInvalid: viewModel.isInvalid(.partner),
                        action: { isShowingPartnerPicker = true }
                    )
                    .id(ElectricalSafetyValidationIssue.partner)
                }
            } trailing: {
                SafetyFormField("safetyInstrucForm.instructor") {
                    Text(viewModel.draft.instructorName)
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
                selectedContext: viewModel.draft.context,
                isInvalid: viewModel.isInvalid(.context),
                showBusinessEntityPicker: { isShowingBusinessEntityPicker = true },
                selectBuilding: viewModel.selectBuilding,
                selectContext: viewModel.selectContext
            )
            .id(ElectricalSafetyValidationIssue.context)

            SafetyFormFieldPair {
                SafetyFormField("safetyInstrucForm.workOrder.timeSpan1", required: true) {
                    DatePicker(
                        "safetyInstrucForm.workOrder.timeSpan1",
                        selection: $viewModel.draft.executionStart,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .briefingFieldChrome(invalid: viewModel.isInvalid(.executionRange))
                    .id(ElectricalSafetyValidationIssue.executionRange)
                }
            } trailing: {
                SafetyFormField("safetyInstrucForm.workOrder.timeSpan2", required: true) {
                    DatePicker(
                        "safetyInstrucForm.workOrder.timeSpan2",
                        selection: $viewModel.draft.executionEnd,
                        in: viewModel.draft.executionStart...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .briefingFieldChrome(invalid: viewModel.isInvalid(.executionRange))
                }
            }

            SafetyFormField("safetyInstrucForm.workOrder", required: true) {
                TextField(
                    "safetyInstrucForm.workOrder",
                    text: Binding(get: { viewModel.draft.workDescription }, set: viewModel.setWorkDescription)
                )
                .briefingFieldChrome(invalid: viewModel.isInvalid(.workDescription))
                .id(ElectricalSafetyValidationIssue.workDescription)
            }

            SafetyFormFieldPair {
                SafetyFormField("safetyInstrucForm.instructedEmployee", required: true) {
                    TextField(
                        "safetyInstrucForm.instructedEmployee",
                        text: Binding(get: { viewModel.draft.instructedPerson }, set: viewModel.setInstructedPerson)
                    )
                    .briefingFieldChrome(invalid: viewModel.isInvalid(.instructedPerson))
                    .id(ElectricalSafetyValidationIssue.instructedPerson)
                }
            } trailing: {
                SafetyFormField("externalCompany.eMail") {
                    TextField("externalCompany.eMail", text: $viewModel.draft.partnerEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .briefingFieldChrome(invalid: false)
                }
            }

            SafetyFormField("externalCompany.address") {
                Text(viewModel.draft.partner?.address ?? "")
                    .lineLimit(3)
                    .briefingReadOnlyValue()
            }

            SafetyFormFieldPair {
                SafetyFormField("safetyInstrucForm.orgUnit") {
                    Text(viewModel.draft.organizationUnit).briefingReadOnlyValue()
                }
            } trailing: {
                SafetyFormField("safetyInstrucForm.coordinator", required: true) {
                    TextField("safetyInstrucForm.coordinator", text: $viewModel.draft.coordinator)
                        .briefingFieldChrome(invalid: viewModel.isInvalid(.coordinator))
                        .id(ElectricalSafetyValidationIssue.coordinator)
                }
            }
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
                SafetyFormTextEditor(text: $viewModel.draft.instructionNotes, minimumHeight: 150)
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
            SafetyFormFieldPair {
                signature(first)
            } trailing: {
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
            isInvalid: viewModel.isInvalid(.signature(slot))
        )
        .allowsHitTesting(!signerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .opacity(signerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.62 : 1)
        .id(ElectricalSafetyValidationIssue.signature(slot))
    }
}
