import CryptoKit
import Foundation
import Security

enum LocalCredentialStoreError: Error {
    case usernameAlreadyExists
    case invalidCredentials
    case storageUnavailable
}

struct LocalAuthenticatedUser: Equatable, Sendable {
    let workerID: String
    let displayName: String
}

struct LocalCredentialStore {
    private static let storageKey = "mobileFacility.localCredentials"
    private static let saltByteCount = 32

    static func createAccount(
        username: String,
        password: String,
        defaults: UserDefaults = .standard
    ) throws -> LocalAuthenticatedUser {
        let displayName = trimmedUsername(username)
        // The shared device carries no password policy: any password the
        // technician types is accepted. The sign-in screen only insists that
        // both fields are filled in.
        guard !displayName.isEmpty else {
            throw LocalCredentialStoreError.invalidCredentials
        }

        let normalizedUsername = normalizedUsername(displayName)
        var accounts = try loadAccounts(from: defaults)
        guard accounts[normalizedUsername] == nil else {
            throw LocalCredentialStoreError.usernameAlreadyExists
        }

        let salt = try makeSalt()
        accounts[normalizedUsername] = StoredCredentials(
            displayName: displayName,
            salt: salt.base64EncodedString(),
            passwordHash: hash(password: password, salt: salt).base64EncodedString()
        )
        try save(accounts, to: defaults)

        return LocalAuthenticatedUser(workerID: normalizedUsername, displayName: displayName)
    }

    static func authenticate(
        username: String,
        password: String,
        defaults: UserDefaults = .standard
    ) throws -> LocalAuthenticatedUser {
        let normalizedUsername = normalizedUsername(username)
        let accounts = try loadAccounts(from: defaults)

        guard let account = accounts[normalizedUsername],
              let salt = Data(base64Encoded: account.salt),
              let expectedHash = Data(base64Encoded: account.passwordHash),
              hashesMatch(hash(password: password, salt: salt), expectedHash) else {
            throw LocalCredentialStoreError.invalidCredentials
        }

        return LocalAuthenticatedUser(workerID: normalizedUsername, displayName: account.displayName)
    }

    private static func loadAccounts(from defaults: UserDefaults) throws -> [String: StoredCredentials] {
        guard let data = defaults.data(forKey: storageKey) else {
            return [:]
        }

        do {
            return try JSONDecoder().decode([String: StoredCredentials].self, from: data)
        } catch {
            throw LocalCredentialStoreError.storageUnavailable
        }
    }

    private static func save(_ accounts: [String: StoredCredentials], to defaults: UserDefaults) throws {
        do {
            defaults.set(try JSONEncoder().encode(accounts), forKey: storageKey)
        } catch {
            throw LocalCredentialStoreError.storageUnavailable
        }
    }

    private static func trimmedUsername(_ username: String) -> String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedUsername(_ username: String) -> String {
        trimmedUsername(username)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
    }

    private static func makeSalt() throws -> Data {
        var salt = Data(count: saltByteCount)
        let status = salt.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return errSecAllocate }
            return SecRandomCopyBytes(kSecRandomDefault, saltByteCount, baseAddress)
        }
        guard status == errSecSuccess else {
            throw LocalCredentialStoreError.storageUnavailable
        }
        return salt
    }

    private static func hash(password: String, salt: Data) -> Data {
        var input = salt
        input.append(contentsOf: password.utf8)
        return Data(SHA256.hash(data: input))
    }

    private static func hashesMatch(_ candidate: Data, _ expected: Data) -> Bool {
        guard candidate.count == expected.count else { return false }
        return zip(candidate, expected).reduce(UInt8.zero) { result, bytes in
            result | (bytes.0 ^ bytes.1)
        } == 0
    }
}

private struct StoredCredentials: Codable {
    let displayName: String
    let salt: String
    let passwordHash: String
}
