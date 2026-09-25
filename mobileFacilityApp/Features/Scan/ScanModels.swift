import Foundation

enum LegacyQRCodePayload: Equatable, Sendable {
    case mtfm(controlKey: String?, functionalLocationID: String, equipmentID: String?)
    case mihm(objectNumber: String, technicalReference: String)
}

enum LegacyQRCodeCodecError: Error, Equatable {
    case invalidPayload
}

enum QRCodeResolutionError: Error, Equatable {
    case synchronizationRequired
    case cacheUnavailable
}

enum LegacyQRCodeCodec {
    static let maximumRawLength = 512

    static func decode(_ rawValue: String) throws -> LegacyQRCodePayload {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmedValue
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        guard
            !value.isEmpty,
            trimmedValue.utf8.count <= maximumRawLength,
            let data = Data(base64Encoded: value),
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw LegacyQRCodeCodecError.invalidPayload
        }

        if let functionalLocationID = nonEmptyString(object[caseInsensitive: "STRNO"]),
           let rawControlKey = object[caseInsensitive: "STEUS"] as? String,
           let equipment = nonEmptyString(object[caseInsensitive: "EQUNR"])
        {
            let controlKey = nonEmptyString(rawControlKey)
            return .mtfm(
                controlKey: controlKey,
                functionalLocationID: functionalLocationID,
                equipmentID: equipment == "%" ? nil : equipment
            )
        }

        if let rawObjectNumber = nonEmptyString(object[caseInsensitive: "objnr"]),
           let technicalReference = nonEmptyString(object[caseInsensitive: "tganr"]),
           rawObjectNumber.allSatisfy(\.isNumber)
        {
            let normalizedNumber = rawObjectNumber.drop(while: { $0 == "0" })
            return .mihm(
                objectNumber: normalizedNumber.isEmpty ? "0" : String(normalizedNumber),
                technicalReference: String(technicalReference.prefix(30))
            )
        }

        throw LegacyQRCodeCodecError.invalidPayload
    }

    /// The counterpart of `decode`, and the format the legacy app printed on
    /// its labels: `QrPrintList.controller.js` base64-encodes
    /// `{"STEUS":…,"STRNO":…,"EQUNR":…}` with `"%"` standing in for "no
    /// equipment". A code produced here is therefore readable both by this
    /// app's scanner and by the labels already in the field.
    static func encodeMTFM(
        controlKey: String? = nil,
        functionalLocationID: String,
        equipmentID: String? = nil
    ) -> String {
        let object: [String: String] = [
            "STEUS": controlKey ?? "",
            "STRNO": functionalLocationID,
            "EQUNR": equipmentID ?? "%"
        ]
        let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return data?.base64EncodedString() ?? ""
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

protocol QRCodeNotificationResolving: Sendable {
    func resolveQRCode(
        _ payload: LegacyQRCodePayload,
        for localWorkerID: String
    ) async throws -> [SAPNotificationSummary]
}

private extension Dictionary where Key == String, Value == Any {
    subscript(caseInsensitive key: String) -> Any? {
        first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }
}
