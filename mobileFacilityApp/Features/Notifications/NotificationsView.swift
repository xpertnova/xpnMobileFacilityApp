import SwiftUI

struct NotificationStructuralFilterPresentationState {
    var isPresented = false
    var pendingFilter = NotificationStructuralFilter.empty
    var appliedFilter = NotificationStructuralFilter.empty
    var expandedField: StructuralFilterField?
}

struct NotificationsView: View {
    let demo: FacilityDemoViewModel
    @Binding var filterPresentation: NotificationStructuralFilterPresentationState
    @State private var query = ""
    @State private var filterSelection: NotificationFilter = .all
    @State private var lastVisibleNotificationID: String?
    @State private var scrollRestoreID: String?

    private let notificationPrefetchThreshold = 8

    enum NotificationFilter {
        case all, attention, draft
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
        guard !query.isEmpty else { return filtered }
        return filtered.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.location.localizedCaseInsensitiveContains(query) ||
            $0.id.localizedCaseInsensitiveContains(query)
        }
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
            if let selectedSAPNotification = demo.selectedSAPNotification {
                SAPNotificationDetailScreen(
                    summary: selectedSAPNotification,
                    offlineWorkStore: demo.offlineWorkStore,
                    dismiss: { demo.selectedNotificationID = nil }
                )
                .id(selectedSAPNotification.id)
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
            .padding(28)
            .frame(maxWidth: 1280, alignment: .leading)
            
            ScrollViewReader { proxy in
                ScrollView {
                    notificationContent
                        .padding(.horizontal, 28)
                        .padding(.bottom, 28)
                        .frame(maxWidth: 1280, alignment: .leading)
                }
                .task(id: scrollRestoreID) {
                    guard let scrollRestoreID else { return }
                    proxy.scrollTo(scrollRestoreID, anchor: .center)
                    self.scrollRestoreID = nil
                }
            }
        }
        .background(Color(white: 0.97).ignoresSafeArea())
        .task(id: filterPreferenceScope) {
            let restoredFilter = NotificationStructuralFilterPreferences.load(
                workerID: demo.sapDataStore.localWorkerID,
                isDemoMode: demo.isDemoMode
            )
            filterPresentation.pendingFilter = restoredFilter
            filterPresentation.appliedFilter = restoredFilter
            guard !demo.isDemoMode else { return }
            await demo.sapDataStore.updateNotificationStructuralFilter(restoredFilter)
            await demo.sapDataStore.loadCachedData()
        }
        .task(id: query) {
            guard !demo.isDemoMode else { return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await demo.sapDataStore.updateNotificationSearch(query)
        }
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

                if filterPresentation.appliedFilter.hasBusinessEntity {
                    Image(systemName: "checkmark.circle.fill")
                        .accessibilityHidden(true)
                }
            }
            .fontWeight(.semibold)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(FacilityTheme.accent)
        .background(
            filterPresentation.appliedFilter.hasBusinessEntity ? FacilityTheme.accentSoft : .clear,
            in: Capsule()
        )
        .accessibilityLabel(Text("notifications.structuralFilter.open"))
        .accessibilityValue(
            filterPresentation.appliedFilter.hasBusinessEntity
                ? Text("\(appliedStructuralFilterNotificationCount)")
                : Text("—")
        )
    }

    private var filterButtonSymbol: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.title3)
                .frame(width: 26, height: 26, alignment: .bottomLeading)

            if filterPresentation.appliedFilter.hasBusinessEntity {
                Text(appliedStructuralFilterNotificationCount, format: .number)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 19, minHeight: 19)
                    .background(FacilityTheme.accent, in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(.white, lineWidth: 1.5)
                    }
                    .offset(x: 7, y: -5)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 33, height: 28, alignment: .bottomLeading)
        .accessibilityHidden(true)
    }

    private var filterPreferenceScope: String {
        "\(demo.isDemoMode ? "demo" : "production")-\(demo.sapDataStore.localWorkerID)"
    }

    private func presentStructuralFilter() {
        withAnimation(.snappy(duration: 0.32, extraBounce: 0)) {
            filterPresentation.pendingFilter = filterPresentation.appliedFilter
            filterPresentation.expandedField = nil
            filterPresentation.isPresented = true
        }
    }

    @ViewBuilder
    private var notificationContent: some View {
        if !demo.isDemoMode, demo.sapDataStore.state == .loadingCache {
            ProgressView("sap.cache.loading")
                .frame(maxWidth: .infinity, minHeight: 260)
        } else if !demo.isDemoMode, demo.sapDataStore.state == .noData {
            sapEmptyState
        } else if !demo.isDemoMode, demo.sapDataStore.state == .failed, !demo.sapDataStore.hasCache {
            sapUnavailableState
        } else {
            notificationList
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Text("🔍")
                .font(.body)
                .accessibilityHidden(true)
            TextField("notifications.search", text: $query)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 40)
        .background(Color(white: 0.92), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var notificationList: some View {
        LazyVStack(spacing: 16) {
            if visibleNotifications.isEmpty {
                if !demo.isDemoMode, demo.sapDataStore.hasMoreNotifications {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 180)
                        .task(id: demo.sapDataStore.notifications.count) {
                            await demo.sapDataStore.loadMoreNotifications()
                        }
                } else {
                    EmptyDemoState(
                        symbol: "tray",
                        titleKey: "notifications.empty.title",
                        subtitleKey: "notifications.empty.subtitle"
                    )
                }
            } else {
                ForEach(visibleNotifications) { notification in
                    NotificationRow(notification: notification, isSelected: demo.selectedNotificationID == notification.id) {
                        scrollRestoreID = lastVisibleNotificationID ?? notification.id
                        demo.selectedOfflineNotificationDetail = nil
                        demo.selectedNotificationID = notification.id
                    }
                    .id(notification.id)
                    .onAppear {
                        lastVisibleNotificationID = notification.id
                        prefetchNextPageIfNeeded(for: notification)
                    }
                }

                if !demo.isDemoMode, demo.sapDataStore.isLoadingMoreNotifications {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }

            if let notification = demo.selectedNotification {
                NotificationDetailCard(notification: notification, isReadOnly: !demo.isDemoMode) {
                    demo.finishChecks(for: notification)
                }
            }
        }
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

    private func prefetchNextPageIfNeeded(for notification: MaintenanceNotification) {
        guard !demo.isDemoMode, demo.sapDataStore.hasMoreNotifications else { return }
        guard let index = visibleNotifications.firstIndex(where: { $0.id == notification.id }) else { return }
        let prefetchStartIndex = max(visibleNotifications.count - notificationPrefetchThreshold, 0)
        guard index >= prefetchStartIndex else { return }

        Task {
            await demo.sapDataStore.loadMoreNotifications()
        }
    }
}

struct NotificationStructuralFilterOverlay: View {
    let demo: FacilityDemoViewModel
    @Binding var presentation: NotificationStructuralFilterPresentationState

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.42)
                    .ignoresSafeArea()
                    .onTapGesture(perform: dismiss)

                filterCard
                    .frame(width: min(max(proxy.size.width * 0.72, 760), 1_040))
                    .frame(height: min(590, max(320, proxy.size.height - 48)))
                    .padding(28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityAddTraits(.isModal)
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
        VStack(alignment: .leading, spacing: 18) {
                picker(
                    field: .businessEntity,
                    titleKey: "notifications.structuralFilter.businessEntity",
                    placeholderKey: "notifications.structuralFilter.businessEntity.placeholder",
                    selection: presentation.pendingFilter.businessEntityID,
                    options: businessEntityOptions,
                    isEnabled: !businessEntityOptions.isEmpty
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
                    options: buildingOptions,
                    isEnabled: presentation.pendingFilter.hasBusinessEntity && !buildingOptions.isEmpty
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
                    options: tradeOptions,
                    isEnabled: !presentation.pendingFilter.buildingCode.isEmpty && !tradeOptions.isEmpty
                ) { option in
                    presentation.pendingFilter.tradeCode = option.id
                    presentation.pendingFilter.formCode = ""
                }

                picker(
                    field: .form,
                    titleKey: "notifications.structuralFilter.form",
                    placeholderKey: "notifications.structuralFilter.form.placeholder",
                    selection: presentation.pendingFilter.formCode,
                    options: formOptions,
                    isEnabled: !presentation.pendingFilter.tradeCode.isEmpty && !formOptions.isEmpty
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
        options: [StructuralFilterOption],
        isEnabled: Bool,
        select: @escaping (StructuralFilterOption) -> Void
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

    private func options(for field: StructuralFilterField) -> [StructuralFilterOption] {
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

    private func select(_ option: StructuralFilterOption, for field: StructuralFilterField) {
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

    private func optionList(_ options: [StructuralFilterOption], selection: String, select: @escaping (StructuralFilterOption) -> Void) -> some View {
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

    private var businessEntityOptions: [StructuralFilterOption] {
        uniqueOptions(demo.notificationFilterMetadata.filter { !$0.businessEntityID.isEmpty }.map { StructuralFilterOption(id: $0.businessEntityID, label: $0.businessEntityID) })
    }

    private var buildingOptions: [StructuralFilterOption] {
        guard presentation.pendingFilter.hasBusinessEntity else { return [] }
        return uniqueOptions(demo.notificationFilterMetadata.compactMap { metadata in
            guard metadata.businessEntityID == presentation.pendingFilter.businessEntityID, !metadata.buildingCode.isEmpty else { return nil }
            let label = metadata.functionalLocationName.isEmpty ? metadata.buildingCode : "\(metadata.buildingCode) — \(metadata.functionalLocationName)"
            return StructuralFilterOption(id: metadata.buildingCode, label: label)
        })
    }

    private var tradeOptions: [StructuralFilterOption] {
        guard presentation.pendingFilter.hasBusinessEntity, !presentation.pendingFilter.buildingCode.isEmpty else { return [] }
        return uniqueOptions(demo.notificationFilterMetadata.compactMap { metadata in
            guard metadata.businessEntityID == presentation.pendingFilter.businessEntityID, metadata.buildingCode == presentation.pendingFilter.buildingCode, !metadata.tradeCode.isEmpty else { return nil }
            return StructuralFilterOption(id: metadata.tradeCode, label: metadata.tradeCode)
        })
    }

    private var formOptions: [StructuralFilterOption] {
        guard presentation.pendingFilter.hasBusinessEntity, !presentation.pendingFilter.buildingCode.isEmpty, !presentation.pendingFilter.tradeCode.isEmpty else { return [] }
        return uniqueOptions(demo.notificationFilterMetadata.compactMap { metadata in
            guard metadata.businessEntityID == presentation.pendingFilter.businessEntityID, metadata.buildingCode == presentation.pendingFilter.buildingCode, metadata.tradeCode == presentation.pendingFilter.tradeCode, !metadata.formCode.isEmpty else { return nil }
            return StructuralFilterOption(id: metadata.formCode, label: formLabel(for: metadata.formCode))
        })
    }

    private func uniqueOptions(_ options: [StructuralFilterOption]) -> [StructuralFilterOption] {
        Dictionary(grouping: options, by: \.id)
            .compactMap { $0.value.sorted { $0.label < $1.label }.first }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    private func formLabel(for code: String) -> String {
        let name: String? = switch code {
        case "TFM1": String(localized: "notifications.structuralFilter.form.tfm1")
        case "TFM3": String(localized: "notifications.structuralFilter.form.tfm3")
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

private struct StructuralFilterOption: Identifiable {
    let id: String
    let label: String
}

enum StructuralFilterField: Hashable {
    case businessEntity
    case building
    case trade
    case form
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
private struct SAPNotificationDetailScreen: View {
    @State private var detail: SAPNotificationDetail
    let offlineWorkStore: OfflineWorkStore
    let dismiss: () -> Void

    init(
        summary: SAPNotificationSummary,
        offlineWorkStore: OfflineWorkStore,
        dismiss: @escaping () -> Void
    ) {
        _detail = State(initialValue: SAPNotificationDetail(summary: summary))
        self.offlineWorkStore = offlineWorkStore
        self.dismiss = dismiss
    }

    var body: some View {
        NotificationDetailView(
            detail: detail,
            offlineWorkStore: offlineWorkStore,
            backDestination: .notifications,
            dismiss: dismiss
        )
    }
}

private struct NotificationRow: View {
    let notification: MaintenanceNotification
    let isSelected: Bool
    let action: () -> Void

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
                        Text(notification.equipment)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Text(notification.location)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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
