import SwiftUI

struct TechnicalPlacesView: View {
    let demo: FacilityDemoViewModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var photoWorkspaceScope: LocalPhotoScope?

    var body: some View {
        @Bindable var model = demo.technicalPlacesStore
        ZStack {
            if case .createMobileLadder = demo.technicalPlacesRoute {
                MobileLadderCreationView(demo: demo, itemID: nil, close: demo.closeMobileLadder)
                    .transition(PhotoWorkspaceMotion.destination)
            } else if case let .mobileLadderDraft(itemID) = demo.technicalPlacesRoute {
                MobileLadderCreationView(demo: demo, itemID: itemID, close: demo.closeMobileLadder)
                    .transition(PhotoWorkspaceMotion.destination)
            } else if case .createSubdistribution = demo.technicalPlacesRoute {
                SubdistributionCreationView(demo: demo, itemID: nil, close: demo.closeSubdistribution)
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
            } else {
                Group {
                    if let detail = model.selectedDetail {
                        TechnicalObjectDetailView(
                            model: model,
                            detail: detail,
                            photoCount: photoCount(for: detail),
                            openPhotos: { photoWorkspaceScope = photoScope(for: detail) }
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
            displayTitle: String(localized: "photos.workspace.title"),
            displaySubtitle: detail.object.displayName
        )
    }

    private func photoCount(for detail: TechnicalObjectDetail) -> Int {
        demo.offlineWorkStore.photoCollection(for: photoScope(for: detail))?
            .payload.photoCollection?.attachments.count ?? 0
    }

    private func hierarchy(_ model: TechnicalPlacesViewModel) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 18) {
                    PageHeader("places.title", subtitle: "places.subtitle")
                    Spacer()
                    Menu {
                        Button { demo.openMobileLadder() } label: {
                            Label("places.new.mobileLadder", systemImage: "figure.climbing")
                        }
                        Button { demo.openSubdistribution() } label: {
                            Label("places.new.subdistribution", systemImage: "bolt.square")
                        }
                    } label: {
                        Label("places.new", systemImage: "plus")
                            .font(.subheadline.weight(.bold)).frame(minWidth: 88, minHeight: 48)
                    }.buttonStyle(.bordered)
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
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .animation(accessibilityReduceMotion ? nil : .smooth(duration: 0.18), value: model.query.isEmpty)

                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        DINChip(title: String(localized: "places.filter.all"), count: model.totalCount, selected: model.selectedDINGroup == nil) {
                            Task { await model.selectDIN(nil) }
                        }
                        ForEach(model.dinCounts) { item in
                            DINChip(title: "KG \(item.code)", count: item.count, selected: model.selectedDINGroup == item.code) {
                                Task { await model.selectDIN(item.code) }
                            }
                        }
                    }
                    .animation(accessibilityReduceMotion ? nil : .smooth(duration: 0.2), value: model.selectedDINGroup)
                }.scrollIndicators(.hidden)
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
            }.facilityPageContent()
        }.scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder private func hierarchyContent(_ model: TechnicalPlacesViewModel) -> some View {
        switch model.state {
        case .idle, .loading:
            ProgressView("places.loading").frame(maxWidth: .infinity, minHeight: 260)
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
            LazyVStack(spacing: 0) {
                ForEach(model.visibleRows) { row in
                    TechnicalObjectRow(
                        row: row,
                        displayName: model.displayName(for: row.node),
                        pendingStatus: model.pendingEdit(for: row.node)?.status,
                        isExpanded: model.expanded.contains(row.node.reference)
                    ) {
                        Task { await model.toggle(row.node) }
                    } open: { Task { await model.open(row.node.reference) } }
                    .transition(.opacity)

                    if model.expanded.contains(row.node.reference), model.hasMoreChildren(of: row.node.reference) {
                        Button("places.loadMore") { Task { await model.loadMoreChildren(of: row.node.reference) } }
                            .font(.caption.weight(.semibold)).padding(.leading, CGFloat(row.depth + 1) * 22 + 54).frame(minHeight: 44)
                            .transition(.opacity)
                    }
                    Divider().padding(.leading, CGFloat(row.depth) * 22 + 54)
                }
                if model.hasMoreRoots {
                    Button("places.loadMore") { Task { await model.loadMoreRoots() } }
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48)
                        .transition(.opacity)
                }
            }
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .transition(.opacity)
        }
    }

    private func unavailable(_ title: LocalizedStringKey, _ subtitle: LocalizedStringKey, _ symbol: String) -> some View {
        ContentUnavailableView { Label(title, systemImage: symbol) } description: { Text(subtitle) }
            .frame(maxWidth: .infinity, minHeight: 260)
    }
}

private struct DINChip: View {
    let title: String; let count: Int; let selected: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text("\(title) (\(count))").font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? .white : .secondary).padding(.horizontal, 13).frame(minHeight: 36)
                .background(selected ? FacilityTheme.accent : Color.white, in: Capsule())
                .overlay(Capsule().stroke(selected ? .clear : Color.secondary.opacity(0.22)))
        }
        .buttonStyle(.plain)
        .animation(.smooth(duration: 0.2), value: selected)
    }
}

private struct TechnicalObjectRow: View {
    let row: TechnicalObjectVisibleRow; let displayName: String; let pendingStatus: OfflineWorkStatus?; let isExpanded: Bool; let toggle: () -> Void; let open: () -> Void
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: CGFloat(row.depth) * 22)
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
                Color.clear.frame(width: 30, height: 44)
            }
            Button(action: open) {
                HStack(spacing: 10) {
                    Image(systemName: rowIcon)
                        .foregroundStyle(row.node.reference.kind == .equipment ? FacilityTheme.blue : FacilityTheme.accent).frame(width: 28)
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(row.node.isUnassignedGroup ? String(localized: "places.unassigned") : displayName)
                            .font(.subheadline.weight(row.node.hasChildren || row.node.isSynthetic ? .bold : .regular))
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
                    if let din = row.node.dinGroup { ObjectBadge("KG \(din)", color: .indigo) }
                    if row.node.isCityGroup { ObjectBadge(String(localized: "places.badge.city"), color: FacilityTheme.accent) }
                    if row.node.directEquipmentCount > 0 { ObjectBadge("\(row.node.directEquipmentCount) EQ", color: .gray) }
                    if pendingStatus == .conflict { ObjectBadge(String(localized: "places.badge.conflict"), color: .red) }
                    else if pendingStatus != nil { ObjectBadge(String(localized: "places.badge.pending"), color: .orange) }
                    if row.node.reference.kind == .equipment {
                        ObjectBadge(String(localized: "places.badge.equipment"), color: .blue)
                    }
                    if !row.node.isSynthetic {
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
        .frame(minHeight: 46)
        .accessibilityElement(children: .combine)
    }

    private var rowIcon: String {
        if row.node.isCityGroup { return "mappin.and.ellipse" }
        if row.node.isUnassignedGroup { return "tray.full.fill" }
        if row.node.reference.kind == .equipment { return "shippingbox.fill" }
        if row.node.dinGroup != nil && row.node.hasChildren { return "folder.fill" }
        if row.node.dinGroup != nil { return "gearshape.fill" }
        return row.depth < 2 ? "building.2.fill" : "building.fill"
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
    let photoCount: Int
    let openPhotos: () -> Void
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

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
                PhotoWorkspaceButton(count: photoCount, action: openPhotos)
                // The equipment fields keep their focus when the side cards
                // move under them as the window or sidebar changes width.
                FacilitySideColumnLayout(sideWidth: 405, minimumMainWidth: 420, spacing: 16) {
                    primaryCard
                    sideCards
                }
            }.facilityPageContent()
        }.scrollDismissesKeyboard(.interactively)
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
                Image(systemName: "qrcode").font(.system(size: 94))
                Text(detail.object.reference.objectID).font(.caption.monospaced()).foregroundStyle(.secondary)
                HStack {
                    Button { model.performUnavailableAction("places.qr.unavailable") } label: { Label("places.qr", systemImage: "printer") }.buttonStyle(.borderedProminent)
                    Button { model.performUnavailableAction("places.rfid.unavailable") } label: { Text("RFID") }.buttonStyle(.bordered)
                }
            }.frame(maxWidth: .infinity).facilityCard()
            VStack(alignment: .leading, spacing: 12) {
                Text("places.detail.linked").font(.headline)
                if notifications.isEmpty { Text("places.detail.linked.empty").foregroundStyle(.secondary) }
                else { ForEach(notifications) { note in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(note.title.isEmpty ? note.id : note.title).font(.subheadline.weight(.semibold))
                        Text(note.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                } }
            }.facilityCard()
        }
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
