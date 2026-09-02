import SwiftUI

/// SAP-backed business-entity value help. It intentionally reuses the same
/// frame and overlay as partner-company selection so briefing value helps have
/// one consistent iPad interaction.
struct BriefingBusinessEntitySelectionEditor: View {
    let viewModel: BriefingWorkflowViewModel
    let onDismiss: () -> Void

    @State private var selectedBusinessEntityID: String?
    @State private var searchText = ""

    init(
        viewModel: BriefingWorkflowViewModel,
        onDismiss: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        _selectedBusinessEntityID = State(initialValue: viewModel.selectedBusinessEntityID)
    }

    var body: some View {
        BriefingPartnerSelectionFrame(
            title: "briefing.businessEntity.dialog.title",
            confirmationTitle: "safetyInstrucForm.addPartnerCompany.dialog.title.add",
            isConfirmationDisabled: selectedBusinessEntityID == nil,
            onCancel: onDismiss,
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
                                selectedBusinessEntityID = entity.businessEntityID
                            } label: {
                                HStack(spacing: 16) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(entity.businessEntityTitle)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(FacilityTheme.ink)
                                        if entity.businessEntityTitle != entity.businessEntityID {
                                            Text(entity.businessEntityID)
                                                .font(.caption.monospaced())
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    Text("\(buildingCount(for: entity.businessEntityID))")
                                        .font(.body.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 150, alignment: .leading)

                                    Image(systemName: selectedBusinessEntityID == entity.businessEntityID ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(selectedBusinessEntityID == entity.businessEntityID ? FacilityTheme.accent : .secondary)
                                        .frame(width: 32)
                                }
                                .padding(.horizontal, 18)
                                .frame(minHeight: 62)
                                .background(
                                    selectedBusinessEntityID == entity.businessEntityID
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

    private var filteredEntities: [BriefingWorkflowViewModel.Context] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return viewModel.businessEntities }
        return viewModel.businessEntities.filter {
            $0.businessEntityTitle.localizedCaseInsensitiveContains(query)
                || $0.businessEntityID.localizedCaseInsensitiveContains(query)
        }
    }

    private func buildingCount(for businessEntityID: String) -> Int {
        Set(
            viewModel.source.contexts
                .filter { $0.businessEntityID == businessEntityID }
                .map(\.buildingCode)
        ).count
    }

    private func confirmSelection() {
        guard let selectedBusinessEntityID else { return }
        viewModel.selectBusinessEntity(selectedBusinessEntityID)
        onDismiss()
    }
}
