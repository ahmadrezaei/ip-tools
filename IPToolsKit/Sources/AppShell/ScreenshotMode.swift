// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

#if DEBUG
import Foundation
import RIPEstat
import SharedUI

/// DEBUG-only launch-argument driver for App Store screenshots (no taps needed):
/// `-screenshotTool ping|traceroute|bgp|whois -screenshotTarget <text> [-screenshotExpandHeader YES] [-screenshotPingCount <n>]`
struct ScreenshotMode: Equatable {
    var tool: Tool
    var target: String?
    var expandHeader: Bool
    var pingCount: Int?

    /// `nil` unless `-screenshotTool` names a valid tool.
    init?(arguments: [String]) {
        func value(_ flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), arguments.indices.contains(i + 1) else { return nil }
            return arguments[i + 1]
        }
        guard let name = value("-screenshotTool") else { return nil }
        switch name.lowercased() {
        case "ping": tool = .ping
        case "traceroute", "trace": tool = .traceroute
        case "bgp": tool = .bgp
        case "whois": tool = .whois
        default: return nil
        }
        target = value("-screenshotTarget").flatMap { $0.isEmpty ? nil : $0 }
        expandHeader = ["YES", "TRUE", "1"].contains(value("-screenshotExpandHeader")?.uppercased() ?? "")
        pingCount = value("-screenshotPingCount").flatMap(Int.init).flatMap { $0 > 0 ? $0 : nil }
    }

    static var current: ScreenshotMode? { ScreenshotMode(arguments: ProcessInfo.processInfo.arguments) }

    /// Throwaway defaults so screenshot runs neither read nor wipe the user's recents/settings.
    static func isolatedDefaults() -> UserDefaults {
        let name = "com.ahmadrezaei.iptools.screenshot"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @MainActor func apply(to env: AppEnvironment) {
        if let pingCount { env.settings.ping.count = pingCount }
        if expandHeader { env.bgp.headerExpanded = true }
        env.router.open(tool, target: target ?? "", autostart: target != nil)
    }
}

/// Wraps the live RIPEstat client for screenshot runs. "What's my IP" answers are fixed (the RIPE NCC
/// addresses), so a screenshot never shows, and never asks for, the real public address. Everything else
/// is forwarded.
struct ScreenshotMyIPAPI: RIPEstatAPI {
    static let v4 = "193.0.6.139"
    static let v6 = "2001:67c:2e8:22::c100:696"

    let base: any RIPEstatAPI

    func whatsMyIP() async throws -> WhatsMyIP { WhatsMyIP(ip: Self.v4) }

    func whatsMyIP(over version: IPVersion) async throws -> WhatsMyIP {
        WhatsMyIP(ip: version == .v4 ? Self.v4 : Self.v6)
    }

    func networkInfo(_ ip: String) async throws -> NetworkInfo { try await base.networkInfo(ip) }
    func prefixOverview(_ prefix: String) async throws -> PrefixOverview { try await base.prefixOverview(prefix) }
    func lookingGlass(_ resource: String) async throws -> LookingGlass { try await base.lookingGlass(resource) }
    func asOverview(_ asn: UInt32) async throws -> ASOverview { try await base.asOverview(asn) }
    func asNames(_ asns: [UInt32]) async throws -> [UInt32: String] { try await base.asNames(asns) }
    func announcedPrefixes(_ asn: UInt32) async throws -> [String] { try await base.announcedPrefixes(asn) }
    func routingStatus(_ prefix: String) async throws -> RoutingStatus { try await base.routingStatus(prefix) }
    func whois(_ resource: String) async throws -> WhoisResponse { try await base.whois(resource) }
    func abuseContacts(_ resource: String) async throws -> AbuseContacts { try await base.abuseContacts(resource) }
    func registeredCountry(_ resource: String) async throws -> String? { try await base.registeredCountry(resource) }
    func geolocation(_ ip: String) async throws -> GeoLocation? { try await base.geolocation(ip) }
}
#endif
