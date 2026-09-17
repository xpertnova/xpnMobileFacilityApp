import SwiftUI
import Observation
import UIKit

@Observable
final class NotificationStructuralFilterPresentationState {
    var isPresented = false
    var pendingFilter = NotificationStructuralFilter.empty
    var appliedFilter = NotificationStructuralFilter.empty
    var expandedField: StructuralFilterField?

    init(restoredFilter: NotificationStructuralFilter = .empty) {
        pendingFilter = restoredFilter
        appliedFilter = restoredFilter
    }
}

struct NotificationsView: View {
    let demo: FacilityDemoViewModel
    let filterPresentation: NotificationStructuralFilterPresentationState
    @State private var appliedSearchQuery = ""
    @State private var filterSelection: NotificationFilter = .all
    @Environment(\.facilityLayout) private var layout

    init(
        demo: FacilityDemoViewModel,
        filterPresentation: NotificationStructuralFilterPresentationState
    ) {
        self.demo = demo
        self.filterPresentation = filterPresentation
    }

    enum NotificationFilter: Equatable {
        case all, attention, draft
    }

    /// Demo notifications are already held in memory. Production uses the cache query's
    /// total, so the badge does not shrink to the currently loaded pagination page.
    private var appliedStructuralFilterNotificationCount: Int {
        guard filterPresentation.appliedFilter.hasBusinessEntity else { return 0 }

        if demo.isDemoMode {
            return demo.visibleNotifications.filter {
                filterPresentation.appliedFilter.matches($0.structuralFilterMetadata)
            }.count
        }

        return demo.sapDataStore.matchingNotificationCount
    }

    var body: some View {
        ZStack {
            if let detail = demo.selectedNotificationDetail {
                NotificationDetailScreen(
                    detail: detail,
                    offlineWorkStore: demo.offlineWorkStore,
                    photoAttachmentStore: demo.photoAttachmentStore,
                    sapDataStore: demo.sapDataStore,
                    elevatorAssetDataProvider: demo.elevatorAssetDataProvider,
                    dismiss: { demo.selectedNotificationID = nil }
                )
                // The same notification can be opened again after the
                // blocking master-data warning. Use the presentation token,
                // not only its stable SAP number, so the form reloads and
                // re-evaluates that warning every time.
                .id(demo.notificationDetailPresentationID)
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(1)
            } else {
                notificationOverview
                    .transition(.opacity)
            }

        }
        .animation(.snappy(duration: 0.32, extraBounce: 0), value: demo.selectedNotificationID)
    }

    private var notificationOverview: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader("notifications.title", subtitle: "notifications.subtitle", trailing: AnyView(headerTrailing))
                searchBar
            }
            .facilityPageContent()
            #if DEBUG
            .keyboardDebugFrame("header+search")
            #endif

            notificationList
            #if DEBUG
                .keyboardDebugFrame("list")
            #endif
        }
        // Keyboard avoidance for the list is disabled at the window root in AppRootView.
        .background(Color(white: 0.97).ignoresSafeArea())
        #if DEBUG
        .keyboardDebugFrame("overview")
        .onAppear { KeyboardDebugObserver.shared.start() }
        #endif
    }

    @ViewBuilder
    private var headerTrailing: some View {
        ViewThatFits(in: .horizontal) {
            notificationHeaderControls(showsFilterTitle: true, statusControlWidth: 330)
            notificationHeaderControls(showsFilterTitle: false, statusControlWidth: 280)
        }
    }

    private func notificationHeaderControls(
        showsFilterTitle: Bool,
        statusControlWidth: CGFloat
    ) -> some View {
        HStack(spacing: 12) {
            structuralFilterButton(showsTitle: showsFilterTitle)

            Picker("notifications.filter.accessibility", selection: $filterSelection) {
                Text("notifications.filter.all").tag(NotificationFilter.all)
                Text("notifications.filter.attention").tag(NotificationFilter.attention)
                Text("notifications.filter.draft").tag(NotificationFilter.draft)
            }
            .pickerStyle(.segmented)
            .frame(width: statusControlWidth)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func structuralFilterButton(showsTitle: Bool) -> some View {
        Button(action: presentStructuralFilter) {
            HStack(spacing: 7) {
                filterButtonSymbol

                if showsTitle {
                    Text("notifications.structuralFilter.open")
                        .lineLimit(1)
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(
                filterPresentation.appliedFilter.hasBusinessEntity ? .white : FacilityTheme.ink
            )
            .padding(.horizontal, showsTitle ? 14 : 0)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: showsTitle ? nil : 48, minHeight: 44)
            .background(
                filterPresentation.appliedFilter.hasBusinessEntity ? FacilityTheme.accent : FacilityTheme.surface,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        filterPresentation.appliedFilter.hasBusinessEntity
                            ? Color.white.opacity(0.22)
                            : FacilityTheme.accent.opacity(0.26),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: filterPresentation.appliedFilter.hasBusinessEntity
                    ? FacilityTheme.accent.opacity(0.18)
                    : Color.black.opacity(0.04),
                radius: 5,
                y: 2
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("notifications.structuralFilter.open"))
        .accessibilityValue(
            filterPresentation.appliedFilter.hasBusinessEntity
                ? Text("\(appliedStructuralFilterNotificationCount)")
                : Text("—")
        )
        .accessibilityAddTraits(
            filterPresentation.appliedFilter.hasBusinessEntity ? .isSelected : []
        )
        .animation(.smooth(duration: 0.2), value: filterPresentation.appliedFilter.hasBusinessEntity)
    }

    private var filterButtonSymbol: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.body.weight(.semibold))
                .frame(width: 24, height: 24, alignment: .bottomLeading)

            if filterPresentation.appliedFilter.hasBusinessEntity {
                Text(appliedStructuralFilterNotificationCount, format: .number)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(FacilityTheme.accent)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 19, minHeight: 19)
                    .background(.white, in: Capsule())
                    .offset(x: 7, y: -6)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 31, height: 26, alignment: .bottomLeading)
        .accessibilityHidden(true)
    }

    private func presentStructuralFilter() {
        withAnimation(.snappy(duration: 0.32, extraBounce: 0)) {
            filterPresentation.pendingFilter = filterPresentation.appliedFilter
            filterPresentation.expandedField = nil
            filterPresentation.isPresented = true
        }
    }

    private func applySearch(_ query: String) {
        guard query != appliedSearchQuery else { return }
        appliedSearchQuery = query
        guard !demo.isDemoMode else { return }

        Task {
            await demo.sapDataStore.updateNotificationSearch(query)
        }
    }

    private var searchBar: some View {
        NotificationSearchBar(onSearch: applySearch)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
    }

    private var notificationList: some View {
        EquatableView(
            content: NotificationListContent(
                demo: demo,
                filterPresentation: filterPresentation,
                filterSelection: filterSelection,
                appliedSearchQuery: appliedSearchQuery,
                pagePadding: layout.pagePadding
            )
        )
    }
}

/// A UIKit input keeps every keystroke out of SwiftUI's render graph. The
/// enclosing list only receives a value after Search or Return is pressed.
private struct NotificationSearchBar: UIViewRepresentable {
    let onSearch: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSearch: onSearch)
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor(white: 0.92, alpha: 1)
        container.layer.cornerRadius = 10

        let symbol = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        symbol.tintColor = .secondaryLabel
        symbol.contentMode = .scaleAspectFit

        let textField = UITextField()
        textField.placeholder = String(localized: "notifications.search")
        textField.font = .preferredFont(forTextStyle: .body)
        textField.textColor = .label
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.returnKeyType = .search
        textField.delegate = context.coordinator
        textField.accessibilityLabel = String(localized: "notifications.search")
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let button = UIButton(type: .system)
        button.setTitle(String(localized: "notifications.search.action"), for: .normal)
        button.setImage(UIImage(systemName: "magnifyingglass"), for: .normal)
        button.tintColor = .white
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .subheadline).withSize(15)
        button.semanticContentAttribute = .forceLeftToRight
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.backgroundColor = UIColor(FacilityTheme.accent)
        button.layer.cornerRadius = 12
        button.accessibilityLabel = String(localized: "notifications.search.action")
        button.addTarget(context.coordinator, action: #selector(Coordinator.submitSearch), for: .touchUpInside)

        [symbol, textField, button].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview($0)
        }
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 44),
            symbol.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            symbol.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            symbol.widthAnchor.constraint(equalToConstant: 18),
            symbol.heightAnchor.constraint(equalToConstant: 18),
            textField.leadingAnchor.constraint(equalTo: symbol.trailingAnchor, constant: 8),
            textField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            button.leadingAnchor.constraint(equalTo: textField.trailingAnchor, constant: 8),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            button.topAnchor.constraint(equalTo: container.topAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        context.coordinator.textField = textField
        return container
    }

    func updateUIView(_: UIView, context: Context) {
        context.coordinator.onSearch = onSearch
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var onSearch: (String) -> Void
        weak var textField: UITextField?

        init(onSearch: @escaping (String) -> Void) {
            self.onSearch = onSearch
        }

        func textFieldShouldReturn(_: UITextField) -> Bool {
            submitSearch()
            return false
        }

        @objc func submitSearch() {
            guard let textField else { return }
            let query = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            textField.resignFirstResponder()
            onSearch(query)
        }
    }
}

private struct NotificationListContent: View, Equatable {
    let demo: FacilityDemoViewModel
    let filterPresentation: NotificationStructuralFilterPresentationState
    let filterSelection: NotificationsView.NotificationFilter
    let appliedSearchQuery: String
    /// Passed in rather than read from the environment, so the equatable
    /// list redraws with the header when the window changes size.
    let pagePadding: CGFloat

    private let notificationPrefetchThreshold = 8

    static func == (lhs: NotificationListContent, rhs: NotificationListContent) -> Bool {
        lhs.demo === rhs.demo
            && lhs.filterPresentation === rhs.filterPresentation
            && lhs.filterSelection == rhs.filterSelection
            && lhs.appliedSearchQuery == rhs.appliedSearchQuery
            && lhs.pagePadding == rhs.pagePadding
    }

    private var visibleNotifications: [MaintenanceNotification] {
        let structurallyFiltered = demo.isDemoMode
            ? demo.visibleNotifications.filter { filterPresentation.appliedFilter.matches($0.structuralFilterMetadata) }
            : demo.visibleNotifications
        let filtered = structurallyFiltered.filter { notification in
            switch filterSelection {
            case .all: return true
            case .attention: return notification.status == .attention || notification.hasLocalDefect
            case .draft: return notification.status == .draft
            }
        }
        guard !appliedSearchQuery.isEmpty else { return filtered }
        return filtered.filter {
            $0.title.localizedCaseInsensitiveContains(appliedSearchQuery)
                || $0.location.localizedCaseInsensitiveContains(appliedSearchQuery)
                || $0.id.localizedCaseInsensitiveContains(appliedSearchQuery)
        }
    }

    var body: some View {
        let notifications = visibleNotifications
        return List {
            if !demo.isDemoMode, demo.sapDataStore.state == .loadingCache {
                notificationListRow(bottomInset: 28) {
                    ProgressView("sap.cache.loading")
                        .frame(maxWidth: .infinity, minHeight: 260)
                }
            } else if !demo.isDemoMode, demo.sapDataStore.state == .noData {
                notificationListRow(bottomInset: 28) {
                    sapEmptyState
                }
            } else if !demo.isDemoMode, demo.sapDataStore.state == .failed, !demo.sapDataStore.hasCache {
                notificationListRow(bottomInset: 28) {
                    sapUnavailableState
                }
            } else if notifications.isEmpty {
                if !demo.isDemoMode, demo.sapDataStore.hasMoreNotifications {
                    notificationListRow(bottomInset: 28) {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 180)
                            .task(id: demo.sapDataStore.notifications.count) {
                                await demo.sapDataStore.loadMoreNotifications()
                            }
                    }
                } else {
                    notificationListRow(bottomInset: 28) {
                        EmptyDemoState(
                            symbol: "tray",
                            titleKey: "notifications.empty.title",
                            subtitleKey: "notifications.empty.subtitle"
                        )
                    }
                }
            } else {
                ForEach(notifications) { notification in
                    notificationListRow {
                        EquatableView(
                            content: NotificationRow(
                                notification: notification,
                                isSelected: demo.selectedNotificationID == notification.id
                            ) {
                                demo.selectedOfflineNotificationDetail = nil
                                demo.selectedNotificationID = notification.id
                            }
                        )
                        .id(notification.id)
                        .onAppear {
                            prefetchNextPageIfNeeded(for: notification, in: notifications)
                        }
                    }
                }

                if !demo.isDemoMode, demo.sapDataStore.isLoadingMoreNotifications {
                    notificationListRow(bottomInset: 28) {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                }
            }

            if let notification = demo.selectedNotification, demo.selectedNotificationDetail == nil {
                notificationListRow(bottomInset: 28) {
                    NotificationDetailCard(notification: notification, isReadOnly: !demo.isDemoMode) {
                        demo.finishChecks(for: notification)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 0, for: .scrollContent)
        .contentMargins(.bottom, 28, for: .scrollContent)
        .scrollDismissesKeyboard(.never)
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private func notificationListRow<Content: View>(
        bottomInset: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: FacilityLayoutMetrics.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        .listRowInsets(EdgeInsets(top: 0, leading: pagePadding, bottom: bottomInset, trailing: pagePadding))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var sapEmptyState: some View {
        ContentUnavailableView {
            Label("sap.cache.empty.title", systemImage: "arrow.down.circle")
        } description: {
            Text("sap.cache.empty.message")
        } actions: {
            Button("sap.refresh.action") {
                demo.requestSAPRefresh()
            }
            .buttonStyle(.borderedProminent)
            .tint(FacilityTheme.accent)
            .disabled(!demo.sapDataStore.isRefreshAvailable)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }

    private var sapUnavailableState: some View {
        ContentUnavailableView {
            Label("sap.refresh.error.title", systemImage: "exclamationmark.triangle")
        } description: {
            Text(errorMessage)
        } actions: {
            Button("sap.refresh.action") {
                demo.requestSAPRefresh()
            }
            .buttonStyle(.borderedProminent)
            .tint(FacilityTheme.accent)
            .disabled(!demo.sapDataStore.isRefreshAvailable)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }

    private var errorMessage: String {
        sapRefreshErrorMessage(demo.sapDataStore.refreshError)
    }

    private func prefetchNextPageIfNeeded(
        for notification: MaintenanceNotification,
        in notifications: [MaintenanceNotification]
    ) {
        guard !demo.isDemoMode, demo.sapDataStore.hasMoreNotifications else { return }
        guard let index = notifications.firstIndex(where: { $0.id == notification.id }) else { return }
        let prefetchStartIndex = max(notifications.count - notificationPrefetchThreshold, 0)
        guard index >= prefetchStartIndex else { return }

        Task {
            await demo.sapDataStore.loadMoreNotifications()
        }
    }
}

struct NotificationStructuralFilterOverlay: View {
    let demo: FacilityDemoViewModel
    let presentation: NotificationStructuralFilterPresentationState

    @Environment(\.facilityLayout) private var layout

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.42)
                    .ignoresSafeArea()
                    .onTapGesture(perform: dismiss)

                filterCard
                    .frame(width: cardWidth(in: proxy.size), height: cardHeight(in: proxy.size))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityAddTraits(.isModal)
    }

    /// 72 % of the space, between 760 and 1040 pt, but never closer to the
    /// edges than the dialog margin: a Split View pane can be narrower than
    /// the 760 pt the filter prefers.
    private func cardWidth(in size: CGSize) -> CGFloat {
        let preferred = min(max(size.width * 0.72, 760), 1_040)
        return max(0, min(preferred, size.width - layout.dialogMargin * 2))
    }

    private func cardHeight(in size: CGSize) -> CGFloat {
        let preferred = min(590, max(320, size.height - 48))
        return max(0, min(preferred, size.height - layout.dialogMargin * 2))
    }

    private var filterCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .font(.title2)
                    .foregroundStyle(FacilityTheme.accent)
                    .frame(width: 46, height: 46)
                    .background(FacilityTheme.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text("notifications.structuralFilter.title")
                        .font(.title3.weight(.bold))
                    Text("notifications.structuralFilter.subtitle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.bold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(FacilityTheme.accent)
                .background(FacilityTheme.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityLabel(Text("app.button.close"))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(FacilityTheme.accent.opacity(0.75))
                    .frame(height: 2)
                    .padding(.horizontal, 24)
            }

            ScrollView(.vertical, showsIndicators: false) {
                filterFields
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
            }
            .scrollBounceBehavior(.basedOnSize)

            Spacer(minLength: 12)

            HStack(spacing: 12) {
                Button("notifications.structuralFilter.clear", action: clear)
                    .buttonStyle(.bordered)
                    .tint(FacilityTheme.accent)
                    .font(.body.weight(.regular))
                    .disabled(!presentation.pendingFilter.hasBusinessEntity && !presentation.appliedFilter.hasBusinessEntity)

                Spacer()

                Button("notifications.structuralFilter.apply", action: apply)
                    .buttonStyle(.borderedProminent)
                    .tint(FacilityTheme.accent)
                    .font(.body.weight(.regular))
                    .disabled(!presentation.pendingFilter.hasBusinessEntity)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
            .zIndex(1)
        }
        .foregroundStyle(FacilityTheme.ink)
        .background(FacilityTheme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(FacilityTheme.accent.opacity(0.65), lineWidth: 2)
        }
        .overlayPreferenceValue(StructuralFilterControlAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if let expandedField = presentation.expandedField,
                   let anchor = anchors[expandedField] {
                    let controlFrame = proxy[anchor]
                    optionList(
                        options(for: expandedField),
                        selection: selection(for: expandedField)
                    ) { option in
                        select(option, for: expandedField)
                    }
                    .frame(width: controlFrame.width)
                    .offset(x: controlFrame.minX, y: controlFrame.maxY + 4)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                    .zIndex(3)
                }
            }
        }
        .shadow(color: Color.black.opacity(0.30), radius: 34, y: 18)
    }

    private var filterFields: some View {
        let businessEntities = businessEntityOptions
        let buildings = buildingOptions
        let trades = tradeOptions
        let forms = formOptions
        return VStack(alignment: .leading, spacing: 18) {
                picker(
                    field: .businessEntity,
                    titleKey: "notifications.structuralFilter.businessEntity",
                    placeholderKey: "notifications.structuralFilter.businessEntity.placeholder",
                    selection: presentation.pendingFilter.businessEntityID,
                    options: businessEntities,
                    isEnabled: !businessEntities.isEmpty
                ) { option in
                    presentation.pendingFilter.businessEntityID = option.id
                    presentation.pendingFilter.buildingCode = ""
                    presentation.pendingFilter.tradeCode = ""
                    presentation.pendingFilter.formCode = ""
                }

                picker(
                    field: .building,
                    titleKey: "notifications.structuralFilter.building",
                    placeholderKey: "notifications.structuralFilter.building.placeholder",
                    selection: presentation.pendingFilter.buildingCode,
                    options: buildings,
                    isEnabled: presentation.pendingFilter.hasBusinessEntity && !buildings.isEmpty
                ) { option in
                    presentation.pendingFilter.buildingCode = option.id
                    presentation.pendingFilter.tradeCode = ""
                    presentation.pendingFilter.formCode = ""
                }

                picker(
                    field: .trade,
                    titleKey: "notifications.structuralFilter.trade",
                    placeholderKey: "notifications.structuralFilter.trade.placeholder",
                    selection: presentation.pendingFilter.tradeCode,
                    options: trades,
                    isEnabled: !presentation.pendingFilter.buildingCode.isEmpty && !trades.isEmpty
                ) { option in
                    presentation.pendingFilter.tradeCode = option.id
                    presentation.pendingFilter.formCode = ""
                }

                picker(
                    field: .form,
                    titleKey: "notifications.structuralFilter.form",
                    placeholderKey: "notifications.structuralFilter.form.placeholder",
                    selection: presentation.pendingFilter.formCode,
                    options: forms,
                    isEnabled: !presentation.pendingFilter.tradeCode.isEmpty && !forms.isEmpty
                ) { option in
                    presentation.pendingFilter.formCode = option.id
                }
        }
    }

    private func picker(
        field: StructuralFilterField,
        titleKey: LocalizedStringKey,
        placeholderKey: LocalizedStringKey,
        selection: String,
        options: [NotificationStructuralFilterOption],
        isEnabled: Bool,
        select: @escaping (NotificationStructuralFilterOption) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(titleKey)
                .font(.subheadline.weight(.semibold))

            Button {
                guard isEnabled else { return }
                withAnimation(.snappy(duration: 0.28, extraBounce: 0)) {
                    presentation.expandedField = presentation.expandedField == field ? nil : field
                }
            } label: {
                HStack(spacing: 12) {
                    if let selectedOption = options.first(where: { $0.id == selection }) {
                        Text(selectedOption.label)
                            .foregroundStyle(FacilityTheme.ink)
                            .lineLimit(1)
                    } else {
                        Text(placeholderKey)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isEnabled ? FacilityTheme.accent : .secondary)
                        .rotationEffect(.degrees(presentation.expandedField == field ? 180 : 0))
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(isEnabled ? Color(white: 0.94) : Color(white: 0.91), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(presentation.expandedField == field ? FacilityTheme.accent : .clear, lineWidth: 2)
                }
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .anchorPreference(key: StructuralFilterControlAnchorKey.self, value: .bounds) { [field: $0] }
            .accessibilityLabel(Text(titleKey))
            .accessibilityValue(
                selection.isEmpty
                    ? Text(placeholderKey)
                    : Text(options.first(where: { $0.id == selection })?.label ?? selection)
            )
        }
    }

    private func options(for field: StructuralFilterField) -> [NotificationStructuralFilterOption] {
        switch field {
        case .businessEntity: businessEntityOptions
        case .building: buildingOptions
        case .trade: tradeOptions
        case .form: formOptions
        }
    }

    private func selection(for field: StructuralFilterField) -> String {
        switch field {
        case .businessEntity: presentation.pendingFilter.businessEntityID
        case .building: presentation.pendingFilter.buildingCode
        case .trade: presentation.pendingFilter.tradeCode
        case .form: presentation.pendingFilter.formCode
        }
    }

    private func select(_ option: NotificationStructuralFilterOption, for field: StructuralFilterField) {
        withAnimation(.snappy(duration: 0.28, extraBounce: 0)) {
            switch field {
            case .businessEntity:
                presentation.pendingFilter.businessEntityID = option.id
                presentation.pendingFilter.buildingCode = ""
                presentation.pendingFilter.tradeCode = ""
                presentation.pendingFilter.formCode = ""
            case .building:
                presentation.pendingFilter.buildingCode = option.id
                presentation.pendingFilter.tradeCode = ""
                presentation.pendingFilter.formCode = ""
            case .trade:
                presentation.pendingFilter.tradeCode = option.id
                presentation.pendingFilter.formCode = ""
            case .form:
                presentation.pendingFilter.formCode = option.id
            }
            presentation.expandedField = nil
        }
    }

    private func optionList(
        _ options: [NotificationStructuralFilterOption],
        selection: String,
        select: @escaping (NotificationStructuralFilterOption) -> Void
    ) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(options) { option in
                    Button {
                        select(option)
                        presentation.expandedField = nil
                    } label: {
                        Text(option.label)
                            .foregroundStyle(FacilityTheme.ink)
                            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                            .padding(.horizontal, 18)
                            .background(option.id == selection ? FacilityTheme.accentSoft : .white)
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.black.opacity(0.08)).frame(height: 1) }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: min(max(CGFloat(options.count) * 62, 62), 240))
        .background(.white)
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(FacilityTheme.accent, lineWidth: 2) }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.20), radius: 16, y: 9)
    }

    private var businessEntityOptions: [NotificationStructuralFilterOption] {
        demo.notificationFilterOptions.businessEntityOptions
    }

    private var buildingOptions: [NotificationStructuralFilterOption] {
        guard presentation.pendingFilter.hasBusinessEntity else { return [] }
        return demo.notificationFilterOptions.buildingOptions(
            for: presentation.pendingFilter.businessEntityID
        )
    }

    private var tradeOptions: [NotificationStructuralFilterOption] {
        guard presentation.pendingFilter.hasBusinessEntity, !presentation.pendingFilter.buildingCode.isEmpty else { return [] }
        return demo.notificationFilterOptions.tradeOptions(
            for: presentation.pendingFilter.businessEntityID,
            buildingCode: presentation.pendingFilter.buildingCode
        )
    }

    private var formOptions: [NotificationStructuralFilterOption] {
        guard presentation.pendingFilter.hasBusinessEntity, !presentation.pendingFilter.buildingCode.isEmpty, !presentation.pendingFilter.tradeCode.isEmpty else { return [] }
        return demo.notificationFilterOptions.formOptions(
            for: presentation.pendingFilter.businessEntityID,
            buildingCode: presentation.pendingFilter.buildingCode,
            tradeCode: presentation.pendingFilter.tradeCode
        ).map { option in
            .init(id: option.id, label: formLabel(for: option.id))
        }
    }

    private func formLabel(for code: String) -> String {
        let name: String? = switch code {
        case "TFM1": String(localized: "notifications.structuralFilter.form.tfm1")
        case "TFM3": String(localized: "notifications.structuralFilter.form.tfm3")
        case "TFM5": String(localized: "mobileLadder.title")
        case "TFM7": String(localized: "notifications.structuralFilter.form.tfm7")
        default: nil
        }
        return name.map { "\(code) — \($0)" } ?? code
    }

    private func dismiss() {
        withAnimation(.snappy(duration: 0.32, extraBounce: 0)) {
            presentation.pendingFilter = presentation.appliedFilter
            presentation.expandedField = nil
            presentation.isPresented = false
        }
    }

    private func apply() {
        withAnimation(.snappy(duration: 0.32, extraBounce: 0)) {
            presentation.appliedFilter = presentation.pendingFilter
            NotificationStructuralFilterPreferences.save(presentation.pendingFilter, workerID: demo.sapDataStore.localWorkerID, isDemoMode: demo.isDemoMode)
            presentation.expandedField = nil
            presentation.isPresented = false
        }
        guard !demo.isDemoMode else { return }
        Task { await demo.sapDataStore.updateNotificationStructuralFilter(presentation.pendingFilter) }
    }

    private func clear() {
        withAnimation(.snappy(duration: 0.32, extraBounce: 0)) {
            presentation.pendingFilter = .empty
            presentation.appliedFilter = .empty
            NotificationStructuralFilterPreferences.reset(workerID: demo.sapDataStore.localWorkerID, isDemoMode: demo.isDemoMode)
            presentation.expandedField = nil
            presentation.isPresented = false
        }
        guard !demo.isDemoMode else { return }
        Task { await demo.sapDataStore.updateNotificationStructuralFilter(.empty) }
    }
}

enum StructuralFilterField: Hashable {
    case businessEntity
    case building
    case trade
    case form
}

struct NotificationStructuralFilterOverlayHost: View {
    let demo: FacilityDemoViewModel
    let presentation: NotificationStructuralFilterPresentationState

    var body: some View {
        if presentation.isPresented {
            NotificationStructuralFilterOverlay(
                demo: demo,
                presentation: presentation
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
            .zIndex(2)
        }
    }
}

private struct StructuralFilterControlAnchorKey: PreferenceKey {
    static var defaultValue: [StructuralFilterField: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [StructuralFilterField: Anchor<CGRect>],
        nextValue: () -> [StructuralFilterField: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

/// Holds the decoded `FELDWERT` detail for the lifetime of one selected
/// notification. Rebuilding it in `NotificationsView.body` made decoding part
/// of unrelated SwiftUI invalidations while the user was reading the checklist.
private struct NotificationDetailScreen: View {
    let detail: SAPNotificationDetail
    let offlineWorkStore: OfflineWorkStore
    let photoAttachmentStore: any PhotoAttachmentStore
    let sapDataStore: SAPDataStore?
    let elevatorAssetDataProvider: (any ElevatorAssetDataProviding)?
    let dismiss: () -> Void

    var body: some View {
        if let form = detail.equipmentInspectionForm {
            EquipmentInspectionView(
                detail: detail,
                form: form,
                offlineWorkStore: offlineWorkStore,
                photoAttachmentStore: photoAttachmentStore,
                sapDataStore: sapDataStore,
                elevatorAssetDataProvider: elevatorAssetDataProvider ?? sapDataStore ?? UnavailableElevatorAssetDataProvider(),
                backDestination: .notifications,
                dismiss: dismiss
            )
        } else if detail.formCode.uppercased() == "TFM1" {
            WartungsplanDetailView(
                detail: detail,
                offlineWorkStore: offlineWorkStore,
                photoAttachmentStore: photoAttachmentStore,
                sapDataStore: sapDataStore,
                backDestination: .notifications,
                dismiss: dismiss
            )
        } else {
            NotificationDetailView(
                detail: detail,
                offlineWorkStore: offlineWorkStore,
                photoAttachmentStore: photoAttachmentStore,
                sapDataStore: sapDataStore,
                backDestination: .notifications,
                dismiss: dismiss
            )
        }
    }
}

private struct NotificationRow: View, Equatable {
    private static let minimumHeight: CGFloat = 160

    let notification: MaintenanceNotification
    let isSelected: Bool
    let action: () -> Void

    /// The action always selects this same notification in the shared view
    /// model, so it is intentionally excluded from the render-state comparison.
    static func == (lhs: NotificationRow, rhs: NotificationRow) -> Bool {
        lhs.notification == rhs.notification && lhs.isSelected == rhs.isSelected
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 16) {
                let iconConfig = iconFor(status: notification.status)
                
                Text(iconConfig.icon)
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .background(iconConfig.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(notification.title) · Meldung \(notification.id.replacingOccurrences(of: "M-", with: "47100000"))")
                        .font(.headline)
                        .foregroundStyle(FacilityTheme.ink)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        if !notification.equipment.isEmpty {
                            Text(notification.equipment)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        if !notification.location.isEmpty, notification.location != notification.equipment {
                            Text(notification.location)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    HStack(alignment: .bottom) {
                        Text(notification.dueDate)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        FacilityTemplateBadge(text: "KG 300", style: .costGroup)
                        
                        NotificationStatusBadges(notification: notification)
                        
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 8)
                    }
                }
            }
            .padding(20)
            .frame(minHeight: Self.minimumHeight, alignment: .topLeading)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? FacilityTheme.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func iconFor(status: WorkStatus) -> (icon: String, tint: Color) {
        switch status {
        case .attention:
            return ("⚠", FacilityTheme.red)
        case .draft, .pending:
            return ("💾", FacilityTheme.orange)
        case .complete, .closedLocally:
            return ("✅", FacilityTheme.accent)
        case .open:
            return ("📋", FacilityTheme.blue)
        }
    }
}

/// Mirrors the legacy overview: a local closure remains visibly local and a
/// defect found during that review stays visible beside it.
private struct NotificationStatusBadges: View {
    let notification: MaintenanceNotification

    var body: some View {
        HStack(spacing: 6) {
            if notification.hasLocalDefect {
                FacilityTemplateBadge(
                    localized: .init(WorkStatus.attention.titleKey),
                    style: .attention
                )
            }
            FacilityTemplateBadge(
                localized: .init(notification.status.titleKey),
                style: style(for: notification.status)
            )
        }
    }

    private func style(for status: WorkStatus) -> FacilityTemplateBadgeStyle {
        switch status {
        case .open:
            .open
        case .attention:
            .attention
        case .draft, .pending:
            .temporarilySaved
        case .complete, .closedLocally:
            .complete
        }
    }
}

private struct NotificationDetailCard: View {
    let notification: MaintenanceNotification
    let isReadOnly: Bool
    let finish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("notifications.detail.title")
                        .font(.title3.weight(.bold))
                    Text([notification.id, notification.location].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let sapStatus = notification.sapStatus, !sapStatus.isEmpty {
                    Text(sapStatus)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(FacilityTheme.blue)
                        .multilineTextAlignment(.trailing)
                } else {
                    StatusPill(status: notification.status)
                }
            }
            Divider()
            if isReadOnly {
                Label("sap.notifications.readOnly", systemImage: "lock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(1...notification.totalChecks, id: \.self) { index in
                    HStack(spacing: 12) {
                        Image(systemName: index <= notification.completedChecks ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(index <= notification.completedChecks ? FacilityTheme.accent : .secondary)
                        Text("\(index). \(index == 1 ? "Visual condition and access" : "Equipment inspection point")")
                            .font(.subheadline)
                        Spacer()
                        Text(index <= notification.completedChecks ? "status.complete" : "status.open")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                }
                HStack {
                    Spacer()
                    Button("notifications.detail.finish", action: finish)
                        .buttonStyle(.borderedProminent)
                        .tint(FacilityTheme.accent)
                }
            }
        }
        .facilityCard()
    }
}

// MARK: - TEMP keyboard shift diagnostics (remove after fix)

#if DEBUG
extension View {
    func keyboardDebugFrame(_ name: String) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            print("[KeyboardDebug] \(name) frame=\(frame)")
        }
    }
}

final class KeyboardDebugObserver {
    static let shared = KeyboardDebugObserver()
    private var tokens: [NSObjectProtocol] = []

    func start() {
        guard tokens.isEmpty else { return }
        let names: [Notification.Name] = [
            UIResponder.keyboardWillShowNotification,
            UIResponder.keyboardDidShowNotification,
            UIResponder.keyboardWillHideNotification,
            UIResponder.keyboardWillChangeFrameNotification,
        ]
        tokens = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
                let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
                print("[KeyboardDebug] \(name.rawValue) keyboardEnd=\(end)")
                Self.dumpScrollViews(label: name.rawValue)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    Self.dumpScrollViews(label: "\(name.rawValue) +0.6s")
                }
            }
        }
    }

    private static func dumpScrollViews(label: String) {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        for window in windows {
            print("[KeyboardDebug] (\(label)) window=\(type(of: window)) frame=\(window.frame) root=\(window.rootViewController.map { String(describing: type(of: $0)) } ?? "nil") rootViewFrame=\(window.rootViewController?.view.frame ?? .zero) safeArea=\(window.rootViewController?.view.safeAreaInsets ?? .zero)")
            visit(window, label: label)
        }
    }

    private static func visit(_ view: UIView, label: String) {
        if let scrollView = view as? UIScrollView, !(view is UITextView), scrollView.bounds.height > 200 {
            print("[KeyboardDebug] (\(label)) \(type(of: scrollView)) frame=\(scrollView.convert(scrollView.bounds, to: nil)) offset=\(scrollView.contentOffset) inset=\(scrollView.contentInset) adjusted=\(scrollView.adjustedContentInset) behavior=\(scrollView.contentInsetAdjustmentBehavior.rawValue) safeArea=\(scrollView.safeAreaInsets)")
        }
        view.subviews.forEach { visit($0, label: label) }
    }
}
#endif
