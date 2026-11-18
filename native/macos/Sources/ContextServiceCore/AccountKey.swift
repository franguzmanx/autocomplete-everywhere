import Foundation
import CryptoKit
import Security

public enum AccountKey {
    public static func directoryName(_ account: String) -> String { SHA256.hash(data:Data(account.utf8)).map { String(format:"%02x",$0) }.joined() }
    public static func load(_ account: String) throws -> Data {
        guard !account.isEmpty, account.utf8.count <= 1024 else { throw StoreError.invalidInput }
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"com.autocompletion.context.database",kSecAttrAccount as String:directoryName(account)]
        var request = query; request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary,&result)
        if status == errSecSuccess, let data = result as? Data, data.count == 32 { return data }
        guard status == errSecItemNotFound else { throw StoreError.keychainUnavailable }
        var bytes = [UInt8](repeating:0,count:32)
        guard SecRandomCopyBytes(kSecRandomDefault,bytes.count,&bytes) == errSecSuccess else { throw StoreError.keychainUnavailable }
        let key = Data(bytes)
        var insertion = query; insertion[kSecValueData as String] = key
        insertion[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(insertion as CFDictionary,nil) == errSecSuccess else { throw StoreError.keychainUnavailable }
        return key
    }
}
