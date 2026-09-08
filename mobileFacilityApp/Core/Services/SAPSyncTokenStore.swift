import Foundation
import Security

protocol SAPSyncTokenStore: Sendable {
    func token(for workerID: String) -> String?
    func save(token: String, for workerID: String) throws
    func deleteToken(for workerID: String)
}

final class KeychainSAPSyncTokenStore: SAPSyncTokenStore, @unchecked Sendable {
    private let service: String

    init(service: String = "com.mobilefacility.app.sap-sync-token") {
        self.service = service
    }

    private func normalizedWorkerID(_ workerID: String) -> String {
        workerID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(with: Locale(identifier: "en_US_POSIX"))
    }

    func token(for workerID: String) -> String? {
        let account = normalizedWorkerID(workerID)
        guard !account.isEmpty else { return nil }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func save(token: String, for workerID: String) throws {
        let account = normalizedWorkerID(workerID)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !account.isEmpty, !trimmedToken.isEmpty else { return }
        guard let tokenData = trimmedToken.data(using: .utf8) else { return }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]

        let updateAttributes: [CFString: Any] = [
            kSecValueData: tokenData
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var newQuery = query
            newQuery[kSecValueData] = tokenData
            newQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(newQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus), userInfo: [
                    NSLocalizedDescriptionKey: "Failed to store SAP sync token in Keychain (\(addStatus))."
                ])
            }
        } else if updateStatus != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(updateStatus), userInfo: [
                NSLocalizedDescriptionKey: "Failed to update SAP sync token in Keychain (\(updateStatus))."
            ])
        }
    }

    func deleteToken(for workerID: String) {
        let account = normalizedWorkerID(workerID)
        guard !account.isEmpty else { return }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

final class InMemorySAPSyncTokenStore: SAPSyncTokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [String: String] = [:]

    private func normalizedWorkerID(_ workerID: String) -> String {
        workerID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(with: Locale(identifier: "en_US_POSIX"))
    }

    func token(for workerID: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        let key = normalizedWorkerID(workerID)
        return tokens[key]
    }

    func save(token: String, for workerID: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let key = normalizedWorkerID(workerID)
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            tokens.removeValue(forKey: key)
        } else {
            tokens[key] = trimmed
        }
    }

    func deleteToken(for workerID: String) {
        lock.lock()
        defer { lock.unlock() }
        let key = normalizedWorkerID(workerID)
        tokens.removeValue(forKey: key)
    }
}
