import SwiftUI
import UIKit

struct ManualCaptureView: View {
    let demo: FacilityDemoViewModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var defectModel: DefectCaptureViewModel
    @State private var meterModel: MeterReadingViewModel
    @State private var photoWorkspaceScope: LocalPhotoScope?
    @State private var isObjectPickerPresented = false
    @State private var objectSearchText = ""
    @State private var isMeterPointPickerPresented = false
    @State private var meterPointSearchText = ""
    @Namespace private var meterSegmentAnimation
    @FocusState private var focusedMeterField: MeterFormField?
    @State private var isMeterValueFocused = false

    init(demo: FacilityDemoViewModel) {
        self.demo = demo
        _defectModel = State(initialValue: DefectCaptureViewModel(
            sapDataStore: demo.sapDataStore,
            offlineWorkStore: demo.offlineWorkStore,
            photoStore: demo.photoAttachmentStore
        ))
        _meterModel = State(initialValue: MeterReadingViewModel(
            provider: demo.meterReferenceProvider,
            offlineWorkStore: demo.offlineWorkStore
        ))
    }

    var body: some View {
        ZStack {
            if let photoWorkspaceScope {
                LocalPhotoWorkspace(
                    scope: photoWorkspaceScope,
                    offlineWorkStore: demo.offlineWorkStore,
                    photoStore: demo.photoAttachmentStore,
                    legacyAttachmentIDs: photoWorkspaceScope.workflow == .defect ? defectModel.attachmentIDs : [],
                    isReadOnly: (photoWorkspaceScope.workflow == .defect && defectModel.isReadOnly)
                        || (photoWorkspaceScope.workflow == .meterReading && meterModel.isReadOnly),
                    close: { self.photoWorkspaceScope = nil }
                )
                .transition(PhotoWorkspaceMotion.destination)
                .zIndex(1)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        PageHeader("manual.title", subtitle: "manual.subtitle")
                        actionCards
                        selectedForm
                    }
                    .padding(28)
                    .frame(maxWidth: 1280, alignment: .leading)
                    .animation(.snappy(duration: 0.3, extraBounce: 0), value: demo.manualCaptureRoute)
                }
                .scrollDismissesKeyboard(.interactively)
                .transition(PhotoWorkspaceMotion.source)
            }
        }
        .animation(
            accessibilityReduceMotion ? nil : PhotoWorkspaceMotion.navigation,
            value: photoWorkspaceScope
        )
        .task(id: demo.manualCaptureRoute) {
            switch demo.manualCaptureRoute {
            case .landing:
                break
            case let .defect(id):
                await defectModel.load(itemID: id)
            case let .meterReading(id):
                await meterModel.load(itemID: id)
            }
        }
        .onChange(of: isObjectPickerPresented) { _, isPresented in
            if !isPresented { objectSearchText = "" }
        }
        .onChange(of: isMeterPointPickerPresented) { _, isPresented in
            if !isPresented { meterPointSearchText = "" }
        }
        .onChange(of: focusedMeterField) { _, newValue in
            if newValue != nil { isMeterValueFocused = false }
        }
        .onChange(of: isMeterValueFocused) { _, isFocused in
            if isFocused { focusedMeterField = nil }
        }
    }

    private var actionCards: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)], spacing: 18) {
            ManualCaptureActionCard(
                titleKey: "manual.action.defect.title",
                subtitleKey: "manual.action.defect.subtitle",
                symbol: "exclamationmark.triangle",
                tint: FacilityTheme.red,
                selected: isDefectSelected
            ) {
                withAnimation(.snappy(duration: 0.32, extraBounce: 0.04)) {
                    demo.openManualDefect()
                }
            }
            ManualCaptureActionCard(
                titleKey: "manual.action.meter.title",
                subtitleKey: "manual.action.meter.subtitle",
                symbol: "number",
                tint: FacilityTheme.blue,
                selected: isMeterSelected
            ) {
                withAnimation(.snappy(duration: 0.32, extraBounce: 0.04)) {
                    demo.openMeterReading()
                }
            }
            ManualCaptureActionCard(
                titleKey: "manual.action.masterData.title",
                subtitleKey: "manual.action.masterData.subtitle",
                symbol: "tag.fill",
                tint: FacilityTheme.accent,
                selected: false
            ) {
                demo.open(.technicalPlaces)
            }
        }
    }

    @ViewBuilder
    private var selectedForm: some View {
        ZStack(alignment: .topLeading) {
            switch demo.manualCaptureRoute {
            case .landing:
                Color.clear
                    .frame(height: 0)
            case .defect:
                defectForm
                    .transition(.opacity)
            case .meterReading:
                meterForm
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var defectTitleKey: LocalizedStringKey {
        if defectModel.isReadOnly {
            return "manual.defect.form.readOnly.title"
        } else if defectModel.isExistingDraft {
            return "manual.defect.form.edit.title"
        } else {
            return "manual.defect.form.title"
        }
    }

    private var defectForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Text(defectTitleKey)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(FacilityTheme.ink)
                Spacer()
                if defectModel.isReadOnly {
                    FacilityTemplateBadge(localized: .init("offline.status.pending"), style: .open)
                } else if defectModel.isExistingDraft {
                    FacilityTemplateBadge(localized: .init("offline.status.draft"), style: .temporarilySaved)
                }
            }

            switch defectModel.state {
            case .idle:
                ProgressView("manual.objects.loading")
                    .frame(maxWidth: .infinity, minHeight: 160)
            case .loading where defectModel.objects.isEmpty:
                ProgressView("manual.objects.loading")
                    .frame(maxWidth: .infinity, minHeight: 160)
            case .empty:
                unavailableState("manual.objects.empty.title", "manual.objects.empty.message") {
                    Task { await defectModel.load(itemID: defectModel.editingID) }
                }
            case .failed:
                unavailableState("manual.objects.failure.title", "manual.objects.failure.message") {
                    Task { await defectModel.load(itemID: defectModel.editingID) }
                }
            case .loaded, .loading:
                defectFields
            }
        }
        .facilityCard()
    }

    private var defectFields: some View {
        VStack(alignment: .leading, spacing: 18) {
            fieldLabel("manual.defect.object") {
                Button {
                    guard !defectModel.isReadOnly else { return }
                    isObjectPickerPresented = true
                } label: {
                    HStack(spacing: 12) {
                        if let selected = defectModel.selectedObject {
                            Text(selected.label)
                                .foregroundStyle(FacilityTheme.ink)
                                .lineLimit(1)
                        } else {
                            Text("manual.select.placeholder")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if !defectModel.isReadOnly {
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(defectModel.objects.isEmpty ? .secondary : FacilityTheme.blue)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 12)
                    .background(FacilityTheme.canvas, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(defectModel.isReadOnly || defectModel.objects.isEmpty)
                .popover(
                    isPresented: $isObjectPickerPresented,
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .top
                ) {
                    defectObjectPicker
                        .presentationCompactAdaptation(.popover)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 22) { defectDINField; defectPriorityField }
                VStack(alignment: .leading, spacing: 18) { defectDINField; defectPriorityField }
            }

            fieldLabel("manual.defect.shortText") {
                if defectModel.isReadOnly {
                    Text(defectModel.shortText.isEmpty ? "—" : defectModel.shortText)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(12)
                        .background(FacilityTheme.canvas, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(FacilityTheme.ink)
                } else {
                    TextField("manual.defect.shortText.placeholder", text: $defectModel.shortText)
                        .manualTextField()
                }
            }

            fieldLabel("manual.defect.description") {
                if defectModel.isReadOnly {
                    Text(defectModel.longText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : defectModel.longText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(FacilityTheme.canvas, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(defectModel.longText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : FacilityTheme.ink)
                } else {
                    TextEditor(text: $defectModel.longText)
                        .frame(minHeight: 110)
                        .padding(8)
                        .scrollContentBackground(.hidden)
                        .background(FacilityTheme.canvas, in: RoundedRectangle(cornerRadius: 12))
                }
            }

            photoSection

            if defectModel.saveFailed { formError("offline.save.error.message") }
            if defectModel.photoFailed { formError("manual.photo.error") }

            Divider()
            if defectModel.isReadOnly {
                HStack {
                    Spacer()
                    Button {
                        Task {
                            await defectModel.cancel()
                            withAnimation(.snappy(duration: 0.3, extraBounce: 0)) {
                                demo.closeManualDefect()
                            }
                        }
                    } label: {
                        Text("app.button.close")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 28)
                            .frame(minHeight: 44)
                            .background(FacilityTheme.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(ScalePressButtonStyle())
                }
            } else {
                formActions(
                    canSave: defectModel.canSave,
                    isSaving: defectModel.isSaving,
                    primaryKey: "manual.defect.create",
                    cancel: {
                        Task {
                            await defectModel.cancel()
                            withAnimation(.snappy(duration: 0.3, extraBounce: 0)) {
                                demo.closeManualDefect()
                            }
                        }
                    },
                    saveDraft: { saveDefect(.draft) },
                    submit: { saveDefect(.pendingSynchronization) }
                )
            }
        }
    }

    private var defectDINField: some View {
        fieldLabel("manual.defect.din") {
            Text(defectModel.selectedObject?.dinGroup.map { "KG \($0)" } ?? "—")
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 12)
                .background(FacilityTheme.canvas, in: RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity)
    }

    private var defectPriorityField: some View {
        fieldLabel("manual.defect.priority") {
            Picker("manual.defect.priority", selection: $defectModel.priority) {
                ForEach(DefectPriority.allCases) { value in
                    Text(LocalizedStringKey(value.titleKey)).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .disabled(defectModel.isReadOnly)
        }
        .frame(maxWidth: .infinity)
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("manual.defect.photos")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            PhotoWorkspaceButton(count: photoCount(for: defectPhotoScope)) {
                photoWorkspaceScope = defectPhotoScope
            }
        }
    }

    private var meterForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Text("manual.meter.form.title")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(FacilityTheme.ink)
                Spacer()
                if meterModel.isReadOnly {
                    FacilityTemplateBadge(localized: .init("offline.status.pending"), style: .open)
                }
            }

            switch meterModel.state {
            case .idle:
                ProgressView("manual.meter.loading")
                    .frame(maxWidth: .infinity, minHeight: 140)
            case .loading where meterModel.references.isEmpty:
                ProgressView("manual.meter.loading")
                    .frame(maxWidth: .infinity, minHeight: 140)
            case .unavailable:
                unavailableState("manual.meter.unavailable.title", "manual.meter.unavailable.message", retry: nil)
            case .empty:
                unavailableState("manual.meter.empty.title", "manual.meter.empty.message", retry: nil)
            case .failed:
                unavailableState("manual.meter.failure.title", "manual.meter.failure.message") {
                    Task { await meterModel.load(itemID: meterModel.editingID) }
                }
            case .loaded, .loading:
                meterFields
            }
        }
        .facilityCard(padding: 24)
    }

    private var meterFields: some View {
        VStack(alignment: .leading, spacing: 18) {
            Group {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        meterKindField
                        meterPointField
                    }
                    VStack(alignment: .leading, spacing: 18) {
                        meterKindField
                        meterPointField
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    meterValueField
                    meterUnitField
                }

                meterNoteField

                VStack(alignment: .leading, spacing: 10) {
                    Text("photos.workspace.title")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    PhotoWorkspaceButton(count: photoCount(for: meterPhotoScope)) {
                        photoWorkspaceScope = meterPhotoScope
                    }
                }

                if meterModel.saveFailed { formError("offline.save.error.message") }
            }
            .disabled(meterModel.isReadOnly)

            Divider()
                .padding(.top, 4)

            HStack(spacing: 12) {
                Spacer()

                meterFormActionButton(
                    meterModel.isReadOnly ? "common.back" : "common.cancel",
                    action: { demo.manualCaptureRoute = .landing }
                )

                if !meterModel.isReadOnly {
                    Button {
                        saveMeter(.pendingSynchronization)
                    } label: {
                        HStack(spacing: 8) {
                            if meterModel.isSaving {
                                ProgressView().tint(.white)
                            } else {
                                Text("manual.meter.book")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(.horizontal, 28)
                        .frame(minHeight: 44)
                        .background(
                            (meterModel.canSave && !meterModel.isSaving) ? FacilityTheme.accent : FacilityTheme.accent.opacity(0.35),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                    }
                    .buttonStyle(ScalePressButtonStyle())
                    .disabled(!meterModel.canSave || meterModel.isSaving)
                    .animation(.easeInOut(duration: 0.2), value: meterModel.canSave)
                }
            }
        }
    }

    private func meterFormActionButton(_ key: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.3, extraBounce: 0)) {
                action()
            }
        } label: {
            Text(key)
                .font(.body.weight(.medium))
                .foregroundStyle(FacilityTheme.ink)
                .padding(.horizontal, 28)
                .frame(minHeight: 44)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(uiColor: .systemGray4), lineWidth: 1)
                }
        }
        .buttonStyle(ScalePressButtonStyle())
    }

    private var defectPhotoScope: LocalPhotoScope {
        LocalPhotoScope(
            workflow: .defect,
            ownerID: defectModel.editingID?.uuidString ?? "new-defect",
            displayTitle: String(localized: "photos.workspace.title"),
            displaySubtitle: defectModel.shortText.isEmpty
                ? String(localized: "manual.defect.form.title")
                : defectModel.shortText
        )
    }

    private var meterPhotoScope: LocalPhotoScope {
        LocalPhotoScope(
            workflow: .meterReading,
            ownerID: meterModel.editingID?.uuidString ?? "new-meter-reading",
            displayTitle: String(localized: "photos.workspace.title"),
            displaySubtitle: meterModel.selectedReference.map { "\($0.id) · \($0.technicalPlaceName)" }
                ?? String(localized: "manual.meter.form.title")
        )
    }

    private func photoCount(for scope: LocalPhotoScope) -> Int {
        demo.offlineWorkStore.photoCollection(for: scope)?.payload.photoCollection?.attachments.count
            ?? (scope.workflow == .defect ? defectModel.attachmentIDs.count : 0)
    }

    private var meterKindField: some View {
        fieldLabel("manual.meter.kind") {
            HStack(spacing: 4) {
                ForEach(MeterKind.allCases) { kind in
                    let isSelected = meterModel.kind == kind

                    Button {
                        Task {
                            await meterModel.selectKind(kind)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            switch kind {
                            case .electricity:
                                Image(systemName: "bolt.fill")
                                    .foregroundStyle(Color.yellow)
                            case .gas:
                                Image(systemName: "flame.fill")
                                    .foregroundStyle(Color.orange)
                            case .water:
                                Image(systemName: "drop.fill")
                                    .foregroundStyle(Color.blue)
                            }

                            Text(LocalizedStringKey(kind.titleKey))
                                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? FacilityTheme.ink : .secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white)
                                    .shadow(color: Color.black.opacity(0.12), radius: 3, y: 1)
                                    .matchedGeometryEffect(id: "meterKindSelectionIndicator", in: meterSegmentAnimation)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(SegmentPressButtonStyle())
                }
            }
            .padding(3)
            .background(Color(uiColor: .systemGray6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .frame(maxWidth: .infinity, minHeight: 44)
            .animation(.spring(response: 0.32, dampingFraction: 0.76), value: meterModel.kind)
        }
        .frame(maxWidth: .infinity)
    }

    private var meterPointField: some View {
        fieldLabel("manual.meter.point") {
            Button {
                isMeterPointPickerPresented = true
            } label: {
                HStack(spacing: 10) {
                    if let selected = meterModel.selectedReference {
                        Text("\(selected.id) · \(selected.technicalPlaceName)")
                            .foregroundStyle(FacilityTheme.ink)
                            .lineLimit(1)
                            .id(selected.id)
                            .transition(.opacity)
                    } else {
                        Text("manual.select.placeholder")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .transition(.opacity)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .meterFieldChrome()
            }
            .buttonStyle(FormFieldPressButtonStyle())
            .disabled(meterModel.references.isEmpty)
            .animation(.easeInOut(duration: 0.22), value: meterModel.selectedReferenceID)
            .popover(
                isPresented: $isMeterPointPickerPresented,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .top
            ) {
                meterPointPicker
                    .presentationCompactAdaptation(.popover)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var meterValueField: some View {
        fieldLabel("manual.meter.value") {
            MeterReadingNumberTextField(
                text: $meterModel.valueText,
                placeholder: String(localized: "manual.meter.value.placeholder"),
                isFocused: $isMeterValueFocused
            )
            .frame(height: 24)
            .meterFieldChrome(isFocused: isMeterValueFocused)
        }
        .frame(maxWidth: .infinity)
    }

    private var meterUnitField: some View {
        fieldLabel("manual.meter.unit") {
            Text(meterModel.selectedReference?.unit ?? "—")
                .foregroundStyle(meterModel.selectedReference == nil ? .secondary : FacilityTheme.ink)
                .lineLimit(1)
                .id(meterModel.selectedReference?.unit ?? "empty")
                .transition(.opacity)
                .meterFieldChrome(isFocused: false)
                .animation(.easeInOut(duration: 0.22), value: meterModel.selectedReference?.unit)
        }
        .frame(width: 104)
    }

    private var meterNoteField: some View {
        fieldLabel("manual.meter.note") {
            TextField("manual.meter.note.placeholder", text: $meterModel.note)
                .textFieldStyle(.plain)
                .foregroundStyle(FacilityTheme.ink)
                .focused($focusedMeterField, equals: .note)
                .meterFieldChrome(isFocused: focusedMeterField == .note)
        }
        .frame(maxWidth: .infinity)
    }

    private func saveDefect(_ status: OfflineWorkStatus) {
        Task {
            if await defectModel.save(status: status) { demo.open(.drafts) }
        }
    }

    private func saveMeter(_ status: OfflineWorkStatus) {
        Task {
            if await meterModel.save(status: status) { demo.open(.drafts) }
        }
    }

    private func fieldLabel<Content: View>(_ key: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(key)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func meterInfo(_ key: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(key).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.subheadline).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formError(_ key: LocalizedStringKey) -> some View {
        Label(key, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(FacilityTheme.red)
    }

    private func unavailableState(
        _ title: LocalizedStringKey,
        _ message: LocalizedStringKey,
        retry: (() -> Void)?
    ) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "tray")
        } description: {
            Text(message)
        } actions: {
            if let retry { Button("common.retry", action: retry) }
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    private func formActions(
        canSave: Bool,
        isSaving: Bool,
        primaryKey: LocalizedStringKey,
        cancel: @escaping () -> Void,
        saveDraft: @escaping () -> Void,
        submit: @escaping () -> Void
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Spacer()
                Button("common.cancel", action: cancel).buttonStyle(.bordered)
                Button("manual.saveDraft", action: saveDraft).buttonStyle(.bordered).disabled(!canSave)
                primaryAction(primaryKey, isSaving: isSaving, canSave: canSave, submit: submit)
            }

            VStack(spacing: 10) {
                primaryAction(primaryKey, isSaving: isSaving, canSave: canSave, submit: submit)
                    .frame(maxWidth: .infinity)
                Button("manual.saveDraft", action: saveDraft)
                    .buttonStyle(.bordered)
                    .disabled(!canSave)
                    .frame(maxWidth: .infinity)
                Button("common.cancel", action: cancel)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func primaryAction(
        _ title: LocalizedStringKey,
        isSaving: Bool,
        canSave: Bool,
        submit: @escaping () -> Void
    ) -> some View {
        Button(action: submit) {
            if isSaving { ProgressView().tint(.white) } else { Text(title) }
        }
        .buttonStyle(.borderedProminent)
        .tint(FacilityTheme.accent)
        .disabled(!canSave)
    }

    private var filteredDefectObjects: [DefectObjectOption] {
        let query = objectSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return defectModel.objects }
        return defectModel.objects.filter { object in
            object.reference.objectID.localizedCaseInsensitiveContains(query)
                || object.name.localizedCaseInsensitiveContains(query)
                || (object.dinGroup?.localizedCaseInsensitiveContains(query) == true)
        }
    }

    private var defectObjectPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "cube.box")
                    .foregroundStyle(FacilityTheme.accent)
                Text("manual.defect.object")
                    .font(.headline)
                    .foregroundStyle(FacilityTheme.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("places.search", text: $objectSearchText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                if !objectSearchText.isEmpty {
                    Button {
                        objectSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("places.search.clear"))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(FacilityTheme.canvas, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 18)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                if filteredDefectObjects.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("manual.objects.empty.title")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    LazyVStack(spacing: 0) {
                        if defectModel.selectedObjectID != nil && objectSearchText.isEmpty {
                            Button {
                                defectModel.selectedObjectID = nil
                                isObjectPickerPresented = false
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "xmark.circle")
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24)
                                    Text("manual.select.placeholder")
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 18)
                                .frame(minHeight: 48)
                            }
                            .buttonStyle(.plain)

                            Divider().padding(.leading, 18)
                        }

                        ForEach(filteredDefectObjects) { object in
                            let isSelected = object.id == defectModel.selectedObjectID

                            Button {
                                defectModel.selectedObjectID = object.id
                                isObjectPickerPresented = false
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: object.reference.kind == .equipment ? "gearshape" : "building.2")
                                        .font(.body)
                                        .foregroundStyle(object.reference.kind == .equipment ? FacilityTheme.blue : FacilityTheme.accent)
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(object.name.isEmpty ? object.reference.objectID : object.name)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(FacilityTheme.ink)
                                            .lineLimit(1)

                                        HStack(spacing: 8) {
                                            Text(object.reference.objectID)
                                                .font(.caption.monospaced())
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)

                                            if let din = object.dinGroup, !din.isEmpty {
                                                Text("KG \(din)")
                                                    .font(.caption2.weight(.semibold))
                                                    .foregroundStyle(FacilityTheme.blue)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(FacilityTheme.blue.opacity(0.10), in: Capsule())
                                            }
                                        }
                                    }

                                    Spacer(minLength: 12)

                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(isSelected ? FacilityTheme.accent : .secondary)
                                }
                                .padding(.horizontal, 18)
                                .frame(minHeight: 56)
                                .background(isSelected ? FacilityTheme.accentSoft : FacilityTheme.surface)
                            }
                            .buttonStyle(.plain)

                            if object.id != filteredDefectObjects.last?.id {
                                Divider().padding(.leading, 18)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 340)
        }
        .frame(width: 440)
        .background(FacilityTheme.surface)
    }

    private var filteredMeterReferences: [MeterReference] {
        let query = meterPointSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return meterModel.references }
        return meterModel.references.filter { meter in
            meter.id.localizedCaseInsensitiveContains(query)
                || meter.technicalPlaceName.localizedCaseInsensitiveContains(query)
                || meter.technicalPlaceID.localizedCaseInsensitiveContains(query)
        }
    }

    private var meterPointPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "gauge.with.needle")
                    .foregroundStyle(FacilityTheme.accent)
                Text("manual.meter.point")
                    .font(.headline)
                    .foregroundStyle(FacilityTheme.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)

            if meterModel.references.count > 4 {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("places.search", text: $meterPointSearchText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                    if !meterPointSearchText.isEmpty {
                        Button {
                            meterPointSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("places.search.clear"))
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(FacilityTheme.canvas, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
            }

            Divider()

            ScrollView {
                if filteredMeterReferences.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("manual.meter.empty.title")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredMeterReferences) { meter in
                            let isSelected = meter.id == meterModel.selectedReferenceID

                            Button {
                                meterModel.selectedReferenceID = meter.id
                                isMeterPointPickerPresented = false
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "gauge.with.needle")
                                        .font(.body)
                                        .foregroundStyle(FacilityTheme.blue)
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(meter.technicalPlaceName.isEmpty ? meter.id : meter.technicalPlaceName)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(FacilityTheme.ink)
                                            .lineLimit(1)

                                        HStack(spacing: 8) {
                                            Text(meter.id)
                                                .font(.caption.monospaced())
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)

                                            if !meter.unit.isEmpty {
                                                Text(meter.unit)
                                                    .font(.caption2.weight(.semibold))
                                                    .foregroundStyle(FacilityTheme.accent)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(FacilityTheme.accentSoft, in: Capsule())
                                            }
                                        }
                                    }

                                    Spacer(minLength: 12)

                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(isSelected ? FacilityTheme.accent : .secondary)
                                }
                                .padding(.horizontal, 18)
                                .frame(minHeight: 56)
                                .background(isSelected ? FacilityTheme.accentSoft : FacilityTheme.surface)
                            }
                            .buttonStyle(.plain)

                            if meter.id != filteredMeterReferences.last?.id {
                                Divider().padding(.leading, 18)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 320)
        }
        .frame(width: 440)
        .background(FacilityTheme.surface)
    }

    private var isDefectSelected: Bool {
        if case .defect = demo.manualCaptureRoute { return true }
        return false
    }

    private var isMeterSelected: Bool {
        if case .meterReading = demo.manualCaptureRoute { return true }
        return false
    }
}

private struct ManualCaptureActionCard: View {
    let titleKey: LocalizedStringKey
    let subtitleKey: LocalizedStringKey
    let symbol: String
    let tint: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 13) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 54, height: 54)
                    .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 15))
                Text(titleKey).font(.title3.weight(.bold)).foregroundStyle(FacilityTheme.ink)
                Text(subtitleKey)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 174, alignment: .topLeading)
            .padding(20)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .stroke(selected ? tint : Color.black.opacity(0.06), lineWidth: selected ? 2 : 1)
            }
            .shadow(color: selected ? tint.opacity(0.12) : Color.black.opacity(0.06), radius: selected ? 12 : 10, y: 5)
            .animation(.easeInOut(duration: 0.22), value: selected)
        }
        .buttonStyle(ScalePressButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct MeterReadingNumberTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    @Binding var isFocused: Bool
    var onCommit: (() -> Void)? = nil

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.delegate = context.coordinator
        textField.keyboardType = .numberPad
        textField.font = UIFont.preferredFont(forTextStyle: .body)
        textField.textColor = UIColor(FacilityTheme.ink)
        textField.tintColor = UIColor(FacilityTheme.blue)
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.spellCheckingType = .no
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)

        let placeholderColor = UIColor.secondaryLabel
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: placeholderColor]
        )

        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }

        let placeholderColor = UIColor.secondaryLabel
        uiView.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: placeholderColor]
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: MeterReadingNumberTextField

        init(_ parent: MeterReadingNumberTextField) {
            self.parent = parent
        }

        @objc func textDidChange(_ textField: UITextField) {
            let current = textField.text ?? ""
            let sanitized = MeterReadingViewModel.sanitizeInput(current)
            if current != sanitized {
                textField.text = sanitized
            }
            if parent.text != sanitized {
                parent.text = sanitized
            }
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            if string.isEmpty {
                return true
            }

            let currentText = textField.text ?? ""
            guard let textRange = Range(range, in: currentText) else { return false }
            let projectedText = currentText.replacingCharacters(in: textRange, with: string)

            let sanitized = MeterReadingViewModel.sanitizeInput(projectedText)

            if projectedText != sanitized {
                if currentText != sanitized {
                    textField.text = sanitized
                    parent.text = sanitized
                }
                return false
            }

            return true
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            DispatchQueue.main.async {
                if !self.parent.isFocused {
                    self.parent.isFocused = true
                }
            }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            DispatchQueue.main.async {
                if self.parent.isFocused {
                    self.parent.isFocused = false
                }
            }
            parent.onCommit?()
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}

private enum MeterFormField: Hashable {
    case value
    case note
}

private struct ScalePressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct SegmentPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct FormFieldPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

private extension View {
    func manualTextField() -> some View {
        textFieldStyle(.plain)
            .padding(12)
            .background(FacilityTheme.canvas, in: RoundedRectangle(cornerRadius: 12))
    }

    func meterFieldChrome(isFocused: Bool = false) -> some View {
        padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isFocused ? FacilityTheme.blue : Color(uiColor: .systemGray4),
                        lineWidth: isFocused ? 1.5 : 1
                    )
            }
            .animation(.easeInOut(duration: 0.18), value: isFocused)
    }
}
