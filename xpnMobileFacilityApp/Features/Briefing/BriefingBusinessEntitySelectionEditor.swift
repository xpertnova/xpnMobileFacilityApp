import SwiftUI

struct BriefingBusinessEntityItem: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let code: String?
    let buildingCount: Int

    init(id: String, title: String, code: String? = nil, buildingCount: Int = 0) {
        self.id = id
        self.title = title
        self.code = code
        self.buildingCount = buildingCount
    }
}

/// SAP-backed business-entity value help. It intentionally reuses the same
/// frame and overlay as partner-company selection so briefing value helps have
/// one consistent iPad interaction.
struct BriefingBusinessEntitySelectionEditor: View {
    let entities: [BriefingBusinessEntityItem]
    let initialBusinessEntityID: String?
    let onCancel: () -> Void
    let onSelect: (String) -> Void

    @State private var selectedBusinessEntityID: String?
    @State private var searchText = ""

    init(
        entities: [BriefingBusinessEntityItem],
        selectedBusinessEntityID: String?,
        onCancel: @escaping () -> Void,
        onSelect: @escaping (String) -> Void
    ) {
        self.entities = entities
        self.initialBusinessEntityID = selectedBusinessEntityID
        self.onCancel = onCancel
        self.onSelect = onSelect
        _selectedBusinessEntityID = State(initialValue: selectedBusinessEntityID)
    }

    init(
        viewModel: BriefingWorkflowViewModel,
        onDismiss: @escaping () -> Void
    ) {
        let items = viewModel.businessEntities.map { entity in
            let count = Set(
                viewModel.source.contexts
                    .filter { $0.businessEntityID == entity.businessEntityID }
                    .map(\.buildingCode)
            ).count
            return BriefingBusinessEntityItem(
                id: entity.businessEntityID,
                title: entity.businessEntityTitle,
                code: entity.businessEntityTitle != entity.businessEntityID ? entity.businessEntityID : nil,
                buildingCount: count
            )
        }
        self.init(
            entities: items,
            selectedBusinessEntityID: viewModel.selectedBusinessEntityID,
            onCancel: onDismiss,
            onSelect: { selectedID in
                viewModel.selectBusinessEntity(selectedID)
                onDismiss()
            }
        )
    }

    var body: some View {
        BriefingPartnerSelectionFrame(
            title: "briefing.businessEntity.dialog.title",
            confirmationTitle: "safetyInstrucForm.addPartnerCompany.dialog.title.add",
            isConfirmationDisabled: selectedBusinessEntityID == nil,
            onCancel: onCancel,
            onConfirm: confirmSelection
        ) {
            VStack(alignment: .leading, spacing: 16) {
                searchField
                entityTable
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            selectedBusinessEntityID = initialBusinessEntityID
            searchText = ""
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("briefing.businessEntity.search", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(FacilityTheme.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.black.opacity(0.10))
        }
    }

    private var entityTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text("briefing.businessEntity.column")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("briefing.buildings.column")
                    .frame(width: 150, alignment: .leading)
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .frame(minHeight: 48)
            .background(FacilityTheme.canvas)

            Divider()

            if filteredEntities.isEmpty {
                ContentUnavailableView(
                    "briefing.businessEntity.empty.title",
                    systemImage: "building.2",
                    description: Text("briefing.businessEntity.empty.message")
                )
                .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredEntities) { entity in
                            Button {
                                selectedBusinessEntityID = entity.id
                            } label: {
                                HStack(spacing: 16) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(entity.title)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(FacilityTheme.ink)
                                        if let code = entity.code, !code.isEmpty, code != entity.title {
                                            Text(code)
                                                .font(.caption.monospaced())
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    Text("\(entity.buildingCount)")
                                        .font(.body.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 150, alignment: .leading)

                                    Image(systemName: selectedBusinessEntityID == entity.id ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(selectedBusinessEntityID == entity.id ? FacilityTheme.accent : .secondary)
                                        .frame(width: 32)
                                }
                                .padding(.horizontal, 18)
                                .frame(minHeight: 62)
                                .background(
                                    selectedBusinessEntityID == entity.id
                                        ? FacilityTheme.accent.opacity(0.09)
                                        : FacilityTheme.surface
                                )
                            }
                            .buttonStyle(.plain)

                            Divider().padding(.leading, 18)
                        }
                    }
                }
            }
        }
        .background(FacilityTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.10))
        }
    }

    private var filteredEntities: [BriefingBusinessEntityItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entities }
        return entities.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || ($0.code?.localizedCaseInsensitiveContains(query) ?? false)
                || $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    private func confirmSelection() {
        guard let selectedBusinessEntityID else { return }
        onSelect(selectedBusinessEntityID)
    }
}
