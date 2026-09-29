import SwiftUI

/// The legacy `MeasurePoints` view: every measuring point of the Rundgang's
/// technical place with its last reading, and a new reading per point.
///
/// `onChangeReadingValue` only accepts a value that is not below the last
/// recorded one and has at most `DECIM` fraction digits; the same rules gate
/// Save here. Points left empty are not saved, as `_updateMeasurementDocument`
/// drops rows without `PARAMETER7`.
struct MeasuringPointsView: View {
    let functionalLocationID: String
    let points: [SAPMeasuringPoint]
    let isReadOnly: Bool
    let save: ([MeasuringPointReadingEntry]) async -> Bool
    let dismiss: () -> Void

    @State private var drafts: [String: MeasuringPointDraft]
    @State private var isSaving = false
    private let savedReadings: [String: MeasuringPointReadingEntry]

    init(
        functionalLocationID: String,
        points: [SAPMeasuringPoint],
        readings: [MeasuringPointReadingEntry],
        isReadOnly: Bool,
        save: @escaping ([MeasuringPointReadingEntry]) async -> Bool,
        dismiss: @escaping () -> Void
    ) {
        self.functionalLocationID = functionalLocationID
        self.points = points
        self.isReadOnly = isReadOnly
        self.save = save
        self.dismiss = dismiss
        let saved = Dictionary(readings.map { ($0.pointID, $0) }, uniquingKeysWith: { _, last in last })
        savedReadings = saved
        _drafts = State(initialValue: Dictionary(uniqueKeysWithValues: points.map { point in
            (point.pointID, MeasuringPointDraft(reading: saved[point.pointID]))
        }))
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.14)
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)

            VStack(alignment: .leading, spacing: 16) {
                header

                if isReadOnly {
                    Label("measuringPoints.readOnly", systemImage: "lock")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 0) {
                    ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                        MeasuringPointRow(
                            point: point,
                            draft: binding(for: point),
                            isReadOnly: isReadOnly
                        )
                        if index < points.count - 1 {
                            Divider()
                        }
                    }
                }
                .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.gray.opacity(0.24))
                }

                footer
            }
            .facilityDialogFrame(width: 760, padding: 22)
            .background(Color(white: 0.95), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.gray.opacity(0.24))
            }
            .shadow(color: Color.black.opacity(0.20), radius: 26, y: 12)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.body.weight(.bold))
                    .foregroundStyle(FacilityTheme.ink)
                    .frame(width: 44, height: 44)
                    .background(.white, in: Circle())
                    .overlay { Circle().stroke(.gray.opacity(0.28)) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("common.cancel"))

            VStack(alignment: .leading, spacing: 2) {
                Text("measuringPoints.title")
                    .font(.headline)
                    .foregroundStyle(FacilityTheme.ink)
                Text(verbatim: functionalLocationID)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if !isReadOnly {
            HStack(spacing: 12) {
                Spacer()
                Button("common.cancel", action: dismiss)
                    .buttonStyle(.bordered)
                Button {
                    Task { await saveReadings() }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("measuringPoints.save")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(FacilityTheme.accent)
                .disabled(!canSave)
            }
        }
    }

    private var entries: [MeasuringPointReadingEntry]? {
        var result: [MeasuringPointReadingEntry] = []
        for point in points {
            let draft = drafts[point.pointID] ?? MeasuringPointDraft(reading: nil)
            switch draft.state(for: point) {
            case .empty:
                continue
            case .invalid:
                return nil
            case let .valid(value):
                let text = String(draft.text.prefix(MeasuringPointReadingEntry.maximumTextLength))
                let saved = savedReadings[point.pointID]
                // Keep the time a reading was taken when it is saved again
                // unchanged; `onBeforeOpenEdit` stamps it when it is edited.
                let recordedAt = saved.flatMap { $0.value == value && $0.text == text ? $0.recordedAt : nil } ?? .now
                result.append(MeasuringPointReadingEntry(
                    client: point.client,
                    pointID: point.pointID,
                    unit: point.unit,
                    value: value,
                    text: text,
                    recordedAt: recordedAt
                ))
            }
        }
        return result
    }

    private var canSave: Bool {
        guard !isSaving, let entries else { return false }
        return entries != points.compactMap { savedReadings[$0.pointID] }
    }

    private func saveReadings() async {
        guard let entries else { return }
        isSaving = true
        defer { isSaving = false }
        if await save(entries) {
            dismiss()
        }
    }

    private func binding(for point: SAPMeasuringPoint) -> Binding<MeasuringPointDraft> {
        Binding(
            get: { drafts[point.pointID] ?? MeasuringPointDraft(reading: nil) },
            set: { drafts[point.pointID] = $0 }
        )
    }
}

/// What the technician typed for one point.
struct MeasuringPointDraft {
    enum State: Equatable {
        case empty
        case invalid(MeasuringPointValidationIssue)
        case valid(Decimal)
    }

    var valueText: String
    var text: String

    init(reading: MeasuringPointReadingEntry?) {
        valueText = reading.map { MeterReadingViewModel.displayString($0.value) } ?? ""
        text = reading?.text ?? ""
    }

    func state(for point: SAPMeasuringPoint) -> State {
        guard let value = MeterReadingViewModel.parseDecimal(valueText, locale: Locale(identifier: "de_DE")) else {
            return .empty
        }
        if let issue = point.validationIssue(for: value) {
            return .invalid(issue)
        }
        return .valid(value)
    }
}

private struct MeasuringPointRow: View {
    let point: SAPMeasuringPoint
    @Binding var draft: MeasuringPointDraft
    let isReadOnly: Bool

    var body: some View {
        FacilitySideColumnLayout(sideWidth: 260, minimumMainWidth: 260, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("measuringPoints.point \(point.displayNumber) \(point.position)")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(FacilityTheme.ink)
                if !point.description.isEmpty {
                    Text(verbatim: point.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                lastReading
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    MeterReadingNumberTextField(
                        text: $draft.valueText,
                        placeholder: String(localized: "measuringPoints.value.placeholder", bundle: .appLanguage),
                        maximumFractionDigits: point.decimals,
                        textAlignment: .right,
                        usesMonospacedDigits: true
                    )
                    Text(verbatim: point.unit)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .measuringPointField(isInvalid: issue != nil)

                if let issue {
                    Text(issueMessage(issue))
                        .font(.footnote)
                        .foregroundStyle(FacilityTheme.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                TextField("measuringPoints.text.placeholder", text: noteText)
                    .measuringPointField(isInvalid: false)
            }
            .disabled(isReadOnly)
        }
        .padding(16)
    }

    private var issue: MeasuringPointValidationIssue? {
        if case let .invalid(issue) = draft.state(for: point) { return issue }
        return nil
    }

    private var noteText: Binding<String> {
        Binding(
            get: { draft.text },
            set: { draft.text = String($0.prefix(MeasuringPointReadingEntry.maximumTextLength)) }
        )
    }

    @ViewBuilder
    private var lastReading: some View {
        if let reading = point.lastReading, let value = reading.value {
            let unit = reading.unit.isEmpty ? point.unit : reading.unit
            Text("measuringPoints.lastReading \(MeterReadingViewModel.displayString(value)) \(unit) \(Self.displayDate(reading.date))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            Text("measuringPoints.lastReading.none")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func issueMessage(_ issue: MeasuringPointValidationIssue) -> String {
        switch issue {
        case .belowLastReading:
            String(localized: "measuringPoints.issue.belowLastReading \(MeterReadingViewModel.displayString(point.minimumValue))", bundle: .appLanguage)
        case .tooManyDecimals:
            String(localized: "measuringPoints.issue.tooManyDecimals \(point.decimals)", bundle: .appLanguage)
        }
    }

    /// `IDATE` arrives as `yyyyMMdd` in the legacy history dialog; the ISO
    /// form the package uses for `ERDAT` is accepted as well.
    private static func displayDate(_ raw: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        for format in ["yyyyMMdd", "yyyy-MM-dd"] {
            parser.dateFormat = format
            if let date = parser.date(from: raw) {
                return date.formatted(Date.FormatStyle(date: .numeric, time: .omitted, timeZone: TimeZone(identifier: "UTC")!))
            }
        }
        return raw
    }
}

private extension View {
    func measuringPointField(isInvalid: Bool) -> some View {
        padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isInvalid ? FacilityTheme.red : .gray.opacity(0.32))
            }
    }
}
