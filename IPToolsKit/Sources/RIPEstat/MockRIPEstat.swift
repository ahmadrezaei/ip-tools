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
/// `routing-status_<prefix>`, `whois_<resource>`, `abuse-contact-finder_<resource>`, `rir-stats-country_<resource>`,
/// `maxmind-geo-lite_<ip>`, `whats-my-ip_v4` / `whats-my-ip_v6`; `/` and `:` in a resource become `-`.
/// A `<name>_error` fixture is served (and fails the same way the live call does) when the plain one is missing.
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

    public func whatsMyIP(over version: IPVersion) async throws -> WhatsMyIP {
        try await pause()
        let name = "whats-my-ip_\(version.rawValue)"
        if let data = fixtureData(name) { return try RIPEstatParsing.whatsMyIP(data) }
        return WhatsMyIP(ip: version == .v4 ? "193.0.6.139" : "2001:67c:2e8:22::c100:696")
    }

    public func whois(_ resource: String) async throws -> WhoisResponse {
        try await pause()
        if let data = fixtureData("whois_\(Self.fixtureKey(resource))") ?? fixtureData("whois_\(Self.fixtureKey(resource))_error") {
            return try WhoisParsing.whois(data, resource: resource)
        }
        return Self.sampleWhois(resource)
    }

    public func abuseContacts(_ resource: String) async throws -> AbuseContacts {
        try await pause()
        let key = Self.fixtureKey(resource)
        if let data = fixtureData("abuse-contact-finder_\(key)") ?? fixtureData("abuse-contact-finder_\(key)_error") {
            return try WhoisParsing.abuse(data)
        }
        return AbuseContacts(emails: ["abuse@example.net"], authoritativeRIR: "ripe")
    }

    public func registeredCountry(_ resource: String) async throws -> String? {
        try await pause()
        if let data = fixtureData("rir-stats-country_\(Self.fixtureKey(resource))") { return try WhoisParsing.country(data) }
        return "NL"
    }

    public func geolocation(_ ip: String) async throws -> GeoLocation? {
        try await pause()
        if let data = fixtureData("maxmind-geo-lite_\(Self.fixtureKey(ip))") { return try WhoisParsing.geolocation(data) }
        return GeoLocation(country: "NL", city: "Amsterdam", coveredFraction: 1)
    }

    /// Built-in answer for resources without a fixture: one RIPE-style object around the sample prefix.
    static func sampleWhois(_ resource: String) -> WhoisResponse {
        func record(_ id: Int, _ pairs: [(String, String)]) -> WhoisRecord {
            WhoisRecord(id: id, fields: pairs.map { WhoisField(key: $0.0, value: $0.1, link: nil) })
        }
        let object: WhoisRecord
        if resource.uppercased().hasPrefix("AS") {
            object = record(0, [("aut-num", String(resource.dropFirst(2))), ("as-name", "EXAMPLE-AS"),
                                ("descr", "Example Network"), ("country", "NL"), ("source", "RIPE")])
        } else {
            let prefix = resource.contains("/") ? resource : (resource.hasPrefix("8.8.") ? "8.8.8.0/24" : "1.1.1.0/24")
            object = record(0, [("inetnum", prefix), ("netname", "EXAMPLE-NET"), ("descr", "Example Network"),
                                ("country", "NL"), ("status", "ASSIGNED PA"), ("org", "ORG-EX1-RIPE"),
                                ("source", "RIPE")])
        }
        return WhoisResponse(resource: resource, authorities: ["ripe"], records: [object], irrRecords: [],
                             warnings: [], queryTime: nil)
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
