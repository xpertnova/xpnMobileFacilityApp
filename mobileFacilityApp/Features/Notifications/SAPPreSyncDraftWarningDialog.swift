import SwiftUI

struct SAPPreSyncDraftWarningDialog: View {
    let draftCount: Int
    let confirm: () -> Void
    let keepDrafts: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(FacilityTheme.red.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(FacilityTheme.red)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("sap.refresh.draftWarning.title")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(FacilityTheme.ink)
                    Text("sap.refresh.draftWarning.subtitle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: cancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(FacilityTheme.ink.opacity(0.55))
                        .frame(width: 32, height: 32)
                        .background(Color.black.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("common.cancel"))
            }

            // Warning detail card
            VStack(alignment: .leading, spacing: 12) {
                // Draft count pill
                HStack(spacing: 8) {
                    Image(systemName: "doc.badge.clock")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(FacilityTheme.orange)
                    Text(
                        String.localizedStringWithFormat(
                            String(localized: "sap.refresh.draftWarning.draftCountBadge"),
                            draftCount
                        )
                    )
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(FacilityTheme.orange)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(FacilityTheme.orange.opacity(0.12), in: Capsule())

                Text(
                    String.localizedStringWithFormat(
                        String(localized: "sap.refresh.draftWarning.message"),
                        draftCount
                    )
                )
                .font(.subheadline)
                .foregroundStyle(FacilityTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

                Divider()
                    .padding(.vertical, 2)

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 1)
                    Text("sap.refresh.draftWarning.tip")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.98, green: 0.98, blue: 0.99), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            }

            // Action Buttons
            HStack(spacing: 12) {
                // Secondary action: Keep drafts, abort sync, and navigate to drafts screen
                Button(action: keepDrafts) {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .font(.subheadline.weight(.semibold))
                        Text("sap.refresh.draftWarning.keepDrafts")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(FacilityTheme.ink)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                // Destructive action: Discard drafts and proceed with sync
                Button(action: confirm) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash.fill")
                            .font(.subheadline.weight(.semibold))
                        Text("sap.refresh.draftWarning.confirmAction")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(FacilityTheme.red, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .padding(28)
        .frame(width: 500, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.24), radius: 28, y: 14)
    }
}
