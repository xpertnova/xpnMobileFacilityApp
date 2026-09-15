import SwiftUI

struct TFM2ElevatorInspectionView: View {
    let detail: SAPNotificationDetail
    let backDestination: AppDestination
    let dismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var model: ElevatorInspectionViewModel
    @State private var editingCommentID: String?
    @State private var photoWorkspaceItemID: String?

    init(
        detail: SAPNotificationDetail,
        offlineWorkStore: OfflineWorkStore,
        photoAttachmentStore: any PhotoAttachmentStore,
        sapDataStore: SAPDataStore? = nil,
        elevatorAssetDataProvider: any ElevatorAssetDataProviding = UnavailableElevatorAssetDataProvider(),
        backDestination: AppDestination,
        dismiss: @escaping () -> Void
    ) {
        self.detail = detail
        self.backDestination = backDestination
        self.dismiss = dismiss
        _model = State(initialValue: ElevatorInspectionViewModel(
            detail: detail,
            offlineWorkStore: offlineWorkStore,
            photoStore: photoAttachmentStore,
            sapDataStore: sapDataStore,
            elevatorAssetDataProvider: elevatorAssetDataProvider
        ))
    }

    var body: some View {
        ZStack {
            if let item = photoWorkspaceItem {
                photoWorkspace(for: item)
                    .transition(PhotoWorkspaceMotion.destination)
                    .zIndex(1)
            } else {
                VStack(spacing: 0) {
                    header

                    ScrollView {
                        VStack(spacing: 18) {
                            metadataCard
                            elevatorAssetDataCard
                            inspectionCard
                        }
                        .padding(28)
                        .frame(maxWidth: 1280, alignment: .leading)
                    }
                }
                .background(FacilityTheme.canvas.ignoresSafeArea())
                .safeAreaInset(edge: .bottom) { actionBar }
                .transition(PhotoWorkspaceMotion.source)
            }
        }
        .animation(
            accessibilityReduceMotion ? nil : PhotoWorkspaceMotion.navigation,
            value: photoWorkspaceItemID
        )
        .overlay {
            if let editingCommentID {
                ElevatorCommentEditorOverlay(
                    comment: commentBinding(for: editingCommentID),
                    dismiss: { self.editingCommentID = nil }
                )
            }
        }
        .task(id: detail.summary.id) {
            await model.load()
        }
        .alert(item: $model.feedback) { feedback in
            Alert(
                title: Text("notifications.detail.action.title"),
                message: Text(feedback.messageKey),
                dismissButton: .default(Text("notifications.detail.commentEditor.done")) {
                    if case .closedLocally = feedback {
                        if !model.isI2DefectSelectionPresented {
                            dismiss()
                        }
                    } else if case .i2DefectsCreated = feedback {
                        dismiss()
                    }
                }
            )
        }
        .confirmationDialog(
            "elevator.closeDialog.title",
            isPresented: $model.isStatusDecisionPresented,
            titleVisibility: .visible
        ) {
            Button("elevator.closeDialog.leaveOpen") {
                Task { await model.confirmStatusDecision(.leaveOpen) }
            }
            Button("elevator.closeDialog.close") {
                Task { await model.confirmStatusDecision(.close) }
            }
            Button("common.cancel", role: .cancel) {
                model.cancelStatusDecision()
            }
        } message: {
            Text("elevator.closeDialog.message")
        }
        .sheet(isPresented: $model.isI2DefectSelectionPresented, onDismiss: {
            dismiss()
        }) {
            ElevatorI2DefectSelectionSheet(
                items: model.deficientItems,
                selectedIDs: $model.selectedI2DefectIDs,
                confirm: {
                    Task {
                        await model.createI2Defects(for: model.selectedI2DefectIDs)
                    }
                },
                cancel: {
                    model.isI2DefectSelectionPresented = false
                    dismiss()
                }
            )
        }
    }

    private var photoWorkspaceItem: ElevatorInspectionItem? {
        model.items.first { $0.id == photoWorkspaceItemID }
    }

    private func photoWorkspace(for item: ElevatorInspectionItem) -> some View {
        let attachments = model.attachments(for: item.id)
        return PhotoWorkspace(
            title: String(localized: "photos.workspace.title"),
            subtitle: item.title,
            entries: attachments.map {
                PhotoWorkspaceEntry(
                    id: $0.id,
                    localAttachmentID: $0.localAttachmentID,
                    capturedAt: $0.capturedAt
                )
            },
            photoData: model.photoData,
            isLoading: model.isLoading,
            isSaving: model.isSaving,
            isReadOnly: isReadOnly,
            maxAttachments: ElevatorInspectionViewModel.maximumPhotoCount,
            close: { photoWorkspaceItemID = nil },
            addPhoto: { data in Task { await model.addPhoto(jpegData: data, to: item) } },
            removePhoto: { id in
                guard let attachment = attachments.first(where: { $0.id == id }) else { return }
                Task { await model.removePhoto(attachment) }
            },
            reportImportFailure: { model.feedback = .photoFailed },
            reportCameraUnavailable: { model.feedback = .cameraUnavailable },
            reportCameraPermissionDenied: { model.feedback = .cameraPermissionDenied }
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                Button {
                    Task {
                        await model.cancel()
                        dismiss()
                    }
                } label: {
                    Label(LocalizedStringKey(backDestination.titleKey), systemImage: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(FacilityTheme.blue)
                .frame(minHeight: 44, alignment: .leading)

                Text(detail.summary.title.isEmpty ? detail.summary.id : detail.summary.title)
                    .font(.system(size: 29, weight: .bold))
                    .foregroundStyle(FacilityTheme.ink)

                Text(notificationSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 8) {
                    Text("TFM2")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(white: 0.92), in: Capsule())

                    if model.isClosedLocally {
                        Text("notifications.detail.status.closed")
                            .font(.caption.bold())
                            .foregroundStyle(FacilityTheme.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(FacilityTheme.accent.opacity(0.12), in: Capsule())
                    } else if !detail.summary.displayStatus.isEmpty {
                        Text(detail.summary.displayStatus)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(FacilityTheme.blue)
                            .multilineTextAlignment(.trailing)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(FacilityTheme.blue.opacity(0.10), in: Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(FacilityTheme.surface)
    }

    private var notificationSubtitle: String {
        let identifier = "\(String(localized: "notifications.detail.number")) \(detail.summary.id)"
        return [identifier, detail.summary.displayDateRange]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var metadataCard: some View {
        HStack(alignment: .top, spacing: 30) {
            VStack(alignment: .leading, spacing: 15) {
                metadataRow(
                    "notifications.detail.technicalPlace",
                    detail.summary.functionalLocationID,
                    monospaced: true
                )
                if !detail.summary.functionalLocationName.isEmpty {
                    metadataRow("notifications.detail.description", detail.summary.functionalLocationName)
                }

                if !detail.structure.isEmpty {
                    metadataRow("notifications.detail.structure", detail.structure)
                }
                if !detail.summary.equipmentID.isEmpty {
                    metadataRow("notifications.detail.equipment", detail.summary.equipmentID, monospaced: true)
                }
                if !detail.summary.systemStatus.isEmpty {
                    metadataRow("notifications.detail.systemStatus", detail.summary.systemStatus)
                }
                if !detail.summary.userStatus.isEmpty {
                    metadataRow("notifications.detail.userStatus", detail.summary.userStatus)
                }
                if !detail.summary.displayDateRange.isEmpty {
                    metadataRow("notifications.detail.dateRange", detail.summary.displayDateRange)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                Text("notifications.detail.performedOn")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                DatePicker(
                    "notifications.detail.performedOn",
                    selection: $model.performedOn,
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .disabled(isReadOnly)
                .padding(.horizontal, 8)
                .frame(minHeight: 44)
                .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.gray.opacity(0.22))
                }
            }
            .frame(width: 190, alignment: .leading)
        }
        .facilityCard(padding: 22)
    }

    private var elevatorAssetDataCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "building.2.crop.circle")
                    .foregroundStyle(FacilityTheme.blue)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("elevator.assetData.title")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(FacilityTheme.ink)
                    Text("elevator.assetData.subtitle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                if model.elevatorAssetDataState == .ready {
                    Text("elevator.assetData.readOnly")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.05), in: Capsule())
                }
            }

            switch model.elevatorAssetDataState {
            case .loading:
                HStack(spacing: 12) {
                    ProgressView()
                    Text("elevator.assetData.loading")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)

            case .ready:
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 290, maximum: 520), spacing: 16)],
                    alignment: .leading,
                    spacing: 16
                ) {
                    ForEach(model.elevatorAssetCharacteristics) { characteristic in
                        elevatorAssetValueCell(for: characteristic)
                    }
                }

            case .unavailable:
                ContentUnavailableView(
                    "elevator.assetData.unavailable.title",
                    systemImage: "archivebox",
                    description: Text("elevator.assetData.unavailable.message")
                )
                .frame(maxWidth: .infinity, minHeight: 124)

                Button {
                    Task { await model.reloadElevatorAssetData() }
                } label: {
                    Label("elevator.assetData.retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .tint(FacilityTheme.blue)
                .frame(minHeight: 44)
            }
        }
        .facilityCard(padding: 22)
    }

    private func elevatorAssetValueCell(for characteristic: ElevatorAssetCharacteristic) -> some View {
        let value = model.elevatorAssetDisplayValue(for: characteristic)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Text(characteristic.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FacilityTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if characteristic.isRequired {
                    Image(systemName: "asterisk")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(FacilityTheme.accent)
                        .accessibilityLabel(Text("elevator.assetData.required"))
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value)
                    .font(characteristic.isNumeric ? .body.monospacedDigit() : .body)
                    .foregroundStyle(value == "—" ? Color.secondary : FacilityTheme.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if !characteristic.unit.isEmpty {
                    Text(characteristic.unit)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 12)
            .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.black.opacity(0.10))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func metadataRow(
        _ titleKey: String,
        _ value: String,
        monospaced: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 24) {
            Text(LocalizedStringKey(titleKey))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 180, alignment: .leading)

            Text(value)
                .font(monospaced ? .subheadline.monospaced() : .body)
                .foregroundStyle(FacilityTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private var inspectionCard: some View {
        VStack(spacing: 0) {
            if model.items.isEmpty {
                VStack(spacing: 16) {
                    ContentUnavailableView(
                        "elevator.unavailable.title",
                        systemImage: "exclamationmark.triangle",
                        description: Text("elevator.unavailable.message")
                    )
                    Button {
                        Task { await model.load() }
                    } label: {
                        Label("elevator.unavailable.retry", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .tint(FacilityTheme.blue)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
                .padding(24)
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        inspectionHeaderRow
                        Divider()

                        ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                            ElevatorInspectionItemRow(
                                item: item,
                                number: index + 1,
                                result: model.results[item.id],
                                action: model.actions[item.id],
                                material: model.materials[item.id] ?? false,
                                isResultMissing: model.validationErrors.contains(item.id),
                                hasMaterialColumn: model.hasMaterialColumn,
                                isReadOnly: isReadOnly,
                                selectResult: { val in
                                    guard !isEditingDisabled else { return }
                                    model.results[item.id] = val
                                    model.validationErrors.remove(item.id)
                                },
                                selectAction: { val in
                                    guard !isEditingDisabled else { return }
                                    model.actions[item.id] = val
                                },
                                toggleMaterial: {
                                    guard !isEditingDisabled else { return }
                                    let current = model.materials[item.id] ?? false
                                    model.materials[item.id] = !current
                                },
                                attachments: model.attachments(for: item.id),
                                openPhotos: { photoWorkspaceItemID = item.id },
                                comment: model.comments[item.id, default: ""],
                                editComment: {
                                    guard !isEditingDisabled else { return }
                                    editingCommentID = item.id
                                }
                            )
                            if index < model.items.count - 1 {
                                Divider().padding(.leading, 22)
                            }
                        }
                    }
                    .frame(minWidth: 840)
                }
            }
        }
        .background(FacilityTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.06))
        }
    }

    private var inspectionHeaderRow: some View {
        HStack(spacing: 12) {
            Text("notifications.detail.numberColumn")
                .frame(width: 42, alignment: .leading)
            Color.clear
                .frame(width: 28, height: 1)
            Text("notifications.detail.inspectionPoint")
                .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
            Text("elevator.column.result")
                .frame(width: 160, alignment: .leading)
            Text("elevator.column.action")
                .frame(width: 160, alignment: .leading)

            if model.hasMaterialColumn {
                Text("elevator.column.material")
                    .frame(width: 65, alignment: .center)
            }

            Text("notifications.detail.photo")
                .frame(width: 52, alignment: .center)
            Text("notifications.detail.comment")
                .frame(width: 58, alignment: .center)
        }
        .font(.subheadline.weight(.bold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private func commentBinding(for itemID: String) -> Binding<String> {
        Binding(
            get: { model.comments[itemID, default: ""] },
            set: { newValue in
                guard !isEditingDisabled else { return }
                if newValue.isEmpty {
                    model.comments.removeValue(forKey: itemID)
                } else {
                    model.comments[itemID] = newValue
                }
            }
        )
    }

    private var actionBar: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 12)

            Button("notifications.detail.allGood") {
                model.applyAllGood()
            }
            .buttonStyle(.plain)
            .foregroundStyle(FacilityTheme.blue)
            .disabled(isEditingDisabled || !model.isAllGoodAvailable || model.isSaving)

            Button("notifications.detail.saveTemporary") {
                Task { await model.save(closed: false) }
            }
            .buttonStyle(.bordered)
            .tint(FacilityTheme.ink)
            .disabled(isEditingDisabled || model.isSaving)

            Button("notifications.detail.closeNotification") {
                model.handleCloseTapped()
            }
            .buttonStyle(.borderedProminent)
            .tint(FacilityTheme.accent)
            .disabled(isEditingDisabled || model.isSaving || model.items.isEmpty)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private var isReadOnly: Bool {
        model.isClosedLocally
    }

    private var isEditingDisabled: Bool {
        model.isEditingDisabled
    }
}

private extension ElevatorInspectionFeedback {
    var messageKey: LocalizedStringKey {
        switch self {
        case .savedLocally: "notifications.detail.action.saved"
        case .closedLocally: "notifications.detail.action.closed"
        case .incomplete: "notifications.detail.action.incomplete"
        case .saveFailed: "notifications.detail.action.failed"
        case .photoFailed: "notifications.detail.photo.failed"
        case .photoLimitReached: "notifications.detail.photo.limit"
        case .cameraUnavailable: "notifications.detail.photo.cameraUnavailable"
        case .cameraPermissionDenied: "notifications.detail.photo.cameraPermissionDenied"
        case .i2DefectsCreated: "elevator.i2.created.success"
        }
    }
}

private struct ElevatorCommentEditorOverlay: View {
    @Binding var comment: String
    let dismiss: () -> Void
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.14)
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)

            VStack(alignment: .leading, spacing: 16) {
                Text("notifications.detail.commentEditor.title")
                    .font(.headline)
                    .foregroundStyle(FacilityTheme.ink)

                ZStack(alignment: .topLeading) {
                    if comment.isEmpty {
                        Text("notifications.detail.commentEditor.placeholder")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $comment)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .focused($isEditorFocused)
                        .accessibilityLabel(Text("notifications.detail.commentEditor.placeholder"))
                }
                .frame(height: 190)
                .background(Color(white: 0.89), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack {
                    Spacer()
                    Button("notifications.detail.commentEditor.done", action: dismiss)
                        .buttonStyle(.borderedProminent)
                        .tint(FacilityTheme.accent)
                }
            }
            .padding(22)
            .frame(maxWidth: 460)
            .background(Color(white: 0.95), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.20), radius: 26, y: 12)
            .padding(28)
        }
        .onAppear { isEditorFocused = true }
    }
}

private struct ElevatorInspectionItemRow: View {
    let item: ElevatorInspectionItem
    let number: Int
    let result: String?
    let action: String?
    let material: Bool
    let isResultMissing: Bool
    let hasMaterialColumn: Bool
    let isReadOnly: Bool
    let selectResult: (String) -> Void
    let selectAction: (String) -> Void
    let toggleMaterial: () -> Void
    let attachments: [NotificationPhotoAttachment]
    let openPhotos: () -> Void
    let comment: String
    let editComment: () -> Void

    @State private var isShowingInformation = false
    @State private var expandedPicker: InspectionPickerField?

    private var isDefect: Bool {
        guard let res = result else { return false }
        return ElevatorInspectionLogic.isDefect(resultCode: res, actionCode: action)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(number, format: .number)
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)

            // Warning icon
            ZStack {
                if isResultMissing {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(FacilityTheme.red)
                        .accessibilityLabel(Text("notifications.detail.validation.incompleteItem"))
                } else if isDefect {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(FacilityTheme.red)
                        .accessibilityLabel(Text("elevator.status.defect"))
                } else if result == "1" {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(FacilityTheme.accent)
                        .accessibilityLabel(Text("elevator.status.inOrder"))
                }
            }
            .frame(width: 28, height: 44)

            // Info button & title
            HStack(spacing: 10) {
                if item.information.isEmpty {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.tertiary)
                        .frame(width: 44, height: 44)
                } else {
                    Button {
                        isShowingInformation = true
                    } label: {
                        Image(systemName: "info.circle.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(FacilityTheme.blue)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("notifications.detail.showInformation"))
                    .popover(isPresented: $isShowingInformation) {
                        Text(item.information)
                            .font(.body)
                            .padding(20)
                            .frame(width: 360, alignment: .leading)
                    }
                }

                Text(item.title)
                    .font(.body)
                    .foregroundStyle(FacilityTheme.ink)
                    .frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
            }

            // Result (Befund)
            resultControl
                .frame(width: 160)

            // Action (Maßnahme)
            actionControl
                .frame(width: 160)

            // Material Checkbox
            if hasMaterialColumn {
                materialControl
                    .frame(width: 65, alignment: .center)
            }

            // Photos button
            Button(action: openPhotos) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: attachments.isEmpty ? "camera" : "camera.fill")
                        .foregroundStyle(attachments.isEmpty ? FacilityTheme.ink : FacilityTheme.blue)
                        .frame(width: 44, height: 44)
                        .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.gray.opacity(0.25)))
                    if !attachments.isEmpty {
                        Text(attachments.count, format: .number)
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(FacilityTheme.blue, in: Circle())
                            .offset(x: 5, y: -5)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("notifications.detail.photo"))
            .accessibilityValue(Text(String(format: String(localized: "notifications.detail.photo.count"), attachments.count)))
            .frame(width: 52)

            // Comment button
            Button(action: editComment) {
                Image(systemName: comment.isEmpty ? "pencil" : "note.text")
                    .foregroundStyle(comment.isEmpty ? FacilityTheme.ink : FacilityTheme.blue)
                    .frame(width: 44, height: 44)
                    .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.gray.opacity(0.25)))
            }
            .buttonStyle(.plain)
            .disabled(isReadOnly)
            .accessibilityLabel(Text("notifications.detail.comment"))
            .frame(width: 58)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .frame(minHeight: 68)
        // Keep the active row above its neighbours while its anchored popover is visible
        .zIndex(expandedPicker == nil ? 0 : 1)
    }

    @ViewBuilder
    private var resultControl: some View {
        if item.resultOptions.isEmpty {
            Text("-")
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            InspectionCodePicker(
                picker: .result,
                expandedPicker: $expandedPicker,
                selection: result,
                options: item.resultOptions.map { InspectionCodeOption(code: $0.code, title: $0.text) },
                isEnabled: !isReadOnly,
                accessibilityLabel: Text("elevator.column.result")
            ) { code in
                selectResult(code)
            }
        }
    }

    @ViewBuilder
    private var actionControl: some View {
        if item.hasAction {
            InspectionCodePicker(
                picker: .action,
                expandedPicker: $expandedPicker,
                selection: action,
                options: item.actionOptions.map { InspectionCodeOption(code: $0.code, title: $0.text) },
                isEnabled: !isReadOnly,
                accessibilityLabel: Text("elevator.column.action")
            ) { code in
                selectAction(code)
            }
        } else {
            Text("-")
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    @ViewBuilder
    private var materialControl: some View {
        if item.hasMaterial {
            Button(action: toggleMaterial) {
                Image(systemName: material ? "checkmark.square.fill" : "square")
                    .font(.title2)
                    .foregroundStyle(material ? FacilityTheme.blue : .secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(isReadOnly)
            .accessibilityLabel(Text("elevator.column.material"))
            .accessibilityValue(Text(material ? "common.yes" : "common.no"))
        } else {
            Text("-")
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

private struct ElevatorI2DefectSelectionSheet: View {
    let items: [ElevatorInspectionItem]
    @Binding var selectedIDs: Set<String>
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("elevator.i2.sheet.description")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                List {
                    ForEach(items) { item in
                        Button {
                            if selectedIDs.contains(item.id) {
                                selectedIDs.remove(item.id)
                            } else {
                                selectedIDs.insert(item.id)
                            }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selectedIDs.contains(item.id) ? FacilityTheme.blue : .secondary)
                                    .frame(width: 44, height: 44)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(FacilityTheme.ink)
                                    Text("\(item.steus) - \(item.vornr)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("elevator.i2.sheet.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("elevator.i2.sheet.skip", action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("elevator.i2.sheet.create", action: confirm)
                        .bold()
                }
            }
        }
    }
}
