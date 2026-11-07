// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation

/// Offline `RIPEstatAPI` for previews and tests. It serves built-in sample data modelled on `1.1.1.0/24`
/// (AS13335 behind a handful of transit networks), so it works with any bundle. `fixtureBundle` is kept
/// for the real fixture-backed implementation (the data agent may switch to decoding `Fixtures/*.json`).
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

    public func networkInfo(_ ip: String) async throws -> NetworkInfo {
        try await pause()
        if ip.hasPrefix("10.") || ip.hasPrefix("192.168.") { return NetworkInfo(prefix: nil, originASNs: []) }
        if ip.hasPrefix("1.1.1.") { return NetworkInfo(prefix: "1.1.1.0/24", originASNs: [13335]) }
        return NetworkInfo(prefix: "8.8.8.0/24", originASNs: [15169])
    }

    public func prefixOverview(_ prefix: String) async throws -> PrefixOverview {
        try await pause()
        let asn: UInt32 = prefix.hasPrefix("8.8.") ? 15169 : 13335
        return PrefixOverview(resource: prefix, announced: !prefix.hasPrefix("10."),
                              origins: [ASHolder(asn: asn, holder: Self.sampleNames[asn] ?? "AS\(asn)")])
    }

    public func lookingGlass(_ resource: String) async throws -> LookingGlass {
        try await pause()
        guard !resource.hasPrefix("10.") else { return LookingGlass(collectors: [], routes: [], latestTime: nil) }
        let prefix = resource.contains("/") ? resource : "1.1.1.0/24"
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

    public func asOverview(_ asn: UInt32) async throws -> ASOverview {
        try await pause()
        return ASOverview(asn: asn, holder: Self.sampleNames[asn], announced: true)
    }

    public func asNames(_ asns: [UInt32]) async throws -> [UInt32: String] {
        try await pause()
        var result: [UInt32: String] = [:]
        for asn in asns { result[asn] = Self.sampleNames[asn] ?? "AS\(asn) Example Network" }
        return result
    }

    public func announcedPrefixes(_ asn: UInt32) async throws -> [String] {
        try await pause()
        return (0..<24).map { "104.16.\($0).0/24" } + ["1.1.1.0/24", "1.0.0.0/24", "2606:4700::/32"]
    }

    public func routingStatus(_ prefix: String) async throws -> RoutingStatus {
        try await pause()
        return RoutingStatus(v4: .init(seeing: 319, total: 319), v6: nil, origins: [13335])
    }
}
