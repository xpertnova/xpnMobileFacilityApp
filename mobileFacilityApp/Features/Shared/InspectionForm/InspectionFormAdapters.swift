import Foundation

// MARK: - Segmented yes/no forms (TFM1 Wartungsplan, TFM3 Rundgang)

extension NotificationReviewResult {
    /// The two options the legacy segmented forms build from `T_PROPS[0]`.
    ///
    /// Their transport codes are `""` for "in Ordnung" and `"X"` for a defect
    /// (`SAPNotificationReviewUpload` posts exactly that), so the options carry
    /// a separate `id` — an empty code cannot double as "not yet answered".
    static let formOptions: [InspectionFormOption] = [
        InspectionFormOption(
            id: NotificationReviewResult.no.rawValue,
            code: "",
            titleKey: "notifications.detail.result.no",
            tint: .satisfactory
        ),
        InspectionFormOption(
            id: NotificationReviewResult.yes.rawValue,
            code: InspectionFormRules.segmentedDefectCode,
            titleKey: "notifications.detail.result.yes",
            tint: .defect
        )
    ]

    var optionID: String { rawValue }

    init?(optionID: String?) {
        guard let optionID, let value = Self(rawValue: optionID) else { return nil }
        self = value
    }
}

extension SAPNotificationDetail.InspectionItem {
    /// Presents a decoded `T_PLPOD` position as a shared checklist row.
    ///
    /// A `MEASURE` row becomes a reading button only when the form passes
    /// `measuringPoints`; the Rundgang is the only legacy form that defines
    /// `getColumnListItemReading`.
    func inspectionFormItem(
        number: Int,
        measuringPoints: InspectionFormMeasuringPointAvailability? = nil
    ) -> InspectionFormItem {
        if let buttonTitle = measuringPointButtonTitle, let measuringPoints {
            return InspectionFormItem(
                id: id,
                number: number,
                title: title,
                information: information,
                groupTitle: groupTitle,
                requiresResult: false,
                measuringPoint: InspectionFormMeasuringPoint(
                    buttonTitle: buttonTitle,
                    unavailableReasonKey: measuringPoints.unavailableReasonKey
                )
            )
        }
        return InspectionFormItem(
            id: id,
            number: number,
            title: title,
            information: information,
            groupTitle: groupTitle,
            resultOptions: NotificationReviewResult.formOptions
        )
    }
}

/// Whether SAP delivered measuring points for the notification's place.
enum InspectionFormMeasuringPointAvailability: Equatable, Sendable {
    case loading
    case available
    /// `FROM_T0274` holds no point for the place.
    case none
    /// The points could not be read from the cache.
    case unreadable

    init(points: [SAPMeasuringPoint]?, isLoading: Bool) {
        if isLoading {
            self = .loading
        } else if let points {
            self = points.isEmpty ? .none : .available
        } else {
            self = .unreadable
        }
    }

    var unavailableReasonKey: String? {
        switch self {
        case .available: nil
        case .loading: "measuringPoints.row.loading"
        case .none: "measuringPoints.row.none"
        case .unreadable: "measuringPoints.row.unreadable"
        }
    }
}

// MARK: - TFM2 Aufzugskontrolle / TFM6 Feststellanlage

extension ElevatorInspectionItem {
    /// Presents an SAP-driven elevator position as a shared checklist row.
    /// Result and action options come straight from `T_PROPS` `DFVAL` pairs.
    var inspectionFormItem: InspectionFormItem {
        InspectionFormItem(
            id: id,
            number: positionNumber,
            title: title,
            information: information,
            groupTitle: groupTitle,
            resultOptions: resultOptions.map {
                InspectionFormOption(code: $0.code, title: $0.text)
            },
            actionOptions: hasAction
                ? actionOptions.map { InspectionFormOption(code: $0.code, title: $0.text) }
                : [],
            supportsMaterial: hasMaterial,
            requiresResult: requiresResult,
            requiresPhoto: requiresPhoto,
            requiresPhotoAndComment: requiresPhotoAndComment
        )
    }
}

// MARK: - TFM5 Mobile ladder

extension MobileLadderInspectionResult {
    static let formOptions: [InspectionFormOption] = allCases.map {
        InspectionFormOption(code: $0.code, titleKey: $0.titleKey)
    }
}

extension MobileLadderInspectionAction {
    static let formOptions: [InspectionFormOption] = allCases.map {
        InspectionFormOption(code: $0.code, titleKey: $0.titleKey)
    }
}

extension MobileLadderInspectionItem {
    var inspectionFormItem: InspectionFormItem {
        InspectionFormItem(
            id: id,
            number: number,
            title: title,
            information: information,
            resultOptions: MobileLadderInspectionResult.formOptions,
            actionOptions: MobileLadderInspectionAction.formOptions
        )
    }

    var inspectionFormState: InspectionFormItemState {
        InspectionFormItemState(
            resultID: result?.code,
            actionID: action?.code,
            comment: comment
        )
    }
}

// MARK: - TFM7 Subdistribution

extension SubdistributionInspectionItem {
    var inspectionFormItem: InspectionFormItem {
        InspectionFormItem(
            id: id,
            number: number,
            title: title,
            information: information,
            resultOptions: requiresResult
                ? resultValues.map { InspectionFormOption(code: $0.value, title: $0.title) }
                : [],
            actionOptions: requiresResult
                ? actionValues.map { InspectionFormOption(code: $0.value, title: $0.title) }
                : [],
            requiresResult: requiresResult
        )
    }

    var inspectionFormState: InspectionFormItemState {
        InspectionFormItemState(resultID: result, actionID: action, comment: comment)
    }
}
