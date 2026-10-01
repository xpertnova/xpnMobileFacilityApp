import SwiftUI

struct TechnicalPlacesView: View {
    let demo: FacilityDemoViewModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var photoWorkspaceScope: LocalPhotoScope?
    @State private var documentWorkspaceScope: LocalPhotoScope?

    var body: some View {
        @Bindable var model = demo.technicalPlacesStore
        ZStack {
            if case let .createMobileLadder(anchor) = demo.technicalPlacesRoute {
                MobileLadderCreationView(demo: demo, itemID: nil, anchor: anchor, close: demo.closeMobileLadder)
                    .transition(PhotoWorkspaceMotion.destination)
            } else if case let .mobileLadderDraft(itemID) = demo.technicalPlacesRoute {
                MobileLadderCreationView(demo: demo, itemID: itemID, close: demo.closeMobileLadder)
                    .transition(PhotoWorkspaceMotion.destination)
            } else if case let .createSubdistribution(anchor) = demo.technicalPlacesRoute {
                SubdistributionCreationView(demo: demo, itemID: nil, anchor: anchor, close: demo.closeSubdistribution)
                    .transition(PhotoWorkspaceMotion.destination)
            } else if case let .subdistributionDraft(itemID) = demo.technicalPlacesRoute {
                SubdistributionCreationView(demo: demo, itemID: itemID, close: demo.closeSubdistribution)
                    .transition(PhotoWorkspaceMotion.destination)
            } else if let photoWorkspaceScope {
                LocalPhotoWorkspace(
                    scope: photoWorkspaceScope,
                    offlineWorkStore: demo.offlineWorkStore,
                    photoStore: demo.photoAttachmentStore,
                    close: { self.photoWorkspaceScope = nil }
                )
                .transition(PhotoWorkspaceMotion.destination)
                .zIndex(1)
            } else if let documentWorkspaceScope {
                LocalDocumentWorkspace(
                    scope: documentWorkspaceScope,
                    offlineWorkStore: demo.offlineWorkStore,
                    documentStore: demo.documentAttachmentStore,
                    close: { self.documentWorkspaceScope = nil }
                )
                .transition(PhotoWorkspaceMotion.destination)
                .zIndex(1)
            } else {
                Group {
                    if let detail = model.selectedDetail {
                        TechnicalObjectDetailView(
                            model: model,
                            detail: detail,
                            offlineWorkStore: demo.offlineWorkStore,
                            photoCount: photoCount(for: detail),
                            openPhotos: { photoWorkspaceScope = photoScope(for: detail) },
                            documentCount: documentCount(for: detail),
                            openDocuments: { documentWorkspaceScope = documentScope(for: detail) },
                            openNotification: demo.openLinkedNotification,
                            openDefect: { demo.openManualDefect($0) },
                            createDefect: {
                                demo.openManualDefect(preselecting: DefectObjectOption(node: detail.object))
                            },
                            openMobileLadder: {
                                demo.openMobileLadder(
                                    preselecting: TechnicalPlaceCreationAnchor(detail.object)
                                )
                            },
                            openSubdistribution: {
                                demo.openSubdistribution(
                                    preselecting: TechnicalPlaceCreationAnchor(detail.object)
                                )
                            },
                            loadInstallOptions: { await demo.equipmentInstallOptions(at: detail.object) },
                            loadCanReportDefect: { await demo.canReportDefect(on: detail.object.reference) }
                        )
                    } else {
                        hierarchy(model)
                    }
                }
                .transition(PhotoWorkspaceMotion.source)
            }
        }
        .animation(accessibilityReduceMotion ? nil : .smooth(duration: 0.24), value: model.selectedDetail != nil)
        .animation(
            accessibilityReduceMotion ? nil : PhotoWorkspaceMotion.navigation,
            value: photoWorkspaceScope
        )
        .animation(
            accessibilityReduceMotion ? nil : PhotoWorkspaceMotion.navigation,
            value: documentWorkspaceScope
        )
        .task { if model.state == .idle { await model.load() } }
        .task(id: model.query) {
            do { try await Task.sleep(for: .milliseconds(350)); await model.updateSearch() } catch { }
        }
        .alert("places.unavailable.title", isPresented: Binding(
            get: { model.unavailableActionKey != nil },
            set: { if !$0 { model.unavailableActionKey = nil } }
        )) {
            Button("common.ok", role: .cancel) { model.unavailableActionKey = nil }
        } message: { Text(LocalizedStringKey(model.unavailableActionKey ?? "places.unavailable.message")) }
    }

    private func photoScope(for detail: TechnicalObjectDetail) -> LocalPhotoScope {
        LocalPhotoScope(
            workflow: .technicalObject,
            ownerID: detail.object.reference.objectID,
            displayTitleKey: "photos.workspace.title",
            displaySubtitle: detail.object.displayName
        )
    }

    private func photoCount(for detail: TechnicalObjectDetail) -> Int {
        demo.offlineWorkStore.photoCollection(for: photoScope(for: detail))?
            .payload.photoCollection?.attachments.count ?? 0
    }

    private func documentScope(for detail: TechnicalObjectDetail) -> LocalPhotoScope {
        LocalPhotoScope(
            workflow: .technicalObject,
            ownerID: detail.object.reference.objectID,
            displayTitleKey: "documents.workspace.title",
            displaySubtitle: detail.object.displayName
        )
    }

    private func documentCount(for detail: TechnicalObjectDetail) -> Int {
        demo.offlineWorkStore.documentCollection(for: documentScope(for: detail))?
            .payload.documentCollection?.documents.count ?? 0
    }

    private func hierarchy(_ model: TechnicalPlacesViewModel) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("places.title")
                            .facilityPageTitleFont()
                            .foregroundStyle(FacilityTheme.ink)
                        Text(verbatim: subtitle(model))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    newTechnicalPlaceMenu
                }
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("places.search", text: Binding(get: { model.query }, set: { model.query = $0 }))
                        .textInputAutocapitalization(.never).submitLabel(.search)
                    if !model.query.isEmpty {
                        Button {
                            withAnimation(accessibilityReduceMotion ? nil : .smooth(duration: 0.18)) {
                                model.query = ""
                            }
                        } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .accessibilityLabel("places.search.clear")
                            .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    }
                }
                .padding(.horizontal, 16).frame(minHeight: 50)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .animation(accessibilityReduceMotion ? nil : .smooth(duration: 0.18), value: model.query.isEmpty)

                // The bar wraps instead of scrolling sideways so every cost
                // group stays visible in a narrow window.
                FacilityWrapLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    DINChip(title: String(localized: "places.filter.all", bundle: .appLanguage), selected: model.selectedDINGroup == nil) {
                        Task { await model.selectDIN(nil) }
                    }
                    ForEach(model.dinCounts) { item in
                        DINChip(
                            title: TechnicalDIN276.chipLabel(for: item.code, count: item.count),
                            selected: model.selectedDINGroup == item.code
                        ) {
                            Task { await model.selectDIN(item.code) }
                        }
                    }
                }
                .animation(accessibilityReduceMotion ? nil : .smooth(duration: 0.2), value: model.selectedDINGroup)
                if let refreshedAt = demo.sapDataStore.lastSuccessfulRefreshAt,
                   Date().timeIntervalSince(refreshedAt) > 86_400 {
                    Label("places.stale", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        .transition(.opacity)
                }
                hierarchyContent(model)
                    .animation(accessibilityReduceMotion ? nil : .smooth(duration: 0.24), value: model.state)
                    // Scoped to the results: the search field above stays
                    // usable while a query runs. `.idle` is the state the
                    // model starts in, so the frame is up on the first render.
                    .facilityBusy(
                        model.state == .idle || model.state == .loading,
                        titleKey: "places.loading"
                    )
                namingSchemaCard(model)
            }.facilityPageContent()
        }.scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder private func hierarchyContent(_ model: TechnicalPlacesViewModel) -> some View {
        switch model.state {
        case .idle, .loading:
            // The shared busy frame covers this area; the placeholder only
            // holds the height open.
            Color.clear.frame(maxWidth: .infinity, minHeight: 260)
                .transition(.opacity)
        case .empty:
            unavailable("places.empty.title", "places.empty.subtitle", "building.2")
                .transition(.opacity)
        case .noResults:
            unavailable("places.noResults.title", "places.noResults.subtitle", "magnifyingglass")
                .transition(.opacity)
        case .failed:
            ContentUnavailableView {
                Label("places.failure.title", systemImage: "exclamationmark.triangle")
            } description: { Text("places.failure.message") } actions: {
                Button("common.retry") { Task { await model.load() } }
            }.frame(maxWidth: .infinity, minHeight: 260)
            .transition(.opacity)
        case .loaded:
            TechnicalObjectHierarchyList(model: model)
                .transition(.opacity)
        }
    }

    /// Everything in the card comes from the cached SAP rows — an identifier
    /// that exists in this landscape and the TPLKZ values those rows carry —
    /// so the card is left out entirely rather than showing an example
    /// identifier the customer does not use.
    @ViewBuilder private func namingSchemaCard(_ model: TechnicalPlacesViewModel) -> some View {
        if let hint = model.namingHint {
            VStack(alignment: .leading, spacing: 6) {
                Text("places.namingSchema")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(FacilityTheme.ink)
                if !hint.structureIndicators.isEmpty {
                    Text(verbatim: String(
                        format: String(localized: "places.namingSchema.structureIndicator", bundle: .appLanguage),
                        hint.structureIndicators.joined(separator: ", ")
                    ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                Text(verbatim: String(
                    format: String(localized: "places.namingSchema.example.label", bundle: .appLanguage),
                    hint.exampleID
                ))
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .facilityCard(padding: 16)
            .transition(.opacity)
        }
    }

    /// Styled like the other screens' primary add actions (accent-filled,
    /// `borderedProminent`). `fixedSize` keeps "Neuer TP" on one line — the
    /// label wrapped mid-phrase at the old fixed minimum width — and the
    /// chevron marks it as a menu rather than a direct action.
    private var newTechnicalPlaceMenu: some View {
        Menu {
            Button { demo.openMobileLadder() } label: {
                Label("places.new.mobileLadder", systemImage: "figure.climbing")
            }
            Button { demo.openSubdistribution() } label: {
                Label("places.new.subdistribution", systemImage: "bolt.square")
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                Text("places.new").lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .opacity(0.7)
            }
            .font(.subheadline.weight(.bold))
            .padding(.horizontal, 6)
            .frame(minHeight: 30)
        }
        .buttonStyle(.borderedProminent)
        .tint(FacilityTheme.accent)
        .controlSize(.large)
        .menuOrder(.fixed)
        .fixedSize()
        .accessibilityLabel("places.new")
    }

    private func subtitle(_ model: TechnicalPlacesViewModel) -> String {
        let base = String(localized: "places.subtitle", bundle: .appLanguage)
        guard model.hasLoadedTotalCount else { return base }
        let counts = String(
            format: String(localized: "places.subtitle.counts", bundle: .appLanguage),
            model.counts.functionalLocations,
            model.counts.equipment
        )
        return "\(base) · \(counts)"
    }

    private func unavailable(_ title: LocalizedStringKey, _ subtitle: LocalizedStringKey, _ symbol: String) -> some View {
        ContentUnavailableView { Label(title, systemImage: symbol) } description: { Text(subtitle) }
            .frame(maxWidth: .infinity, minHeight: 260)
    }
}

/// The tree itself, in its own view so that expanding a branch redraws the
/// rows without invalidating the title, the search field and the cost-group
/// chips above them.
private struct TechnicalObjectHierarchyList: View {
    let model: TechnicalPlacesViewModel

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(model.visibleRows) { row in
                TechnicalObjectRow(
                    row: row,
                    displayName: model.displayName(for: row.node),
                    pendingStatus: model.pendingEdit(for: row.node)?.status,
                    isExpanded: model.expanded.contains(row.node.reference),
                    canOpenDetail: model.canOpenDetail(row.node)
                ) {
                    Task { await model.toggle(row.node) }
                } open: { Task { await model.open(row.node.reference) } }
                .transition(.opacity)

                if model.expanded.contains(row.node.reference), model.hasMoreChildren(of: row.node.reference) {
                    // The next page of a branch is pulled when its marker
                    // scrolls into view, so the tree grows as the worker moves
                    // through it instead of asking for a tap.
                    TechnicalObjectPageMarker(indent: CGFloat(row.depth + 1) * 20 + 56)
                        .task(id: model.nextChildOffset(of: row.node.reference)) {
                            await model.loadMoreChildren(of: row.node.reference)
                        }
                }
            }
            if model.hasMoreRoots {
                TechnicalObjectPageMarker(indent: 0)
                    .task(id: model.nextRootOffset) { await model.loadMoreRoots() }
            }
        }
        // The reference hierarchy separates rows by indentation and the
        // level tiles alone, without rules between them.
        .padding(.vertical, 10)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// The row that stands in for a page that has not been read yet. It pulls the
/// page as soon as it appears, so it is only ever seen as a brief spinner —
/// the same paging the notification list uses.
private struct TechnicalObjectPageMarker: View {
    let indent: CGFloat

    var body: some View {
        ProgressView()
            .controlSize(.small)
            .padding(.leading, indent)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: indent > 0 ? .leading : .center)
            .accessibilityLabel("places.loading")
    }
}

private struct DINChip: View {
    let title: String; let selected: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(verbatim: title).font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? .white : .secondary).padding(.horizontal, 14).frame(minHeight: 38)
                .background(selected ? FacilityTheme.accent : Color.white, in: Capsule())
                .overlay(Capsule().stroke(selected ? .clear : Color.secondary.opacity(0.22)))
        }
        .buttonStyle(.plain)
        .animation(.smooth(duration: 0.2), value: selected)
    }
}

private struct TechnicalObjectRow: View {
    let row: TechnicalObjectVisibleRow; let displayName: String; let pendingStatus: OfflineWorkStatus?; let isExpanded: Bool; let canOpenDetail: Bool; let toggle: () -> Void; let open: () -> Void
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: CGFloat(row.depth) * 20)
            if row.node.hasChildren {
                Button(action: toggle) {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(FacilityTheme.ink)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(accessibilityReduceMotion ? nil : .snappy(duration: 0.22, extraBounce: 0), value: isExpanded)
                        .frame(width: 30, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "places.collapse" : "places.expand")
            } else {
                // A leaf keeps the twisty column, marked with the same dot the
                // reference hierarchy uses.
                Text(verbatim: "·")
                    .font(.subheadline.bold())
                    .foregroundStyle(.tertiary)
                    .frame(width: 30, height: 44)
                    .accessibilityHidden(true)
            }
            Button(action: canOpenDetail ? open : toggle) {
                HStack(spacing: 10) {
                    Text(verbatim: level.emoji)
                        .font(.system(size: 15))
                        .frame(width: 30, height: 30)
                        .background(level.tile, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .accessibilityLabel(LocalizedStringKey(level.nameKey))
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(row.node.isUnassignedGroup ? String(localized: "places.unassigned", bundle: .appLanguage) : displayName)
                            .font(.subheadline.weight(level.nameWeight))
                            .foregroundStyle(FacilityTheme.ink)
                            .lineLimit(2)
                        if row.node.isCityGroup, !row.node.locationCode.isEmpty {
                            Text(row.node.locationCode)
                                .font(.subheadline.monospaced().weight(.semibold))
                                .foregroundStyle(.tertiary)
                        } else if !row.node.isSynthetic {
                            Text(row.node.reference.objectID)
                                .font(.subheadline.monospaced().weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 10)
                    if let din = row.node.dinGroup { ObjectBadge("KG \(din)", color: FacilityTheme.purple) }
                    if row.node.isCityGroup { ObjectBadge(String(localized: "places.badge.city", bundle: .appLanguage), color: FacilityTheme.accent) }
                    if row.node.directEquipmentCount > 0 { ObjectBadge("\(row.node.directEquipmentCount) EQ", color: .gray) }
                    if pendingStatus == .conflict { ObjectBadge(String(localized: "places.badge.conflict", bundle: .appLanguage), color: .red) }
                    else if pendingStatus != nil { ObjectBadge(String(localized: "offline.status.localOnly", bundle: .appLanguage), color: .orange) }
                    if row.node.reference.kind == .equipment {
                        ObjectBadge(String(localized: "places.badge.equipment", bundle: .appLanguage), color: .blue)
                    }
                    if canOpenDetail {
                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(TechnicalObjectRowButtonStyle())
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .accessibilityElement(children: .combine)
    }

    /// Which level of the hierarchy this row is drawn as.
    ///
    /// SAP's own `LEVELID` is not dependable across landscapes (it is empty in
    /// a lot of cached rows), so the level comes from the row's depth among the
    /// real objects, with the kind and the cost group taking precedence — the
    /// same rule the design reference applies to its own tree.
    private var level: TechnicalPlaceLevel {
        if row.node.reference.kind == .equipment { return .equipment }
        if row.node.isUnassignedGroup { return .unassigned }
        if row.node.isCityGroup { return .site }
        if row.node.dinGroup != nil { return row.node.hasChildren ? .costGroup : .system }
        switch row.structuralDepth {
        case 0: return .company
        case 1: return .site
        case 2: return .object
        default: return .area
        }
    }
}

/// The hierarchy levels of the design reference, with the emoji, tile fill and
/// name weight it gives each one.
private enum TechnicalPlaceLevel {
    case company, site, object, area, costGroup, system, equipment, unassigned

    var emoji: String {
        switch self {
        case .company: "🏢"
        case .site: "📍"
        case .object: "🏗️"
        case .area: "🗺️"
        case .costGroup: "📂"
        case .system: "⚙️"
        case .equipment: "🏷️"
        case .unassigned: "🗂️"
        }
    }

    var tile: Color {
        switch self {
        case .system: FacilityTheme.accentSoft
        case .costGroup, .equipment: FacilityTheme.purpleSoft
        case .company, .site, .object, .area, .unassigned: FacilityTheme.neutralSoft
        }
    }

    /// The reference tree sets the structural levels in bold and leaves the
    /// cost groups, systems and equipment at regular weight.
    var nameWeight: Font.Weight {
        switch self {
        case .company, .site, .object: .bold
        case .area, .unassigned: .semibold
        case .costGroup, .system, .equipment: .regular
        }
    }

    /// Spoken in place of the emoji, which VoiceOver would otherwise read out
    /// by its Unicode name.
    var nameKey: String {
        switch self {
        case .company: "places.level.company"
        case .site: "places.level.site"
        case .object: "places.level.object"
        case .area: "places.level.area"
        case .costGroup: "places.level.costGroup"
        case .system: "places.level.system"
        case .equipment: "places.badge.equipment"
        case .unassigned: "places.unassigned"
        }
    }
}

private struct TechnicalObjectRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.black.opacity(0.04) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

private struct ObjectBadge: View {
    let text: String; let color: Color
    init(_ text: String, color: Color) { self.text = text; self.color = color }
    var body: some View {
        Text(text).font(.caption.weight(.bold)).foregroundStyle(color).padding(.horizontal, 9).padding(.vertical, 5)
            .background(color.opacity(0.1), in: Capsule()).lineLimit(1)
    }
}

private struct TechnicalObjectDetailView: View {
    @Bindable var model: TechnicalPlacesViewModel
    let detail: TechnicalObjectDetail
    let offlineWorkStore: OfflineWorkStore
    let photoCount: Int
    let openPhotos: () -> Void
    let documentCount: Int
    let openDocuments: () -> Void
    let openNotification: (SAPNotificationSummary) -> Void
    let openDefect: (UUID) -> Void
    let createDefect: () -> Void
    let openMobileLadder: () -> Void
    let openSubdistribution: () -> Void
    let loadInstallOptions: () async -> TechnicalPlaceInstallOptions
    let loadCanReportDefect: () async -> Bool
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    /// Nil while the creation data is read; the install action waits for it
    /// rather than offering a form that may have nothing to choose.
    @State private var installOptions: TechnicalPlaceInstallOptions?
    /// Nil while the place's I1s are read: SAP creates a defect (I2) only
    /// under one of them.
    @State private var canReportDefect: Bool?
    /// Built when someone asks to see or print the code. Generating one is a
    /// few milliseconds now that it no longer goes through CoreImage.
    @State private var qrCode: UIImage?
    @State private var label: FormReportPDFArtifact?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button {
                    withAnimation(accessibilityReduceMotion ? nil : .smooth(duration: 0.24)) {
                        model.closeDetail()
                    }
                } label: { Label("places.detail.back", systemImage: "chevron.left") }
                    .buttonStyle(.plain).foregroundStyle(.blue).frame(minHeight: 44)
                Text(detail.object.displayName).font(.system(size: 30, weight: .bold, design: .rounded))
                Text(breadcrumbLabels.joined(separator: " › ")).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                if !detail.object.displayStatus.isEmpty { ObjectBadge(detail.object.displayStatus, color: FacilityTheme.accent) }
                // Photos and documents share a row until the window is too
                // narrow for both, then stack.
                FacilityColumnsLayout(columnCounts: [2, 1], minimumColumnWidth: 280, spacing: 12) {
                    PhotoWorkspaceButton(count: photoCount, action: openPhotos)
                    DocumentWorkspaceButton(count: documentCount, action: openDocuments)
                }
                // The equipment fields keep their focus when the side cards
                // move under them as the window or sidebar changes width.
                FacilitySideColumnLayout(sideWidth: 405, minimumMainWidth: 420, spacing: 16) {
                    VStack(spacing: 16) {
                        primaryCard
                        identifierSegmentsCard
                    }
                    sideCards
                }
            }.facilityPageContent()
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: detail.object.id) { _, _ in qrCode = nil }
        .task(id: detail.object.id) {
            guard case .functionalLocation = detail else { return }
            installOptions = nil
            canReportDefect = nil
            async let canReport = loadCanReportDefect()
            let options = await loadInstallOptions()
            let reportable = await canReport
            guard !Task.isCancelled else { return }
            installOptions = options
            canReportDefect = reportable
        }
        .fullScreenCover(item: $label) { label in
            FormReportPDFPreview(report: label, titleKey: "places.qr.label.title")
        }
    }

    private var qrPayload: String? { TechnicalObjectQRCode.payload(for: detail.object) }

    private var identifierSegments: [TechnicalObjectIdentifierSegment] {
        TechnicalObjectIdentifierSegment.segments(
            of: detail.object.reference.objectID,
            breadcrumbs: breadcrumbs
        )
    }

    /// Left out when the identifier has no separators to split on — the card
    /// would only repeat the identifier from the master data above it.
    @ViewBuilder private var identifierSegmentsCard: some View {
        let segments = identifierSegments
        if !segments.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("places.detail.segments").font(.headline)
                ForEach(segments) { segment in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(verbatim: "\(segment.position)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                            .frame(width: 18, alignment: .trailing)
                        Text(segment.value)
                            .font(.subheadline.monospaced().weight(.bold))
                            .foregroundStyle(FacilityTheme.ink)
                        if let objectName = segment.objectName {
                            Text(verbatim: "· \(objectName)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 30)
                    .accessibilityElement(children: .combine)
                    if segment.position < segments.count { Divider() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .facilityCard()
        }
    }

    private func prepareCode() {
        guard let qrPayload else { return }
        qrCode = QRCodeImageRenderer.image(for: qrPayload)
    }

    private func shareLabel() {
        guard let qrPayload,
              let data = TechnicalObjectQRCode.labelPDF(for: detail.object, payload: qrPayload)
        else {
            model.performUnavailableAction("places.qr.unavailable")
            return
        }
        label = FormReportPDFArtifact(
            id: detail.object.id,
            fileName: TechnicalObjectQRCode.labelFileName(for: detail.object),
            data: data
        )
    }

    private var breadcrumbs: [TechnicalObjectNode] {
        switch detail { case let .functionalLocation(v): v.breadcrumbs; case let .equipment(v): v.breadcrumbs }
    }
    private var breadcrumbLabels: [String] {
        let city = detail.object.cityAndLocationDisplay
        return (city.isEmpty ? [] : [city]) + breadcrumbs.map(\.displayName)
    }
    private var notifications: [SAPNotificationSummary] {
        switch detail { case let .functionalLocation(v): v.linkedNotifications; case let .equipment(v): v.linkedNotifications }
    }
    @ViewBuilder private var primaryCard: some View {
        switch detail { case let .functionalLocation(v): FunctionalLocationCard(detail: v); case .equipment: EquipmentEditCard(model: model) }
    }
    private var sideCards: some View {
        VStack(spacing: 16) {
            VStack(spacing: 14) {
                Text("places.detail.identification").font(.headline)
                if let qrCode {
                    // Nearest-neighbour keeps the modules square when the
                    // bitmap is scaled down to the card.
                    Image(uiImage: qrCode)
                        .interpolation(.none)
                        .antialiased(false)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 176, height: 176)
                        .padding(8)
                        .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityLabel("places.qr.code")
                } else if qrPayload != nil {
                    Button(action: prepareCode) { 
                        VStack(spacing: 10) {
                            Image(systemName: "qrcode")
                                .font(.system(size: 76))
                                .foregroundStyle(.tertiary)
                            Text("places.qr.show")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(FacilityTheme.accent)
                        }
                        .frame(width: 176, height: 176)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    // No identifier to encode.
                    Image(systemName: "qrcode")
                        .font(.system(size: 94))
                        .foregroundStyle(.tertiary)
                        .frame(width: 176, height: 176)
                }
                Text(detail.object.reference.objectID).font(.caption.monospaced()).foregroundStyle(.secondary)
                HStack {
                    Button(action: shareLabel) { Label("places.qr", systemImage: "printer") }
                        .buttonStyle(.borderedProminent)
                        .disabled(qrPayload == nil)
                    Button { model.performUnavailableAction("places.rfid.unavailable") } label: { Text("RFID") }.buttonStyle(.bordered)
                }
            }.frame(maxWidth: .infinity).facilityCard()
            linkedProcessesCard
            actionsCard
        }
    }

    /// Everything currently open at this object: the notifications SAP has
    /// linked to it and the fault notifications the technician has recorded
    /// locally but not yet synchronized.
    private var linkedProcesses: [LinkedProcessEntry] {
        let reference = detail.object.reference
        let sapEntries = notifications.map { note in
            LinkedProcessEntry(
                id: "notification-\(note.id)",
                symbol: "list.bullet.clipboard",
                tint: FacilityTheme.blue,
                title: note.title.isEmpty ? note.id : note.title,
                meta: [note.id, note.displayDateRange, note.displayStatus]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · "),
                status: nil,
                open: { openNotification(note) }
            )
        }
        let localEntries = offlineWorkStore.defectItems.compactMap { item -> LinkedProcessEntry? in
            guard let defect = item.payload.defect, defect.technicalObject == reference else { return nil }
            return LinkedProcessEntry(
                id: "defect-\(item.id.uuidString)",
                symbol: "exclamationmark.triangle.fill",
                tint: FacilityTheme.red,
                title: defect.shortText.isEmpty ? defect.technicalObjectName : defect.shortText,
                meta: String(localized: String.LocalizationValue(defect.priority.titleKey), bundle: .appLanguage),
                status: item.status,
                open: { openDefect(item.id) }
            )
        }
        return sapEntries + localEntries
    }

    private static let linkedProcessesMaxHeight: CGFloat = 330

    private var linkedProcessesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("places.detail.linked").font(.headline)
            let entries = linkedProcesses
            if entries.isEmpty {
                Text("places.detail.linked.empty")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // Grows with its rows up to about five, then scrolls, so a
                // busy object does not push the actions card off the page.
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            LinkedProcessRow(entry: entry)
                            if index < entries.count - 1 { Divider() }
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: Self.linkedProcessesMaxHeight)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .facilityCard()
    }

    /// The actions the design reference offers on a technical place.
    ///
    /// "Equipment einbauen" is the TFM5 / TFM7 creation forms: both close as an
    /// I1 notification carrying a `NEU-` equipment number for `STRNO`, which is
    /// exactly what installing equipment at this place means. It offers only
    /// the forms SAP has a context for at this place — both as a menu, one as
    /// a direct button, none as a disabled button — and says why the others
    /// are missing, so an absent option never reads as an app error.
    /// Creating a subordinate place (IL01) has no counterpart in either
    /// reference app and no confirmed SAP write contract, so it says so
    /// instead of pretending.
    @ViewBuilder private var actionsCard: some View {
        if case .functionalLocation = detail {
            VStack(alignment: .leading, spacing: 12) {
                Text("places.detail.actions").font(.headline)
                VStack(spacing: 9) {
                    Button(action: createDefect) {
                        HStack(spacing: 8) {
                            if canReportDefect == nil { ProgressView().controlSize(.small) }
                            actionButtonLabel("places.detail.action.defect")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(canReportDefect != true)
                    actionButton("places.detail.action.childPlace") {
                        model.performUnavailableAction("places.detail.action.childPlace.unavailable")
                    }
                    installEquipmentAction
                }
                if canReportDefect == false {
                    TechnicalPlaceInstallNotice(
                        symbol: "exclamationmark.bubble",
                        title: String(localized: "places.detail.action.defect.unavailable", bundle: .appLanguage),
                        message: String(localized: "manual.defect.object.noParent", bundle: .appLanguage)
                    )
                    .transition(.opacity)
                }
                installNotes
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .facilityCard()
            .animation(accessibilityReduceMotion ? nil : .smooth(duration: 0.2), value: installOptions)
            .animation(accessibilityReduceMotion ? nil : .smooth(duration: 0.2), value: canReportDefect)
        }
    }

    @ViewBuilder private var installEquipmentAction: some View {
        let ladder = installOptions?.mobileLadder.isAvailable == true
        let subdistribution = installOptions?.subdistribution.isAvailable == true
        if ladder && subdistribution {
            Menu {
                Button(action: openMobileLadder) {
                    Label("places.new.mobileLadder", systemImage: "figure.climbing")
                }
                Button(action: openSubdistribution) {
                    Label("places.new.subdistribution", systemImage: "bolt.square")
                }
            } label: {
                actionButtonLabel("places.detail.action.installEquipment")
            }
            .buttonStyle(.bordered)
            .menuOrder(.fixed)
        } else if ladder {
            actionButton("places.new.mobileLadder", action: openMobileLadder)
        } else if subdistribution {
            actionButton("places.new.subdistribution", action: openSubdistribution)
        } else {
            Button {} label: {
                HStack(spacing: 8) {
                    if installOptions == nil { ProgressView().controlSize(.small) }
                    actionButtonLabel("places.detail.action.installEquipment")
                }
            }
            .buttonStyle(.bordered)
            .disabled(true)
        }
    }

    /// One framed notice per form that cannot be used here, with SAP's
    /// reason, in the app's notice style. A place without a business entity
    /// gets a single notice, since neither form can address it.
    @ViewBuilder private var installNotes: some View {
        if let installOptions {
            VStack(spacing: 8) {
                if installOptions.mobileLadder == .noBusinessEntity {
                    TechnicalPlaceInstallNotice(
                        symbol: "shippingbox",
                        title: String(localized: "places.install.unavailable", bundle: .appLanguage),
                        message: String(localized: "places.install.noBusinessEntity", bundle: .appLanguage)
                    )
                } else {
                    if let message = Self.installReason(installOptions.mobileLadder, form: .mobileLadder) {
                        TechnicalPlaceInstallNotice(
                            symbol: "figure.climbing",
                            title: String(localized: "places.install.mobileLadder.unavailable", bundle: .appLanguage),
                            message: message
                        )
                    }
                    if let message = Self.installReason(installOptions.subdistribution, form: .subdistribution) {
                        TechnicalPlaceInstallNotice(
                            symbol: "bolt.square",
                            title: String(localized: "places.install.subdistribution.unavailable", bundle: .appLanguage),
                            message: message
                        )
                    }
                }
            }
            .transition(.opacity)
        }
    }

    private enum InstallForm { case mobileLadder, subdistribution }

    private static func installReason(
        _ availability: TechnicalPlaceInstallAvailability,
        form: InstallForm
    ) -> String? {
        switch (availability, form) {
        case (.available, _):
            nil
        case let (.noContext(trade), .mobileLadder):
            String(localized: "places.install.mobileLadder.noContext \(trade)", bundle: .appLanguage)
        case (.noContext, .subdistribution):
            String(localized: "places.install.subdistribution.noContext", bundle: .appLanguage)
        case (.noData, _):
            String(localized: "places.install.noData", bundle: .appLanguage)
        case (.noBusinessEntity, _):
            String(localized: "places.install.noBusinessEntity", bundle: .appLanguage)
        }
    }

    private func actionButton(_ key: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) { actionButtonLabel(key) }
            .buttonStyle(.bordered)
    }

    private func actionButtonLabel(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 44)
    }
}

/// Why a form of "Equipment einbauen" is missing at this place, styled like
/// the app's other notices (`SafetyFormNoBuildingsNotice`) so it reads as
/// information from SAP rather than an app error.
private struct TechnicalPlaceInstallNotice: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FacilityTheme.orange)
                .frame(width: 34, height: 34)
                .background(FacilityTheme.orange.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FacilityTheme.ink)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FacilityTheme.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(FacilityTheme.orange.opacity(0.25))
        }
        .accessibilityElement(children: .combine)
    }
}

private struct LinkedProcessEntry: Identifiable {
    let id: String
    let symbol: String
    let tint: Color
    let title: String
    let meta: String
    /// Set for locally recorded work, so a row that has not reached SAP yet
    /// is never read as an open SAP process.
    let status: OfflineWorkStatus?
    let open: () -> Void
}

private struct LinkedProcessRow: View {
    let entry: LinkedProcessEntry

    var body: some View {
        Button(action: entry.open) {
            HStack(spacing: 12) {
                Image(systemName: entry.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(entry.tint)
                    .frame(width: 36, height: 36)
                    .background(entry.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FacilityTheme.ink)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    if !entry.meta.isEmpty {
                        Text(entry.meta)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                if let status = entry.status { OfflineStatusPill(status: status) }
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(TechnicalObjectRowButtonStyle())
        .accessibilityElement(children: .combine)
    }
}

private struct FunctionalLocationCard: View {
    let detail: FunctionalLocationDetail
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("places.detail.masterData").font(.headline)
            DetailGridLine("places.detail.technicalPlace", detail.object.reference.objectID)
            DetailGridLine("places.detail.designation", detail.object.name)
            DetailGridLine("places.detail.city", detail.object.cityAndLocationDisplay)
            DetailGridLine("places.detail.parent", detail.object.parent?.objectID ?? "—")
            DetailGridLine("places.detail.hierarchyLevel", detail.object.hierarchyLevel)
            DetailGridLine("places.detail.category", detail.object.category)
            DetailGridLine("places.detail.structure", detail.object.structureIndicator)
            DetailGridLine("places.detail.din", detail.object.dinGroup.map { "KG \($0)" } ?? "—")
            DetailGridLine("places.detail.status", detail.object.displayStatus)
            DetailGridLine("places.detail.equipment", "\(detail.object.directEquipmentCount)")
            DetailGridLine("places.detail.identificationText", detail.object.reference.objectID)
            if !detail.children.isEmpty {
                Divider()
                Text("places.detail.children").font(.subheadline.weight(.bold))
                ForEach(detail.children) { child in
                    HStack {
                        Image(systemName: child.reference.kind == .equipment ? "gearshape" : "building.2")
                        VStack(alignment: .leading) {
                            Text(child.displayName).font(.subheadline.weight(.semibold))
                            Text(child.reference.objectID).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }.accessibilityElement(children: .combine)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).facilityCard()
    }
}

private struct EquipmentEditCard: View {
    @Bindable var model: TechnicalPlacesViewModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("places.detail.masterData").font(.headline)
            immutable("places.detail.equipmentNumber", model.equipmentDraft?.equipmentID ?? "")
            immutable("places.detail.technicalPlace", model.equipmentDraft?.functionalLocationID ?? "")
            immutable("places.detail.city", model.equipmentDraft?.cityAndLocationDisplay ?? "")
            edit("places.detail.designation", \.designation)
            HStack(alignment: .top, spacing: 14) { edit("places.detail.manufacturer", \.manufacturer); edit("places.detail.type", \.modelType) }
            edit("places.detail.serial", \.serialNumber)
            VStack(alignment: .leading, spacing: 6) {
                Text("places.detail.din").fieldLabel()
                Picker("places.detail.din", selection: dinBinding) {
                    Text("common.none").tag(String?.none)
                    ForEach(TechnicalDIN276.supportedCodes, id: \.self) { Text("KG \($0)").tag(Optional($0)) }
                }.pickerStyle(.menu).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).fieldChrome()
            }
            Toggle("places.detail.nextInspection.enabled", isOn: hasDateBinding)
            if model.equipmentDraft?.hasNextInspectionDate == true {
                DatePicker("places.detail.nextInspection", selection: dateBinding, displayedComponents: .date)
                    .transition(.opacity)
            }
            Divider()
            HStack {
                if model.saveState == .saving { ProgressView().transition(.opacity) }
                if model.saveState == .savedPending { Label("places.save.pending", systemImage: "clock.fill").foregroundStyle(.orange).transition(.opacity) }
                if model.saveState == .conflict { Label("places.save.conflict", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).transition(.opacity) }
                if model.saveState == .failed { Text("places.save.failed").foregroundStyle(.red).transition(.opacity) }
                Spacer()
                Button("places.save") { Task { await model.saveEquipment() } }.buttonStyle(.borderedProminent).disabled(model.saveState == .saving)
            }
            .animation(accessibilityReduceMotion ? nil : .smooth(duration: 0.2), value: model.saveState)
        }
        .animation(accessibilityReduceMotion ? nil : .smooth(duration: 0.22), value: model.equipmentDraft?.hasNextInspectionDate)
        .frame(maxWidth: .infinity, alignment: .leading)
        .facilityCard()
    }

    private func immutable(_ key: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(key).fieldLabel(); Text(value.isEmpty ? "—" : value).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 12).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
    }
    private func edit(_ key: LocalizedStringKey, _ path: WritableKeyPath<EquipmentEditDraft, String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(key).fieldLabel()
            TextField(key, text: Binding(get: { model.equipmentDraft?[keyPath: path] ?? "" }, set: { model.equipmentDraft?[keyPath: path] = $0 }))
                .frame(minHeight: 44).padding(.horizontal, 12).fieldChrome()
        }.frame(maxWidth: .infinity)
    }
    private var dinBinding: Binding<String?> { Binding(get: { model.equipmentDraft?.dinGroup }, set: { model.equipmentDraft?.dinGroup = $0 }) }
    private var hasDateBinding: Binding<Bool> { Binding(get: { model.equipmentDraft?.hasNextInspectionDate ?? false }, set: { model.equipmentDraft?.hasNextInspectionDate = $0 }) }
    private var dateBinding: Binding<Date> { Binding(get: { model.equipmentDraft?.nextInspectionDate ?? Date() }, set: { model.equipmentDraft?.nextInspectionDate = $0 }) }
}

private struct DetailGridLine: View {
    let key: LocalizedStringKey; let value: String
    init(_ key: LocalizedStringKey, _ value: String) { self.key = key; self.value = value }
    var body: some View {
        HStack(alignment: .top) {
            Text(key).fieldLabel().frame(maxWidth: 190, alignment: .leading)
            Text(value.isEmpty ? "—" : value).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private extension View {
    func fieldChrome() -> some View { background(.white, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2))) }
}
private extension Text {
    func fieldLabel() -> some View { font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
}
