#if DEBUG
import Observation
import SwiftUI

/// Sizes of what the generated records land in.
struct LoadTestStorageUsage: Equatable, Sendable {
    var photoByteCount: Int64 = 0
    var databaseByteCount: Int64 = 0
    var freeByteCount: Int64 = 0

    /// `FilePhotoAttachmentStore` and `SQLiteOfflineWorkRepository` keep
    /// their default locations to themselves; the names are repeated here.
    static func measure() -> Self {
        let manager = FileManager.default
        guard let support = try? manager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ) else { return Self() }

        var usage = Self()
        let photos = support.appendingPathComponent("ManualCapturePhotos", isDirectory: true)
        let files = (try? manager.contentsOfDirectory(at: photos, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        for file in files {
            usage.photoByteCount += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        let database = support.appendingPathComponent("offline-work.sqlite")
        for suffix in ["", "-wal"] {
            let attributes = try? manager.attributesOfItem(atPath: database.path + suffix)
            usage.databaseByteCount += (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        }
        let capacity = try? support.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        usage.freeByteCount = capacity?.volumeAvailableCapacityForImportantUsage ?? 0
        return usage
    }
}

@MainActor
@Observable
final class LoadTestPanelModel {
    struct Progress: Equatable {
        let done: Int
        let total: Int
    }

    /// Generated photos must leave this much of the device free.
    static let freeSpaceReserve: Int64 = 500_000_000

    private let seeder: LoadTestSeeder
    private let offlineWorkStore: OfflineWorkStore
    @ObservationIgnored private var task: Task<Void, Never>?

    var configuration = LoadTestConfiguration()
    private(set) var availability: LoadTestAvailability?
    private(set) var storage = LoadTestStorageUsage()
    private(set) var progress: Progress?
    private(set) var isDeleting = false
    private(set) var isClosing = false
    private(set) var message: String?

    init(workspace: FacilityDemoViewModel) {
        offlineWorkStore = workspace.offlineWorkStore
        let sapDataStore = workspace.sapDataStore
        seeder = LoadTestSeeder(
            offlineWorkStore: workspace.offlineWorkStore,
            photoStore: workspace.photoAttachmentStore,
            mobileLadderProvider: workspace.mobileLadderCreationProvider,
            subdistributionProvider: workspace.subdistributionCreationProvider,
            loadDefectParents: { await sapDataStore.loadDefectParentNotifications() },
            loadDefectObjects: {
                let nodes = (try? await sapDataStore.searchTechnicalObjects("", dinGroup: nil, limit: 500)) ?? []
                return nodes.filter { !$0.isSynthetic }.map(DefectObjectOption.init(node:))
            },
            loadInstructionSource: { LoadTestInstructionSource.make(for: workspace) }
        )
    }

    var inventory: LoadTestInventory {
        // Read so the counts follow the queue.
        _ = offlineWorkStore.revision
        return seeder.inventory
    }

    var isBusy: Bool { progress != nil || isDeleting || isClosing }

    /// Why nothing can be generated right now, or `nil` when it can.
    var generationBlocker: String? {
        guard availability != nil else { return "Reading the SAP cache…" }
        if configuration.recordCount == 0 { return "Choose at least one record to generate." }
        let required = configuration.estimatedPhotoByteCount + Self.freeSpaceReserve
        if configuration.photoCount > 0, storage.freeByteCount > 0, required > storage.freeByteCount {
            return "Not enough free space for these photos."
        }
        return nil
    }

    func refresh() async {
        let availability = await seeder.availability()
        self.availability = availability
        // A kind the cache has nothing for cannot be generated.
        if availability.defectParentCount == 0 { configuration.defectCount = 0 }
        if availability.mobileLadderContextCount == 0 { configuration.mobileLadderCount = 0 }
        if availability.subdistributionContextCount == 0 { configuration.subdistributionCount = 0 }
        if !availability.canGenerateInstructionForms {
            configuration.electricalSafetyCount = 0
            configuration.firePermitCount = 0
        }
        if !availability.canGenerateInstructionForms || !availability.hasBriefingTemplate {
            configuration.briefingCount = 0
        }
        if !availability.canGenerateInstructionForms || !availability.hasQualificationTemplate {
            configuration.qualificationCount = 0
        }
        storage = await Task.detached { LoadTestStorageUsage.measure() }.value
    }

    func generate() {
        guard !isBusy, generationBlocker == nil else { return }
        let configuration = configuration
        message = nil
        progress = Progress(done: 0, total: configuration.recordCount)
        task = Task {
            do {
                let result = try await seeder.generate(configuration) { [weak self] done, total in
                    self?.progress = Progress(done: done, total: total)
                }
                message = Self.summary(result)
            } catch {
                message = "Generation failed: \(error.localizedDescription)"
            }
            progress = nil
            task = nil
            await refresh()
        }
    }

    func cancel() {
        task?.cancel()
    }

    func deleteGenerated() {
        guard !isBusy else { return }
        isDeleting = true
        message = nil
        Task {
            do {
                try await seeder.deleteGenerated()
                message = "Generated records and their photos were deleted."
            } catch {
                message = "Deleting failed: \(error.localizedDescription)"
            }
            isDeleting = false
            await refresh()
        }
    }

    func closeGeneratedDrafts() {
        guard !isBusy else { return }
        isClosing = true
        message = nil
        let photoByteCount = configuration.photoByteCount
        Task {
            do {
                let count = try await seeder.closeGeneratedDrafts(photoByteCount: photoByteCount)
                message = "Closed \(count) generated drafts. They are sent with the next synchronization."
            } catch {
                message = "Closing failed: \(error.localizedDescription)"
            }
            isClosing = false
            await refresh()
        }
    }

    private static func summary(_ result: LoadTestResult) -> String {
        let lead = result.wasCancelled ? "Cancelled after" : "Created"
        return "\(lead) \(result.recordCount) records with \(result.photoCount) photos in "
            + "\(seconds(result.generationDuration)). Reloading local work took \(seconds(result.reloadDuration))."
    }

    private static func seconds(_ interval: TimeInterval) -> String {
        String(format: "%.2f s", interval)
    }
}

/// Debug-only card in the profile settings that fills the offline queue with
/// generated work. Its texts are developer-facing and deliberately not in the
/// String Catalog, so they never ship.
struct LoadTestPanelView: View {
    private static let recordCounts = [0, 10, 50, 100, 250, 500, 1000]
    private static let photoCounts = [0, 1, 5, 10, 20, 50]
    private static let photoByteCounts = [500_000, 2_000_000, 4_000_000]

    @State private var model: LoadTestPanelModel
    @State private var isConfirmingClosedRecords = false
    @State private var isConfirmingDeletion = false
    @State private var isConfirmingDraftClosing = false

    init(workspace: FacilityDemoViewModel) {
        _model = State(initialValue: LoadTestPanelModel(workspace: workspace))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            Divider()
            recordRows
            Divider()
            instructionRows
            Divider()
            photoRows
            Divider()
            statusRow
            estimate
            actions
            Divider()
            inventory
        }
        .facilityCard()
        .task { await model.refresh() }
        .alert(Text(verbatim: "Generate records for SAP?"), isPresented: $isConfirmingClosedRecords) {
            button("Cancel", role: .cancel) {}
            button("Generate", role: .destructive) { model.generate() }
        } message: {
            Text(verbatim: "Closed records are sent to SAP with the next synchronization. "
                + "Every ladder and sub-distribution creates real equipment and a notification there, "
                + "every I3 form a notification with its report. Use this on a test client only.")
        }
        .alert(Text(verbatim: "Close generated drafts?"), isPresented: $isConfirmingDraftClosing) {
            button("Cancel", role: .cancel) {}
            button("Close drafts", role: .destructive) { model.closeGeneratedDrafts() }
        } message: {
            Text(verbatim: "Closes the \(model.inventory.draftCount) \(LoadTestSeeder.marker) drafts on this device. "
                + "They are sent to SAP with the next synchronization, where every ladder and "
                + "sub-distribution creates real equipment and a notification. Use this on a test client only.")
        }
        .alert(Text(verbatim: "Delete generated records?"), isPresented: $isConfirmingDeletion) {
            button("Cancel", role: .cancel) {}
            button("Delete", role: .destructive) { model.deleteGenerated() }
        } message: {
            Text(verbatim: "Removes every \(LoadTestSeeder.marker) record and its photos from this device. "
                + "Other local work is not touched.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.title2.weight(.semibold))
                .foregroundStyle(FacilityTheme.orange)
                .frame(width: 46, height: 46)
                .background(FacilityTheme.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(verbatim: "Load test")
                        .font(.headline)
                        .foregroundStyle(FacilityTheme.ink)
                    Text(verbatim: "DEBUG")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(FacilityTheme.orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(FacilityTheme.orange.opacity(0.12), in: Capsule())
                }
                Text(verbatim: "Fills local work with generated I2 defects, mobile ladders, sub-distributions and I3 forms. "
                    + "Every record is marked \(LoadTestSeeder.marker).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var recordRows: some View {
        let availability = model.availability
        countRow(
            "I2 defects",
            available: availability?.defectParentCount,
            availableNote: { "Spread over \($0) open I1 notifications" },
            unavailableNote: "No open I1 in the SAP cache. Synchronize first.",
            selection: $model.configuration.defectCount
        )
        countRow(
            "Mobile ladders (TFM5)",
            available: availability?.mobileLadderContextCount,
            availableNote: { "Spread over \($0) places from the SAP cache" },
            unavailableNote: "No ladder template in the SAP cache. Synchronize first.",
            selection: $model.configuration.mobileLadderCount
        )
        countRow(
            "Sub-distributions (TFM7)",
            available: availability?.subdistributionContextCount,
            availableNote: { "Spread over \($0) places from the SAP cache" },
            unavailableNote: "No sub-distribution template in the SAP cache. Synchronize first.",
            selection: $model.configuration.subdistributionCount
        )
    }

    @ViewBuilder
    private var instructionRows: some View {
        let availability = model.availability
        let buildings = availability?.instructionContextCount ?? 0
        let isAvailable = availability?.canGenerateInstructionForms == true
        let sharedNote = "Partner \(LoadTestInstructionSource.testPartnerName), spread over \(buildings) buildings"
        Text(verbatim: "I3 forms. They carry a report, no photos.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        countRow(
            "Briefings",
            available: availability.map { isAvailable && $0.hasBriefingTemplate ? buildings : 0 },
            availableNote: { _ in sharedNote },
            unavailableNote: instructionBlocker(plan: "TFMB_001", hasPlan: availability?.hasBriefingTemplate),
            selection: $model.configuration.briefingCount
        )
        countRow(
            "Proofs of qualification",
            available: availability.map { isAvailable && $0.hasQualificationTemplate ? buildings : 0 },
            availableNote: { _ in sharedNote },
            unavailableNote: instructionBlocker(plan: "TFMQ_001", hasPlan: availability?.hasQualificationTemplate),
            selection: $model.configuration.qualificationCount
        )
        countRow(
            "Electrical safety forms",
            available: availability.map { _ in isAvailable ? buildings : 0 },
            availableNote: { _ in sharedNote },
            unavailableNote: instructionBlocker(plan: nil, hasPlan: nil),
            selection: $model.configuration.electricalSafetyCount
        )
        countRow(
            "Fire permits",
            available: availability.map { _ in isAvailable ? buildings : 0 },
            availableNote: { _ in "Always closed and sent to SAP: the form keeps no drafts." },
            unavailableNote: instructionBlocker(plan: nil, hasPlan: nil),
            selection: $model.configuration.firePermitCount
        )
    }

    /// Why an I3 form cannot be generated.
    private func instructionBlocker(plan: String?, hasPlan: Bool?) -> String {
        guard let availability = model.availability else { return "" }
        if availability.instructionContextCount == 0 {
            return "No buildings in the SAP cache. Synchronize first."
        }
        if !availability.hasTestPartner {
            return "Partner \(LoadTestInstructionSource.testPartnerName) is not in the SAP cache."
        }
        if let plan, hasPlan == false {
            return "Plan \(plan) is not in the SAP cache. Synchronize first."
        }
        return ""
    }

    @ViewBuilder
    private var photoRows: some View {
        row(
            "Photos per record",
            note: model.configuration.photosPerRecord > LoadTestConfiguration.maximumFormPhotoCount
                ? "Ladders and sub-distributions take at most \(LoadTestConfiguration.maximumFormPhotoCount)."
                : nil
        ) {
            picker(Self.photoCounts, selection: $model.configuration.photosPerRecord) { "\($0)" }
        }
        row("Photo size", note: "Generated noise image, the same for the whole run") {
            picker(Self.photoByteCounts, selection: $model.configuration.photoByteCount) {
                Self.bytes(Int64($0))
            }
        }
    }

    private var statusRow: some View {
        row(
            "Close the records",
            note: model.configuration.closesRecords
                ? "Queued for the next synchronization and sent to SAP."
                : model.configuration.firePermitCount > 0
                    ? "Drafts, except the fire permits: those are always closed and sent to SAP."
                    : "Drafts. Nothing is sent to SAP."
        ) {
            Toggle(isOn: $model.configuration.closesRecords) { EmptyView() }
                .labelsHidden()
                .tint(FacilityTheme.orange)
                .disabled(model.isBusy)
        }
    }

    private var estimate: some View {
        let configuration = model.configuration
        return Text(verbatim: "\(configuration.recordCount) records, \(configuration.photoCount) photos, "
            + "about \(Self.bytes(configuration.estimatedPhotoByteCount)). "
            + "Free: \(Self.bytes(model.storage.freeByteCount)).")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var actions: some View {
        if let progress = model.progress {
            HStack(spacing: 14) {
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                    .tint(FacilityTheme.orange)
                Text(verbatim: "\(progress.done) / \(progress.total)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                button("Cancel") { model.cancel() }
                    .buttonStyle(.bordered)
            }
            .frame(minHeight: 44)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    button("Generate") {
                        if model.configuration.queuesRecords {
                            isConfirmingClosedRecords = true
                        } else {
                            model.generate()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(FacilityTheme.orange)
                    .disabled(model.isBusy || model.generationBlocker != nil)

                    button("Close drafts") { isConfirmingDraftClosing = true }
                        .buttonStyle(.bordered)
                        .tint(FacilityTheme.orange)
                        .disabled(model.isBusy || model.inventory.draftCount == 0)

                    button("Delete generated", role: .destructive) { isConfirmingDeletion = true }
                        .buttonStyle(.bordered)
                        .disabled(model.isBusy || model.inventory.recordCount == 0)

                    if model.isDeleting || model.isClosing { ProgressView() }
                }
                .frame(minHeight: 44)

                if let blocker = model.generationBlocker {
                    Text(verbatim: blocker)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let message = model.message {
                    Text(verbatim: message)
                        .font(.footnote)
                        .foregroundStyle(FacilityTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var inventory: some View {
        let inventory = model.inventory
        return VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "On this device")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FacilityTheme.ink)
            Text(verbatim: "Generated: \(inventory.defectCount) I2 defects, \(inventory.mobileLadderCount) ladders, "
                + "\(inventory.subdistributionCount) sub-distributions, \(inventory.photoCount) photos, "
                + "\(inventory.briefingCount) briefings, \(inventory.qualificationCount) proofs of qualification, "
                + "\(inventory.electricalSafetyCount) electrical safety forms, \(inventory.firePermitCount) fire permits. "
                + "\(inventory.draftCount) are still drafts.")
            Text(verbatim: "All photos: \(Self.bytes(model.storage.photoByteCount)). "
                + "Local work database: \(Self.bytes(model.storage.databaseByteCount)).")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private func countRow(
        _ title: String,
        available: Int?,
        availableNote: (Int) -> String,
        unavailableNote: String,
        selection: Binding<Int>
    ) -> some View {
        let isAvailable = (available ?? 0) > 0
        return row(title, note: available.map { $0 > 0 ? availableNote($0) : unavailableNote }) {
            picker(Self.recordCounts, selection: selection) { "\($0)" }
                .disabled(!isAvailable)
        }
    }

    private func row<Control: View>(
        _ title: String,
        note: String?,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FacilityTheme.ink)
                if let note {
                    Text(verbatim: note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control()
        }
        .frame(minHeight: 44)
    }

    private func picker(
        _ values: [Int],
        selection: Binding<Int>,
        title: @escaping (Int) -> String
    ) -> some View {
        Picker(selection: selection) {
            ForEach(values, id: \.self) { value in
                Text(verbatim: title(value)).tag(value)
            }
        } label: {
            EmptyView()
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .tint(FacilityTheme.blue)
        .disabled(model.isBusy)
    }

    /// Verbatim, so the title is not picked up as a String Catalog key.
    private func button(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) { Text(verbatim: title) }
    }

    private static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}
#endif
