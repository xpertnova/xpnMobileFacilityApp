import Foundation

/// `insertSaveProcessVorschlag`: one `TO_T0211` row per proposal, which the
/// sync sends to SAP as `T_0211R`. Shared by every form that offers
/// "Pflege durch Admin" (see `MasterDataProposalRules`).
enum SAPMasterDataProposalRows {
    /// - Parameters:
    ///   - proposals: proposal text per characteristic (`ATNAM`), which is
    ///     the row's `ELEMENTNR`. Empty proposals are skipped.
    ///   - equipmentID: `masterDataQuery.EQUNR`; the new equipment number
    ///     when the form creates the object.
    ///   - functionalLocationID: `masterDataQuery.STRNO`, empty for an
    ///     equipment or a newly created object.
    static func rows(
        proposals: [String: String],
        processID: String,
        notificationID: String,
        equipmentID: String,
        functionalLocationID: String,
        userID: String,
        date: String,
        time: String
    ) -> [LegacySAPRow] {
        proposals
            .compactMap { elementID, proposal -> (String, String)? in
                let value = MasterDataProposalRules.normalized(proposal)
                return value.isEmpty ? nil : (elementID, value)
            }
            .sorted { $0.0 < $1.0 }
            .map { elementID, proposal in
                // The legacy `type4T0211` leaves `MANDT` empty and sets `AKTIV`.
                [
                    "MANDT": "", "REQID": "", "VORGANGSNR": processID,
                    "ELEMENTNR": elementID, "QMNUM": notificationID,
                    "STRNO": functionalLocationID, "EQUNR": equipmentID,
                    "CREATEDBY": userID, "CREATEDDATE": date, "CREATEDTIME": time,
                    "MODIFIEDDATE": date, "MODIFIEDTIME": time, "MODIFIEDBY": userID,
                    "FELDWERT": proposal, "AKTIV": "X"
                ]
            }
    }
}
