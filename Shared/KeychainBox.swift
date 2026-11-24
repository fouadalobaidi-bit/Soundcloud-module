import Foundation
#if canImport(Security)
import Security
#endif

/// Where SharedStore keeps its copies: named blobs, each with a time stamp.
@MainActor
protocol BlobStore: AnyObject {
    /// The app and the keyboard see the same blobs.
    var isShared: Bool { get }
    /// Blobs can be kept at all (they survive reinstalling the app).
    var isAvailable: Bool { get }
    func stamp(_ name: String) -> Double?
    func read(_ name: String) -> (data: Data, stamp: Double)?
    @discardableResult func write(_ name: String, data: Data, stamp: Double) -> Bool
}

#if canImport(Security)
/// Blobs in the iPhone's keychain. Both the app and the keyboard declare the keychain group
/// "HARFTEAMID.com.fezo.harf.shared"; SideStore swaps the part before the first dot for the team of the
/// Apple ID that installs it, so both end up in "<team>.com.fezo.harf.shared". Keychain items stay when the
/// app is reinstalled or updated, so settings and learned words come back by themselves.
@MainActor
final class KeychainBox: BlobStore {
    static let service = "com.fezo.harf.store"
    static let sharedSuffix = ".com.fezo.harf.shared"

    private(set) var accessGroup: String?
    private(set) var isShared = false
    private(set) var isAvailable = false

    init() {
        resolveGroup()
    }

    private func query(_ account: String, group: String?) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account
        ]
        if let group { q[kSecAttrAccessGroup as String] = group }
        return q
    }

    /// Finds out which keychain group this install can use, by adding a throwaway item.
    private func resolveGroup() {
        let probe = "probe"
        SecItemDelete(query(probe, group: nil) as CFDictionary)
        var add = query(probe, group: nil)
        add[kSecValueData as String] = Data([1])
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        add[kSecReturnAttributes as String] = true
        var result: CFTypeRef?
        guard SecItemAdd(add as CFDictionary, &result) == errSecSuccess else { return }
        isAvailable = true
        let defaultGroup = (result as? [String: Any])?[kSecAttrAccessGroup as String] as? String
        SecItemDelete(query(probe, group: defaultGroup) as CFDictionary)
        guard let defaultGroup else { return }

        // Our declared group comes first, so it is the default when the installer kept it.
        if defaultGroup.hasSuffix(Self.sharedSuffix) {
            accessGroup = defaultGroup
            isShared = true
            return
        }
        // A team-wide keychain entitlement (TEAM.*) also lets us name the shared group directly.
        if let dot = defaultGroup.firstIndex(of: ".") {
            let candidate = String(defaultGroup[..<dot]) + Self.sharedSuffix
            var test = query(probe, group: candidate)
            test[kSecValueData as String] = Data([1])
            test[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            if SecItemAdd(test as CFDictionary, nil) == errSecSuccess {
                SecItemDelete(query(probe, group: candidate) as CFDictionary)
                accessGroup = candidate
                isShared = true
                return
            }
        }
        // Not shared with the app, but still kept across reinstalls of the same app.
        accessGroup = defaultGroup
    }

    private func attributes(_ name: String, withData: Bool) -> [String: Any]? {
        guard isAvailable else { return nil }
        var q = query(name, group: accessGroup)
        q[kSecReturnAttributes as String] = true
        if withData { q[kSecReturnData as String] = true }
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? [String: Any]
    }

    private static func stamp(from attributes: [String: Any]) -> Double? {
        guard let generic = attributes[kSecAttrGeneric as String] as? Data,
              let text = String(data: generic, encoding: .utf8) else { return nil }
        return Double(text)
    }

    func stamp(_ name: String) -> Double? {
        attributes(name, withData: false).flatMap(Self.stamp(from:))
    }

    func read(_ name: String) -> (data: Data, stamp: Double)? {
        guard let attrs = attributes(name, withData: true),
              let data = attrs[kSecValueData as String] as? Data,
              let stamp = Self.stamp(from: attrs) else { return nil }
        return (data, stamp)
    }

    @discardableResult
    func write(_ name: String, data: Data, stamp: Double) -> Bool {
        guard isAvailable else { return false }
        let q = query(name, group: accessGroup)
        let values: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrGeneric as String: Data(String(stamp).utf8)
        ]
        var status = SecItemUpdate(q as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var add = q.merging(values) { $1 }
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(add as CFDictionary, nil)
        }
        return status == errSecSuccess
    }
}
#endif

/// In memory only: for platforms without a keychain (and for tests).
@MainActor
final class MemoryBox: BlobStore {
    var isShared = true
    var isAvailable = true
    private var items: [String: (data: Data, stamp: Double)] = [:]

    init() {}

    func stamp(_ name: String) -> Double? { items[name]?.stamp }
    func read(_ name: String) -> (data: Data, stamp: Double)? { items[name] }

    @discardableResult
    func write(_ name: String, data: Data, stamp: Double) -> Bool {
        guard isAvailable else { return false }
        items[name] = (data, stamp)
        return true
    }
}
