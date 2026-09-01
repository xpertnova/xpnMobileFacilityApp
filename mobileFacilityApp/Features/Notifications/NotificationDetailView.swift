import SwiftUI

struct NotificationDetailView: View {
    let detail: SAPNotificationDetail
    let offlineWorkStore: OfflineWorkStore
    let dismiss: () -> Void
    @State private var performedOn = Date.now
    @State private var comments: [String: String] = [:]
    @State private var results: [String: NotificationReviewResult] = [:]
    @State private var photoItemIDs: Set<String> = []
    @State private var editingCommentID: String?
    @State private var isSavingDraft = false
    @State private var isClosedLocally = false
    @State private var feedback: DetailActionFeedback?

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 18) {
                    metadataCard
                    inspectionCard
                }
                .padding(28)
                .frame(maxWidth: 1280, alignment: .leading)
            }
        }
        .background(FacilityTheme.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            actionBar
        }
        .overlay {
            if let editingCommentID {
                CommentEditorOverlay(
                    comment: commentBinding(for: editingCommentID),
                    dismiss: { self.editingCommentID = nil }
                )
            }
        }
        .task(id: detail.summary.id) {
            await offlineWorkStore.load()
            guard let draft = offlineWorkStore.notificationReview(notificationID: detail.summary.id) else { return }
            performedOn = draft.performedOn
            results = draft.results
            comments = draft.comments
            photoItemIDs = Set(draft.photoItemIDs)
            isClosedLocally = draft.isClosedLocally
        }
        .alert(item: $feedback) { feedback in
            Alert(
                title: Text(feedback.titleKey),
                message: Text(feedback.messageKey),
                dismissButton: .default(Text("notifications.detail.commentEditor.done")) {
                    if case .closedLocally = feedback {
                        dismiss()
                    }
                }
            )
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                Button(action: dismiss) {
                    Label("notifications.detail.back", systemImage: "chevron.left")
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
                if !detail.summary.displayStatus.isEmpty {
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
                metadataRow("notifications.detail.description", detail.summary.functionalLocationName)

                if !detail.structure.isEmpty {
                    metadataRow("notifications.detail.structure", detail.structure)
                }
                if !detail.equipmentID.isEmpty {
                    metadataRow("notifications.detail.equipment", detail.equipmentID, monospaced: true)
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
                    selection: $performedOn,
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.compact)
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
            HStack(spacing: 12) {
                Text("notifications.detail.numberColumn")
                    .frame(width: 42, alignment: .leading)
                Color.clear
                    .frame(width: 28, height: 1)
                Text("notifications.detail.inspectionPoint")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("notifications.detail.result")
                    .frame(width: 130, alignment: .center)
                Text("notifications.detail.photo")
                    .frame(width: 52, alignment: .center)
                Text("notifications.detail.comment")
                    .frame(width: 58, alignment: .center)
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)

            Divider()

            if detail.inspectionItems.isEmpty {
                ContentUnavailableView(
                    "notifications.detail.noInspectionItems.title",
                    systemImage: "list.bullet",
                    description: Text("notifications.detail.noInspectionItems.message")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ForEach(Array(detail.inspectionItems.enumerated()), id: \.element.id) { index, item in
                    InspectionItemRow(
                        item: item,
                        number: index + 1,
                        result: results[item.id],
                        isResultMissing: results[item.id] == nil,
                        selectResult: { results[item.id] = $0 },
                        hasPhoto: photoItemIDs.contains(item.id),
                        togglePhoto: { togglePhoto(for: item.id) },
                        comment: comments[item.id, default: ""],
                        editComment: { editingCommentID = item.id }
                    )
                    if index < detail.inspectionItems.count - 1 {
                        Divider().padding(.leading, 22)
                    }
                }
            }
        }
        .background(FacilityTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        // A shadow around one long scrolling surface forces expensive
        // off-screen compositing. A subtle border keeps the same card edge
        // without making scroll performance depend on checklist height.
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.06))
        }
    }

    private func commentBinding(for itemID: String) -> Binding<String> {
        Binding(
            get: { comments[itemID, default: ""] },
            set: { newValue in
                if newValue.isEmpty {
                    comments.removeValue(forKey: itemID)
                } else {
                    comments[itemID] = newValue
                }
            }
        )
    }

    private var actionBar: some View {
        HStack(spacing: 14) {
            Label("notifications.detail.localOnly", systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Button("notifications.detail.allGood") {
                for item in detail.inspectionItems {
                    results[item.id] = .no
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(FacilityTheme.blue)
            .disabled(detail.inspectionItems.isEmpty || isSavingDraft)

            Button("notifications.detail.saveTemporary") {
                saveReview(isClosedLocally: false)
            }
            .buttonStyle(.bordered)
            .tint(FacilityTheme.ink)
            .disabled(isSavingDraft)

            Button("notifications.detail.closeNotification") {
                saveReview(isClosedLocally: true)
            }
            .buttonStyle(.borderedProminent)
            .tint(FacilityTheme.accent)
            .disabled(isSavingDraft || isClosedLocally || !canCloseNotification)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private var canCloseNotification: Bool {
        detail.inspectionItems.allSatisfy { results[$0.id] != nil }
    }

    private func togglePhoto(for itemID: String) {
        if photoItemIDs.contains(itemID) {
            photoItemIDs.remove(itemID)
        } else {
            photoItemIDs.insert(itemID)
        }
    }

    private func saveReview(isClosedLocally: Bool) {
        guard !isSavingDraft else { return }
        guard !isClosedLocally || canCloseNotification else {
            feedback = .incomplete
            return
        }

        isSavingDraft = true
        let draft = NotificationReviewDraftPayload(
            notificationID: detail.summary.id,
            performedOn: performedOn,
            results: results,
            comments: comments,
            photoItemIDs: Array(photoItemIDs),
            isClosedLocally: isClosedLocally,
            notificationSnapshot: OfflineNotificationSnapshot(detail: detail)
        )
        Task {
            defer { isSavingDraft = false }
            do {
                _ = try await offlineWorkStore.saveNotificationReview(draft)
                self.isClosedLocally = isClosedLocally
                feedback = isClosedLocally ? .closedLocally : .savedLocally
            } catch {
                feedback = .saveFailed
            }
        }
    }
}

private enum DetailActionFeedback: Identifiable {
    case savedLocally
    case closedLocally
    case incomplete
    case saveFailed

    var id: Self { self }

    var titleKey: LocalizedStringKey { "notifications.detail.action.title" }

    var messageKey: LocalizedStringKey {
        switch self {
        case .savedLocally: "notifications.detail.action.saved"
        case .closedLocally: "notifications.detail.action.closed"
        case .incomplete: "notifications.detail.action.incomplete"
        case .saveFailed: "notifications.detail.action.failed"
        }
    }
}

private struct CommentEditorOverlay: View {
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

private struct InspectionItemRow: View {
    let item: SAPNotificationDetail.InspectionItem
    let number: Int
    let result: NotificationReviewResult?
    let isResultMissing: Bool
    let selectResult: (NotificationReviewResult) -> Void
    let hasPhoto: Bool
    let togglePhoto: () -> Void
    let comment: String
    let editComment: () -> Void
    @State private var isShowingInformation = false

    var body: some View {
        HStack(spacing: 12) {
            Text(number, format: .number)
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)

            Image(systemName: "exclamationmark.triangle")
                .font(.title3.weight(.semibold))
                .foregroundStyle(FacilityTheme.red)
                .frame(width: 28, height: 52)
                .opacity(isResultMissing ? 1 : 0)
                .accessibilityLabel(Text("notifications.detail.validation.incompleteItem"))
                .accessibilityHidden(!isResultMissing)

            HStack(spacing: 10) {
                if item.information.isEmpty {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.tertiary)
                        .frame(width: 28, height: 28)
                } else {
                    Button {
                        isShowingInformation = true
                    } label: {
                        Image(systemName: "info.circle.fill")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(FacilityTheme.blue)
                            .frame(width: 52, height: 52)
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
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            resultControl
                .frame(width: 130)

            Button(action: togglePhoto) {
                Image(systemName: hasPhoto ? "camera.fill" : "camera")
                    .foregroundStyle(hasPhoto ? FacilityTheme.blue : FacilityTheme.ink)
                    .frame(width: 44, height: 44)
                    .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.gray.opacity(0.25)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("notifications.detail.photo"))
            .frame(width: 52)

            Button(action: editComment) {
                Image(systemName: comment.isEmpty ? "pencil" : "note.text")
                    .foregroundStyle(comment.isEmpty ? FacilityTheme.ink : FacilityTheme.blue)
                    .frame(width: 44, height: 44)
                    .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.gray.opacity(0.25)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("notifications.detail.comment"))
            .frame(width: 58)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
    }

    private var resultControl: some View {
        HStack(spacing: 0) {
            resultButton(.no, titleKey: "notifications.detail.result.no")
            resultButton(.yes, titleKey: "notifications.detail.result.yes")
        }
        .background(Color(white: 0.94), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func resultButton(_ value: NotificationReviewResult, titleKey: String) -> some View {
        Button { selectResult(value) } label: {
            Text(LocalizedStringKey(titleKey))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(result == value ? .white : .secondary)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(result == value ? FacilityTheme.accent : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
