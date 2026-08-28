import SwiftUI

struct TechnicalPlacesView: View {
    let demo: FacilityDemoViewModel
    @State private var query = ""

    private var places: [TechnicalPlace] {
        guard !query.isEmpty else { return demo.technicalPlaces }
        return demo.technicalPlaces.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.code.localizedCaseInsensitiveContains(query) ||
            $0.detail.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader("places.title", subtitle: "places.subtitle")
                TextField("places.search", text: $query)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 13)
                    .frame(maxWidth: 430, minHeight: 42)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack(alignment: .top, spacing: 18) {
                    placeList
                    placeDetail
                }
            }
            .padding(28)
            .frame(maxWidth: 1280, alignment: .leading)
        }
    }

    private var placeList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("places.tree")
                .font(.subheadline.weight(.bold))
                .padding(18)
            Divider()
            ForEach(places) { place in
                Button {
                    demo.selectedTechnicalPlaceID = place.id
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(FacilityTheme.accent)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(place.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(FacilityTheme.ink)
                            Text(place.code)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(place.equipmentCount)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(FacilityTheme.accent)
                    }
                    .padding(15)
                    .background(demo.selectedTechnicalPlaceID == place.id ? FacilityTheme.accentSoft.opacity(0.65) : .clear)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 16)
            }
        }
        .frame(minWidth: 370, maxWidth: .infinity, alignment: .leading)
        .facilityCard(padding: 0)
    }

    @ViewBuilder
    private var placeDetail: some View {
        if let place = demo.selectedTechnicalPlace {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "building.2.fill")
                    .font(.title2)
                    .foregroundStyle(FacilityTheme.accent)
                    .frame(width: 50, height: 50)
                    .background(FacilityTheme.accentSoft, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                Text(place.title)
                    .font(.title3.weight(.bold))
                Text(place.code)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Divider()
                DetailLine(key: "places.detail.category", value: place.detail)
                DetailLine(key: "places.detail.equipment", value: "\(place.equipmentCount)")
                DetailLine(key: "places.detail.mode", value: String(localized: "places.detail.mock"))
                Label("places.detail.hardware", systemImage: "wrench.and.screwdriver")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            .frame(width: 330, alignment: .leading)
            .facilityCard()
        } else {
            EmptyDemoState(symbol: "square.split.2x2", titleKey: "places.empty.title", subtitleKey: "places.empty.subtitle")
                .frame(width: 330)
        }
    }
}

private struct DetailLine: View {
    let key: String
    let value: String

    var body: some View {
        HStack {
            Text(LocalizedStringKey(key))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
    }
}
