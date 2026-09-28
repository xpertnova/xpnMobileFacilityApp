import SwiftUI

struct FirePermitWorkflowView: View {
    let workspace: FacilityDemoViewModel
    let onClose: () -> Void
    @State private var viewModel: FirePermitViewModel
    @State private var isShowingPartnerPicker = false
    @State private var isShowingBusinessEntityPicker = false

    init(workspace: FacilityDemoViewModel, onClose: @escaping () -> Void) {
        self.workspace = workspace
        self.onClose = onClose
        _viewModel = State(initialValue: FirePermitViewModel(source: .make(for: workspace)))
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        VStack(spacing: 0) {
            SafetyFormPageHeader(
                title: "forms.fire.title",
                subtitle: "forms.fire.subtitle",
                onClose: onClose
            )

            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if viewModel.source.contexts.isEmpty || viewModel.source.partners.isEmpty {
                        masterDataBanner
                    }
                    commonHeader
                    permitHeading
                    workAndLocation
                    fireSafety
                    explosionSafety
                    alarm
                    permit
                }
                .facilityPageContent()
            }
            .scrollDismissesKeyboard(.interactively)
            .alert("forms.fire.title", isPresented: Binding(
                get: { viewModel.validationMessage != nil },
                set: { if !$0 { viewModel.validationMessage = nil } }
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
                canSaveDraft: false,
                canComplete: viewModel.record.context != nil,
                isBusy: viewModel.isRenderingPDF,
                saveDraft: nil,
                complete: viewModel.complete
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
        .overlay {
            if viewModel.isRenderingPDF { BriefingPDFRenderingOverlay() }
        }
        .fullScreenCover(item: $viewModel.pdfArtifact) { artifact in
            BriefingPDFPreview(artifact: artifact) {
                Task {
                    if await viewModel.saveClosed(using: workspace.offlineWorkStore) {
                        onClose()
                    } else {
                        viewModel.pdfArtifact = nil
                    }
                }
            }
        }
    }

    private func dismissValidationAndScroll(using proxy: ScrollViewProxy) {
        let issue = viewModel.firstValidationIssue
        viewModel.validationMessage = nil

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
            partner: viewModel.record.partner,
            partnerInvalid: viewModel.isInvalid(.partner),
            partnerID: FirePermitValidationIssue.partner,
            isPartnerSelectionEnabled: viewModel.selectedBusinessEntityID != nil,
            selectPartner: { isShowingPartnerPicker = true },
            instructorFirstName: viewModel.source.instructorFirstName,
            instructorLastName: viewModel.source.instructorLastName,
            coordinator: $viewModel.record.coordinator,
            coordinatorRequired: true,
            coordinatorInvalid: viewModel.isInvalid(.coordinator),
            coordinatorID: FirePermitValidationIssue.coordinator,
            dateFrom: Binding(get: { viewModel.record.executionStart }, set: viewModel.setExecutionStart),
            dateTo: $viewModel.record.executionEnd,
            dateRangeInvalid: viewModel.isInvalid(.executionRange),
            dateRangeID: FirePermitValidationIssue.executionRange,
            workDescription: Binding(get: { viewModel.record.workDescription }, set: viewModel.setWorkDescription),
            workDescriptionInvalid: viewModel.isInvalid(.workDescription),
            workDescriptionID: FirePermitValidationIssue.workDescription,
            instructedPerson: Binding(get: { viewModel.record.instructedPerson }, set: viewModel.setInstructedPerson),
            instructedPersonInvalid: viewModel.isInvalid(.instructedPerson),
            instructedPersonID: FirePermitValidationIssue.instructedPerson
        ) {
                SafetyFormContextCard(
                    businessEntities: viewModel.businessEntities,
                    buildings: viewModel.buildings,
                    selectedBusinessEntityID: viewModel.selectedBusinessEntityID,
                    selectedBuildingCode: viewModel.selectedBuildingCode,
                    selectedContext: viewModel.record.context,
                    isInvalid: viewModel.isInvalid(.context),
                    showBusinessEntityPicker: { isShowingBusinessEntityPicker = true },
                    selectBuilding: viewModel.selectBuilding
                )
                .id(FirePermitValidationIssue.context)
        }
    }

    private var permitHeading: some View {
        SafetyFormCard {
            VStack(spacing: 10) {
                Text("firePermit.document.title")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(FacilityTheme.red)
                    .multilineTextAlignment(.center)
                Text("firePermit.preview.notice")
                    .foregroundStyle(FacilityTheme.red)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var workAndLocation: some View {
        @Bindable var viewModel = viewModel
        return VStack(spacing: 18) {
            SafetyFormCard("firePermit.section.workplace") {
                subsection("firePermit.workType") {
                    ForEach(FirePermitWorkType.allCases) { workType in
                        Toggle(LocalizedStringKey(workType.titleKey), isOn: workTypeBinding(workType))
                    }
                    Toggle("firePermit.other", isOn: Binding(
                        get: { viewModel.record.hasOtherWorkType },
                        set: {
                            viewModel.record.hasOtherWorkType = $0
                            if !$0 { viewModel.record.otherWorkType = "" }
                        }
                    ))
                    if viewModel.record.hasOtherWorkType {
                        TextField("firePermit.other", text: $viewModel.record.otherWorkType)
                            .briefingFieldChrome(invalid: false)
                    }
                }

                subsection("firePermit.workplace") {
                    SafetyFormFieldPair {
                        SafetyFormField("firePermit.businessEntity") {
                            Text(viewModel.record.context?.businessEntityTitle ?? "").briefingReadOnlyValue()
                        }
                    } trailing: {
                        SafetyFormField("firePermit.building") {
                            Text(viewModel.record.context?.buildingTitle ?? "").briefingReadOnlyValue()
                        }
                    }
                    SafetyFormField("firePermit.functionalLocation") {
                        Text(viewModel.record.context?.functionalLocationTitle ?? "").briefingReadOnlyValue()
                    }
                    Text("firePermit.spatialExtent").font(.headline)
                    SafetyFormFieldPair {
                        dimensionField("firePermit.radius", value: viewModel.record.radiusMetres, keyPath: \.radiusMetres)
                    } trailing: {
                        HStack(alignment: .top, spacing: 16) {
                            dimensionField("firePermit.height", value: viewModel.record.heightMetres, keyPath: \.heightMetres)
                            dimensionField("firePermit.depth", value: viewModel.record.depthMetres, keyPath: \.depthMetres)
                        }
                    }
                }
            }

            SafetyFormCard("firePermit.workOrder") {
                SafetyFormTextEditor(
                    text: Binding(get: { viewModel.record.workDescription }, set: viewModel.setWorkDescription),
                    invalid: viewModel.isInvalid(.workDescription)
                )
                signerField(.onSiteWorker, title: "firePermit.performedBy")
                Text("firePermit.performedByHint")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var fireSafety: some View {
        @Bindable var viewModel = viewModel
        return SafetyFormCard("firePermit.section.fireSafety") {
            subsection("firePermit.subsection.fireHazard") {
                measures([.removeCombustibles, .removeCombustibleCoverings, .coverFixedCombustibles, .sealOpenings])
                otherMeasure(
                    enabled: Binding(get: { viewModel.record.otherFireHazardEnabled }, set: {
                        viewModel.record.otherFireHazardEnabled = $0
                        if !$0 { viewModel.record.otherFireHazard = "" }
                    }),
                    text: $viewModel.record.otherFireHazard
                )
                signerField(.fireHazardMeasures, title: "firePermit.measurePerformedBy")
                dateField("firePermit.completedOn", selection: $viewModel.record.fireHazardCompletedOn)
                signature(.fireHazardMeasures)
            }

            subsection("firePermit.subsection.extinguishing") {
                measures([.water, .foam, .powder, .carbonDioxide, .connectedWaterHose, .waterFilledBucket, .notifyFireBrigade])
                otherMeasure(
                    enabled: Binding(get: { viewModel.record.otherExtinguishingEnabled }, set: {
                        viewModel.record.otherExtinguishingEnabled = $0
                        if !$0 { viewModel.record.otherExtinguishing = "" }
                    }),
                    text: $viewModel.record.otherExtinguishing
                )
                signerField(.extinguishingMedia, title: "firePermit.measurePerformedBy")
                dateField("firePermit.completedOn", selection: $viewModel.record.extinguishingCompletedOn)
                signature(.extinguishingMedia)
            }

            subsection("firePermit.subsection.fireAlarm") {
                measure(.fireAlarmLoopsOutOfService)
                signerField(.fireAlarmSystem, title: "firePermit.measurePerformedBy")
                Text("firePermit.responsibleInformed").font(.footnote).foregroundStyle(.secondary)
                signature(.fireAlarmSystem)
            }

            subsection("firePermit.subsection.fireWatchDuring") {
                measure(.fireWatchDuringWork)
                SafetyFormField("firePermit.fireWatchName") {
                    TextField("firePermit.fireWatchName", text: $viewModel.record.fireWatchName)
                        .briefingFieldChrome(invalid: false)
                }
            }

            subsection("firePermit.subsection.fireWatchAfter") {
                measure(.fireWatchAfterWork)
                SafetyFormFieldPair {
                    SafetyFormField("firePermit.fireWatchDuration") {
                        TextField(
                            "firePermit.hours",
                            text: Binding(get: { viewModel.record.fireWatchDurationHours }, set: viewModel.setFireWatchDuration)
                        )
                        .keyboardType(.numberPad)
                        .briefingFieldChrome(invalid: false)
                    }
                } trailing: {
                    SafetyFormField("firePermit.fireWatchName") {
                        TextField("firePermit.fireWatchName", text: $viewModel.record.afterWorkFireWatchName)
                            .briefingFieldChrome(invalid: false)
                    }
                }
            }
        }
    }

    private var explosionSafety: some View {
        @Bindable var viewModel = viewModel
        return SafetyFormCard("firePermit.section.explosionSafety") {
            subsection("firePermit.subsection.explosionHazard") {
                measures([.removeExplosives, .removePipelineExplosionHazard, .sealFixedContainers, .ventilationMeasures, .gasDetectors])
                if viewModel.record.measures[.gasDetectors, default: false] {
                    SafetyFormField("firePermit.gasDetectorDetails") {
                        TextField("firePermit.gasDetectorDetails", text: $viewModel.record.gasDetectorDetails)
                            .briefingFieldChrome(invalid: false)
                    }
                }
                otherMeasure(
                    enabled: Binding(get: { viewModel.record.otherExplosionEnabled }, set: {
                        viewModel.record.otherExplosionEnabled = $0
                        if !$0 { viewModel.record.otherExplosion = "" }
                    }),
                    text: $viewModel.record.otherExplosion
                )
                signerField(.explosionHazardMeasures, title: "firePermit.measurePerformedBy")
                dateField("firePermit.completedOn", selection: $viewModel.record.explosionCompletedOn)
                signature(.explosionHazardMeasures)
            }
            subsection("firePermit.subsection.monitoring") {
                SafetyFormField("firePermit.monitoring") {
                    TextField("firePermit.performedBy", text: $viewModel.record.monitoringContractorName)
                        .briefingFieldChrome(invalid: false)
                }
            }
        }
    }

    private var alarm: some View {
        @Bindable var viewModel = viewModel
        return SafetyFormCard("firePermit.section.alarm") {
            Text("firePermit.alarm.nearest")
            SafetyFormField("firePermit.alarm.manualCallPoint") {
                TextField("firePermit.alarm.manualCallPoint", text: $viewModel.record.manualCallPointLocation)
                    .briefingFieldChrome(invalid: false)
            }
            SafetyFormField("firePermit.alarm.mobileTelephone") {
                TextField("firePermit.alarm.mobileTelephone", text: $viewModel.record.mobileTelephone)
                    .keyboardType(.phonePad)
                    .briefingFieldChrome(invalid: false)
            }
            HStack {
                Text("firePermit.emergencyNumber")
                Spacer()
                Text("(0) 112").font(.title.bold()).foregroundStyle(FacilityTheme.red)
            }
        }
    }

    private var permit: some View {
        @Bindable var viewModel = viewModel
        return SafetyFormCard("firePermit.section.permit") {
            subsection("firePermit.permitIssuer") {
                signerField(.permitIssuer, title: "firePermit.permitIssuer")
                dateField("firePermit.completedOn", selection: $viewModel.record.permitIssuedOn)
                Text("firePermit.permitIssuerConfirmation").font(.subheadline.weight(.medium))
                signature(.permitIssuer)
            }
            subsection("firePermit.contractor") {
                signerField(.contractor, title: "firePermit.contractor")
                dateField("firePermit.completedOn", selection: $viewModel.record.contractorSignedOn)
                Text("firePermit.contractorConfirmation").font(.subheadline.weight(.medium))
                signature(.contractor)
                signerField(.onSiteWorker, title: "firePermit.onSiteWorkerConfirmation")
                signature(.onSiteWorker)
            }
        }
    }

    private func subsection<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
            Text(title).font(.headline.italic()).foregroundStyle(FacilityTheme.ink)
            content()
        }
    }

    @ViewBuilder
    private func measures(_ values: [FirePermitMeasure]) -> some View {
        ForEach(values) { measure in self.measure(measure) }
    }

    private func measure(_ value: FirePermitMeasure) -> some View {
        @Bindable var viewModel = viewModel
        return SafetyFormYesNo(
            title: LocalizedStringKey(value.titleKey),
            isYes: Binding(
                get: { viewModel.record.measures[value, default: false] },
                set: { viewModel.record.measures[value] = $0 }
            )
        )
    }

    private func otherMeasure(enabled: Binding<Bool>, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("firePermit.other", isOn: enabled)
            if enabled.wrappedValue {
                TextField("firePermit.other", text: text).briefingFieldChrome(invalid: false)
            }
        }
    }

    private func signerField(_ slot: FirePermitSignatureSlot, title: LocalizedStringKey) -> some View {
        SafetyFormField(title, required: true) {
            TextField(
                title,
                text: Binding(
                    get: { viewModel.signerName(for: slot) },
                    set: { viewModel.updateSignerName($0, for: slot) }
                )
            )
            .briefingFieldChrome(invalid: viewModel.isInvalid(.signerName(slot)))
            .id(FirePermitValidationIssue.signerName(slot))
        }
    }

    private func signature(_ slot: FirePermitSignatureSlot) -> some View {
        let signerName = viewModel.signerName(for: slot)
        return BriefingInlineSignatureField(
            title: LocalizedStringKey(slot.titleKey),
            signatureData: Binding(
                get: { viewModel.record.signatures[slot]?.pngData },
                set: { viewModel.setSignature($0, for: slot) }
            ),
            isInvalid: viewModel.isInvalid(.signature(slot)),
            inputRequirement: SignatureInputRequirement(
                signerName: signerName,
                requiredNameField: String(localized: String.LocalizationValue(slot.signerNameFieldKey), bundle: .appLanguage)
            )
        )
        .id(FirePermitValidationIssue.signature(slot))
    }

    private func dateField(_ title: LocalizedStringKey, selection: Binding<Date>) -> some View {
        SafetyFormField(title) {
            DatePicker(title, selection: selection, displayedComponents: .date)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .briefingFieldChrome(invalid: false)
        }
    }

    private func dimensionField(
        _ title: LocalizedStringKey,
        value: String,
        keyPath: WritableKeyPath<FirePermitRecord, String>
    ) -> some View {
        SafetyFormField(title) {
            TextField(title, text: Binding(get: { value }, set: { viewModel.setDimension($0, keyPath: keyPath) }))
                .keyboardType(.numberPad)
                .briefingFieldChrome(invalid: false)
        }
    }

    private func workTypeBinding(_ workType: FirePermitWorkType) -> Binding<Bool> {
        Binding(
            get: { viewModel.record.workTypes.contains(workType) },
            set: {
                if $0 { viewModel.record.workTypes.insert(workType) }
                else { viewModel.record.workTypes.remove(workType) }
            }
        )
    }
}

private struct SafetyFormYesNo: View {
    let title: LocalizedStringKey
    @Binding var isYes: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) { label; choices }
            VStack(alignment: .leading, spacing: 10) { label; choices }
        }
        .padding(.vertical, 3)
    }

    private var label: some View {
        Text(title).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var choices: some View {
        HStack(spacing: 0) {
            choice("firePermit.no", selected: !isYes) { isYes = false }
            choice("firePermit.yes", selected: isYes) { isYes = true }
        }
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(FacilityTheme.blue.opacity(0.45))
        }
    }

    private func choice(_ title: LocalizedStringKey, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .foregroundStyle(selected ? .white : FacilityTheme.blue)
            .frame(width: 82, height: 44)
            .background(selected ? FacilityTheme.blue : Color.clear)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
