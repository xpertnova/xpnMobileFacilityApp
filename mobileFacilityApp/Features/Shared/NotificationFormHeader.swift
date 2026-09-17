import SwiftUI

/// The one notification header shared by every maintenance form.
///
/// The legacy Cordova app declared the header exactly once, in
/// `www/fragment/FormHeader.fragment.xml`, and every form view embedded that
/// same fragment: `Rundgang` (TFM3), `WartungsPlan` (TFM1),
/// `Aufzugskontrolle` (TFM2) and `CreateNewForm` (TFM5). This file is the
/// SwiftUI equivalent of that fragment, so the four screens keep one header
/// instead of four copies that drift apart.
///
/// The visual design is taken from the Rundgang/TFM3 detail screen, and TFM3
/// is also the template for which notification information the header shows:
/// the legacy `ObjectHeader` attributes (`QMNUM`, `STRNO`, `PLTXT`, `EQKTX`,
/// address) plus the structure, status and date-range rows the SwiftUI screen
/// added on top of them.
struct NotificationFormHeaderInfo: Equatable {
    /// Heading text — the notification short text (`QMTXT`), falling back to
    /// the notification number when SAP delivered no short text.
    var title: String
    /// Notification number (`QMNUM`). Empty for a form that has not been
    /// assigned a local `NEU` identifier yet.
    var notificationID: String
    /// Form code (`STEUS`/`FORMNR`), rendered as the grey badge: TFM1 … TFM5.
    var formCode: String
    /// Technical place (`STRNO`).
    var technicalPlace: String
    /// Technical place description (`PLTXT`).
    var technicalPlaceDescription: String
    /// Postal address assembled from the `*_TO` address fields.
    var address: String
    /// Structure indicator (`STRUR`).
    var structure: String
    /// Equipment number (`EQUNR`).
    var equipmentID: String
    var systemStatus: String
    var userStatus: String
    var dateRange: String

    /// Combined SAP status shown as the blue badge next to the title.
    var displayStatus: String {
        [systemStatus, userStatus]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// Line under the title: `Meldung <number> · <date range>`, matching the
    /// Rundgang/TFM3 subtitle.
    var subtitle: String {
        let identifier = notificationID.isEmpty
            ? ""
            : "\(String(localized: "notifications.detail.number")) \(notificationID)"
        return [identifier, dateRange]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    init(
        title: String,
        notificationID: String = "",
        formCode: String = "",
        technicalPlace: String = "",
        technicalPlaceDescription: String = "",
        address: String = "",
        structure: String = "",
        equipmentID: String = "",
        systemStatus: String = "",
        userStatus: String = "",
        dateRange: String = ""
    ) {
        self.title = title
        self.notificationID = notificationID
        self.formCode = formCode
        self.technicalPlace = technicalPlace
        self.technicalPlaceDescription = technicalPlaceDescription
        self.address = address
        self.structure = structure
        self.equipmentID = equipmentID
        self.systemStatus = systemStatus
        self.userStatus = userStatus
        self.dateRange = dateRange
    }

    /// Builds the header of a loaded SAP notification (TFM1, TFM2, TFM3, TFM5
    /// and every other `I1` form that reaches the generic review screen).
    ///
    /// - Parameter formCode: overrides the code decoded from the payload for a
    ///   screen that already knows which form it renders. The elevator screen
    ///   passes `TFM2` because it recognises the notification from `FORMNR`
    ///   even when the plan positions carry no `STEUS`.
    init(detail: SAPNotificationDetail, formCode: String? = nil) {
        self.init(
            title: detail.summary.title.isEmpty ? detail.summary.id : detail.summary.title,
            notificationID: detail.summary.id,
            formCode: (formCode ?? detail.formCode).uppercased(),
            technicalPlace: detail.summary.functionalLocationID,
            technicalPlaceDescription: detail.summary.functionalLocationName,
            address: detail.address,
            structure: detail.structure,
            // `EQUNR` only reached the detail payload after the cache format
            // change, so fall back to the summary for older cached rows.
            equipmentID: detail.equipmentID.isEmpty ? detail.summary.equipmentID : detail.equipmentID,
            systemStatus: detail.summary.systemStatus,
            userStatus: detail.summary.userStatus,
            dateRange: detail.summary.displayDateRange
        )
    }
}

/// Top bar of the shared header: back button, notification title, subtitle and
/// the form/status badges.
struct NotificationFormHeaderBar: View {
    let info: NotificationFormHeaderInfo
    /// Localization key of the destination the back button returns to.
    let backTitleKey: String
    /// Replaces the SAP status badge with the green "closed" badge once the
    /// form has been closed locally and is waiting for synchronization.
    var isClosedLocally: Bool = false
    let back: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                Button(action: back) {
                    Label(LocalizedStringKey(backTitleKey), systemImage: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(FacilityTheme.blue)
                .frame(minHeight: 44, alignment: .leading)

                Text(info.title)
                    .font(.system(size: 29, weight: .bold))
                    .foregroundStyle(FacilityTheme.ink)

                if !info.subtitle.isEmpty {
                    Text(info.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                if !info.formCode.isEmpty {
                    Text(info.formCode)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(white: 0.92), in: Capsule())
                }

                if isClosedLocally {
                    Text("notifications.detail.status.closed")
                        .font(.caption.bold())
                        .foregroundStyle(FacilityTheme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(FacilityTheme.accent.opacity(0.12), in: Capsule())
                } else if !info.displayStatus.isEmpty {
                    Text(info.displayStatus)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(FacilityTheme.blue)
                        .multilineTextAlignment(.trailing)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(FacilityTheme.blue.opacity(0.10), in: Capsule())
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(FacilityTheme.surface)
    }
}

/// Information card of the shared header: every notification attribute the
/// legacy `FormHeader` fragment carried.
///
/// The execution date and the "Außer Betrieb" / "Demontiert" status are
/// deliberately *not* here. The legacy client keeps them in
/// `www/fragment/TableFormHeader.fragment.xml`, on one toolbar band directly
/// above the position table, so they live on `InspectionFormTable` instead.
struct NotificationFormHeaderCard: View {
    let info: NotificationFormHeaderInfo

    var body: some View {
        HStack(alignment: .top, spacing: 30) {
            VStack(alignment: .leading, spacing: 15) {
                if !info.technicalPlace.isEmpty {
                    NotificationMetadataRow(
                        titleKey: "notifications.detail.technicalPlace",
                        value: info.technicalPlace,
                        monospaced: true
                    )
                }
                if !info.technicalPlaceDescription.isEmpty {
                    NotificationMetadataRow(
                        titleKey: "notifications.detail.description",
                        value: info.technicalPlaceDescription
                    )
                }
                if !info.address.isEmpty {
                    NotificationMetadataRow(
                        titleKey: "notifications.detail.address",
                        value: info.address
                    )
                }
                if !info.structure.isEmpty {
                    NotificationMetadataRow(
                        titleKey: "notifications.detail.structure",
                        value: info.structure
                    )
                }
                if !info.equipmentID.isEmpty {
                    NotificationMetadataRow(
                        titleKey: "notifications.detail.equipment",
                        value: info.equipmentID,
                        monospaced: true
                    )
                }
                if !info.systemStatus.isEmpty {
                    NotificationMetadataRow(
                        titleKey: "notifications.detail.systemStatus",
                        value: info.systemStatus
                    )
                }
                if !info.userStatus.isEmpty {
                    NotificationMetadataRow(
                        titleKey: "notifications.detail.userStatus",
                        value: info.userStatus
                    )
                }
                if !info.dateRange.isEmpty {
                    NotificationMetadataRow(
                        titleKey: "notifications.detail.dateRange",
                        value: info.dateRange
                    )
                }
            }

            Spacer(minLength: 0)
        }
        .facilityCard(padding: 22)
    }
}
