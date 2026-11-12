import Foundation
import Security

/// Where a connection lives on this phone, in three places on purpose:
///
/// - the device token in the Keychain, readable after the first unlock and
///   only on this device (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`):
///   never in the settings, never in a backup file, never synced;
/// - the company's name and address and the person (`ConnectAccount`) in this
///   device's own preferences (`UserDefaults`), not the settings that iCloud
///   carries to the user's other devices and the backup file holds;
/// - the queue, the cursor and who is who (`ConnectState`) in a file in
///   Application Support, kept out of the device's iCloud backup.
///
/// A UI test run keeps all three in memory.
@MainActor
protocol ConnectStorage: AnyObject {
    var token: String? { get set }
    var account: ConnectAccount? { get set }
    var state: ConnectState { get set }
    /// The folder a sheet's PDF waits in until it is uploaded.
    var filesFolder: URL { get }
}

@MainActor
final class DeviceConnectStorage: ConnectStorage {
    private let defaults: UserDefaults
    private static let accountKey = "hours.connect.account"
    private static let keychainService = "app.zeitkonto.connect"
    private static let keychainAccount = "device-token"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var token: String? {
        get { Self.readToken() }
        set { Self.writeToken(newValue) }
    }

    var account: ConnectAccount? {
        get { defaults.data(forKey: Self.accountKey).flatMap { try? JSONDecoder().decode(ConnectAccount.self, from: $0) } }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Self.accountKey)
            } else {
                defaults.removeObject(forKey: Self.accountKey)
            }
        }
    }

    var state: ConnectState {
        get {
            guard let data = try? Data(contentsOf: stateFile) else { return ConnectState() }
            return (try? JSONDecoder().decode(ConnectState.self, from: data)) ?? ConnectState()
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            try? data.write(to: stateFile, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            Self.excludeFromBackup(folder)
        }
    }

    var filesFolder: URL {
        let url = folder.appendingPathComponent("Files", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var folder: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let url = base.appendingPathComponent("Connect", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var stateFile: URL { folder.appendingPathComponent("state.json") }

    private static func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    // MARK: - Keychain

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
    }

    private static func readToken() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeToken(_ token: String?) {
        SecItemDelete(query as CFDictionary)
        guard let token, let data = token.data(using: .utf8) else { return }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        // Never synced through iCloud Keychain.
        item[kSecAttrSynchronizable as String] = kCFBooleanFalse
        SecItemAdd(item as CFDictionary, nil)
    }
}

/// A UI test run's connection: in memory, gone at the next launch.
@MainActor
final class MemoryConnectStorage: ConnectStorage {
    var token: String?
    var account: ConnectAccount?
    var state = ConnectState()
    let filesFolder: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("connect-ui-tests", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
}

/// The device API over URLSession: no cookies, no cache, a short timeout.
struct URLSessionConnectTransport: ConnectTransport {
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    func send(_ request: ConnectHTTPRequest) async throws -> ConnectHTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        urlRequest.httpBody = request.body
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw ConnectError.unreadable }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String { headers[key] = "\(value)" }
        }
        return ConnectHTTPResponse(status: http.statusCode, headers: headers, body: data)
    }
}
