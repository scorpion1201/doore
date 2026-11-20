import Foundation
import SwiftProtobuf

public enum WiFiOperation: Sendable {
    case list
    case hotspot(enabled: Bool)
    case add(ssid: String, password: String, hidden: Bool, connectNow: Bool)

    public var type: String { Woosh_Robot_RobotWiFi.protoMessageName }

    public func allows(_ snapshot: RobotSnapshot) -> Bool {
        switch self {
        case .list: return true
        case .hotspot(let enabled): return snapshot.wifiMode == (enabled ? 3 : 1)
        case .add(let ssid, let password, _, _):
            return snapshot.wifiMode != 2 && snapshot.wifiMode != 4
                && !ssid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
        }
    }

    public var body: Data {
        get throws {
            var message = Woosh_Robot_RobotWiFi()
            switch self {
            case .list:
                message.order = .kWiFiList
            case .hotspot(let enabled):
                message.order = .kHotspot
                message.enable = enabled
            case .add(let ssid, let password, let hidden, let connectNow):
                // The public RobotWiFi example specifies this inner JSON for WPA-PSK with DHCP.
                // https://wooshrobot.apifox.cn/api-69850428
                message.order = .kAdd
                message.isConnectNow = connectNow
                message.content = try JSONSerialization.data(withJSONObject: [
                    "essid": ssid, "auth_method": "wpa-psk", "hidden": hidden,
                    "ip4_settings": ["method": "auto"], "wifi_security": ["psk": password]
                ])
            }
            var options = JSONEncodingOptions()
            options.alwaysPrintEnumsAsInts = true
            return try message.jsonUTF8Data(options: options)
        }
    }
}

/// Read the documented profile fields when the robot actually includes them in list_json.
/// Other firmware-specific fields and any stored credentials stay out of the display model.
public struct WiFiNetworkSummary: Identifiable, Equatable, Sendable {
    public let ssid: String
    public let security: String?
    public let ipMethod: String?
    public var id: String { ssid }

    public static func reported(in data: Data?) -> [Self] {
        guard let data, let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var networks: [Self] = []
        var names: Set<String> = []
        func visit(_ value: Any) {
            if let list = value as? [Any] {
                list.forEach(visit)
            } else if let profile = value as? [String: Any] {
                if let name = profile["essid"] as? String, !name.isEmpty {
                    guard names.insert(name).inserted else { return }
                    let ip = profile["ip4_settings"] as? [String: Any]
                    networks.append(Self(ssid: name, security: profile["auth_method"] as? String, ipMethod: ip?["method"] as? String))
                } else {
                    for key in profile.keys.sorted() where key != "wifi_security" {
                        if let child = profile[key] { visit(child) }
                    }
                }
            }
        }
        visit(root)
        return networks
    }
}
