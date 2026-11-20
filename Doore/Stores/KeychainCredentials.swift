import Foundation
import WooshKit
#if canImport(Security)
import Security
#endif

enum KeychainCredentials {
    static func read(_ endpoint: Endpoint) -> BasicCredential? {
        guard endpoint.isValid else { return nil }
        #if canImport(Security)
        let query: [CFString: Any] = [
            kSecClass: kSecClassInternetPassword,
            kSecAttrServer: endpoint.host,
            kSecAttrPort: endpoint.port,
            kSecAttrProtocol: kSecAttrProtocolHTTP,
            kSecAttrAuthenticationType: kSecAttrAuthenticationTypeHTTPBasic,
            kSecReturnAttributes: true,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let attributes = result as? [CFString: Any],
              let user = attributes[kSecAttrAccount] as? String,
              let data = attributes[kSecValueData] as? Data,
              let password = String(data: data, encoding: .utf8)
        else { return nil }
        return BasicCredential(user: user, password: password)
        #else
        return nil
        #endif
    }
}
