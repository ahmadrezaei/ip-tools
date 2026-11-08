// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation

/// Offline `RIPEstatAPI` for previews and tests. It decodes the real captured responses in `Fixtures/*.json`
/// (looked up in `fixtureBundle`, in a `Fixtures` subdirectory or flat) with the same parsing as the live client.
/// Anything without a fixture, or any bundle without fixtures, falls back to built-in sample data modelled on
/// `1.1.1.0/24` (AS13335 behind a handful of transit networks), so it works with any bundle.
///
/// Fixture names: `network-info_<ip>`, `prefix-overview_<prefix>`, `bgp-state_<prefix>` (preferred) or
/// `looking-glass_<prefix>`, `as-overview_AS<n>`, `as-names_*` (all merged), `announced-prefixes_AS<n>`,
/// `routing-status_<prefix>`; `/` and `:` in a resource become `-`.
public struct MockRIPEstat: RIPEstatAPI {
    public let fixtureBundle: Bundle
    private let latency: Duration

    public init(fixtureBundle: Bundle) {
        self.init(fixtureBundle: fixtureBundle, latency: .milliseconds(150))
    }

    public init(fixtureBundle: Bundle, latency: Duration) {
        self.fixtureBundle = fixtureBundle
        self.latency = latency
    }

    public static let sampleNames: [UInt32: String] = [
        13335: "CLOUDFLARENET - Cloudflare, Inc.",
        6939: "HURRICANE - Hurricane Electric LLC",
        174: "COGENT-174 - Cogent Communications, LLC",
        3356: "LEVEL3 - Level 3 Parent, LLC",
        1299: "TWELVE99 Arelion Sweden AB",
        2914: "NTT-DATA-2914 - NTT America, Inc.",
        3257: "GTT-BACKBONE GTT Communications Inc.",
        6453: "AS6453 - TATA COMMUNICATIONS (AMERICA) INC",
        1273: "CWVodafone Group PLC",
        12389: "ROSTELECOM-AS PJSC Rostelecom",
        3320: "DTAG Deutsche Telekom AG",
        7018: "ATT-INTERNET4 - AT&T Services, Inc.",
        20940: "AKAMAI-ASN1 Akamai International B.V.",
        15169: "GOOGLE - Google LLC",
    ]

    private static let transit: [UInt32] = [174, 3356, 1299, 2914, 3257, 6453, 6939, 1273, 3320, 7018]
    private static let edges: [UInt32] = [12389, 20940, 15169, 1273, 3320, 7018, 64500, 64501, 64502, 64503]

    private static let collectors = (1...8).map {
        LookingGlass.Collector(id: String(format: "RRC%02d", $0), location: ["Amsterdam, NL", "London, GB", "Paris, FR",
            "Frankfurt, DE", "Vienna, AT", "Milan, IT", "Stockholm, SE", "Zurich, CH"][$0 - 1])
    }

    private func pause() async throws { try await Task.sleep(for: latency) }

    // MARK: Fixture access

    static func fixtureKey(_ resource: String) -> String {
        resource.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }

    private func fixtureURL(_ name: String) -> URL? {
        fixtureBundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? fixtureBundle.url(forResource: name, withExtension: "json")
    }

    private func fixtureData(_ name: String) -> Data? {
        fixtureURL(name).flatMap { try? Data(contentsOf: $0) }
    }

    private func allNameFixtures() -> [UInt32: String] {
        var urls = fixtureBundle.urls(forResourcesWithExtension: "json", subdirectory: "Fixtures") ?? []
        urls += fixtureBundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        var merged: [UInt32: String] = [:]
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where url.lastPathComponent.hasPrefix("as-names_") {
            if let data = try? Data(contentsOf: url), let names = try? RIPEstatParsing.asNames(data) {
                merged.merge(names) { a, _ in a }
            }
        }
        return merged
    }

    private func isPrivate(_ resource: String) -> Bool {
        resource.hasPrefix("10.") || resource.hasPrefix("192.168.") || resource.lowercased().hasPrefix("fd")
    }

    // MARK: RIPEstatAPI

    public func networkInfo(_ ip: String) async throws -> NetworkInfo {
        try await pause()
        if let data = fixtureData("network-info_\(Self.fixtureKey(ip))") { return try RIPEstatParsing.networkInfo(data) }
        if isPrivate(ip) { return NetworkInfo(prefix: nil, originASNs: []) }
        if ip.hasPrefix("1.1.1.") { return NetworkInfo(prefix: "1.1.1.0/24", originASNs: [13335]) }
        return NetworkInfo(prefix: "8.8.8.0/24", originASNs: [15169])
    }

    public func prefixOverview(_ prefix: String) async throws -> PrefixOverview {
        try await pause()
        if let data = fixtureData("prefix-overview_\(Self.fixtureKey(prefix))") {
            return try RIPEstatParsing.prefixOverview(data, resource: prefix)
        }
        let asn: UInt32 = prefix.hasPrefix("8.8.") ? 15169 : 13335
        return PrefixOverview(resource: prefix, announced: !isPrivate(prefix),
                              origins: [ASHolder(asn: asn, holder: Self.sampleNames[asn] ?? "AS\(asn)")])
    }

    public func lookingGlass(_ resource: String) async throws -> LookingGlass {
        try await pause()
        var prefix = resource
        if !resource.contains("/") {
            if let data = fixtureData("network-info_\(Self.fixtureKey(resource))"),
               let info = try? RIPEstatParsing.networkInfo(data) {
                guard let p = info.prefix else { return LookingGlass(collectors: [], routes: [], latestTime: nil) }
                prefix = p
            } else if !isPrivate(resource) {
                prefix = resource.hasPrefix("8.8.") ? "8.8.8.0/24" : "1.1.1.0/24"
            }
        }
        let key = Self.fixtureKey(prefix)
        if let data = fixtureData("bgp-state_\(key)") { return try RIPEstatParsing.bgpState(data) }
        if let data = fixtureData("looking-glass_\(key)") { return try RIPEstatParsing.lookingGlass(data) }
        guard !isPrivate(prefix) else { return LookingGlass(collectors: [], routes: [], latestTime: nil) }
        let origin: UInt32 = prefix.hasPrefix("8.8.") ? 15169 : 13335
        var routes: [LookingGlass.Route] = []
        let now = Date()
        for i in 0..<48 {
            let collector = Self.collectors[i % Self.collectors.count]
            let peer = Self.edges[(i * 3) % Self.edges.count]
            let t1 = Self.transit[i % Self.transit.count]
            var path: [UInt32] = [peer]
            if i % 4 != 0 { path.append(t1) }
            if i % 7 == 0 { path.append(Self.transit[(i + 3) % Self.transit.count]) }
            path.append(origin)
            // Collapse accidental repeats from the deterministic generator.
            var cleaned: [UInt32] = []
            for asn in path where cleaned.last != asn { cleaned.append(asn) }
            routes.append(.init(collector: collector.id, peerIP: "192.0.2.\(i + 1)", prefix: prefix, asPath: cleaned,
                                hadASSet: false, rawASPath: cleaned.map(String.init).joined(separator: " "),
                                lastUpdated: now))
        }
        return LookingGlass(collectors: Self.collectors, routes: routes, latestTime: now)
    }

    public func whatsMyIP() async throws -> WhatsMyIP {
        try await pause()
        if let data = fixtureData("whats-my-ip") { return try RIPEstatParsing.whatsMyIP(data) }
        return WhatsMyIP(ip: "91.107.240.242")
    }

    public func asOverview(_ asn: UInt32) async throws -> ASOverview {
        try await pause()
        if let data = fixtureData("as-overview_AS\(asn)") { return try RIPEstatParsing.asOverview(data, asn: asn) }
        return ASOverview(asn: asn, holder: Self.sampleNames[asn], announced: true)
    }

    public func asNames(_ asns: [UInt32]) async throws -> [UInt32: String] {
        try await pause()
        let fixtures = allNameFixtures()
        var result: [UInt32: String] = [:]
        for asn in asns {
            result[asn] = fixtures[asn] ?? Self.sampleNames[asn] ?? "AS\(asn) Example Network"
        }
        return result
    }

    public func announcedPrefixes(_ asn: UInt32) async throws -> [String] {
        try await pause()
        if let data = fixtureData("announced-prefixes_AS\(asn)") { return try RIPEstatParsing.announcedPrefixes(data) }
        return (0..<24).map { "104.16.\($0).0/24" } + ["1.1.1.0/24", "1.0.0.0/24", "2606:4700::/32"]
    }

    public func routingStatus(_ prefix: String) async throws -> RoutingStatus {
        try await pause()
        if let data = fixtureData("routing-status_\(Self.fixtureKey(prefix))") { return try RIPEstatParsing.routingStatus(data) }
        return RoutingStatus(v4: .init(seeing: 319, total: 319), v6: nil, origins: [13335])
    }
}
