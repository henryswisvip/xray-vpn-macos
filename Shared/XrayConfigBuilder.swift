import Foundation

enum XrayConfigBuilder {
    static func makeConfig(for endpoint: TunnelEndpoint) throws -> String {
        let serverName = endpoint.sni.isEmpty ? endpoint.address : endpoint.sni
        let wsPath = normalizedWSPath(endpoint.wsPath)
        let wsHost = endpoint.wsHost.trimmingCharacters(in: .whitespacesAndNewlines)

        var wsSettings: [String: Any] = [
            "path": wsPath
        ]
        if !wsHost.isEmpty {
            wsSettings["headers"] = ["Host": wsHost]
        }

        var streamSettings: [String: Any] = [
            "network": "ws",
            "security": endpoint.useTLS ? "tls" : "none",
            "wsSettings": wsSettings
        ]
        if endpoint.useTLS {
            streamSettings["tlsSettings"] = [
                "serverName": serverName,
                "allowInsecure": endpoint.allowInsecure
            ]
        }

        let config: [String: Any] = [
            "log": [
                "loglevel": "warning"
            ],
            "inbounds": [
                [
                    "tag": "local-socks",
                    "listen": "127.0.0.1",
                    "port": endpoint.socksPort,
                    "protocol": "socks",
                    "settings": [
                        "udp": true
                    ]
                ]
            ],
            "outbounds": [
                [
                    "tag": "proxy",
                    "protocol": "vmess",
                    "settings": [
                        "vnext": [
                            [
                                "address": endpoint.address,
                                "port": endpoint.port,
                                "users": [
                                    [
                                        "id": endpoint.userID,
                                        "alterId": 0,
                                        "security": "auto"
                                    ]
                                ]
                            ]
                        ]
                    ],
                    "streamSettings": streamSettings
                ],
                [
                    "tag": "direct",
                    "protocol": "freedom"
                ],
                [
                    "tag": "block",
                    "protocol": "blackhole"
                ]
            ],
            "routing": [
                "domainStrategy": "AsIs",
                "rules": [
                    [
                        "type": "field",
                        "protocol": ["bittorrent"],
                        "outboundTag": "block"
                    ]
                ]
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted])
        guard let json = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: "XrayConfigBuilder",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Could not encode Xray JSON config"]
            )
        }

        return json
    }

    private static func normalizedWSPath(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "/"
        }
        return trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
    }
}
