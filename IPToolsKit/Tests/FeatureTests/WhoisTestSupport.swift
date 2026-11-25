// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore
import RIPEstat
import SharedUI
@testable import WhoisFeature

/// RIPEstat stand-in for the Whois tests. It records every call and answers from the dictionaries; anything
/// without an entry fails with `RIPEstatError.offline`. Configure it before use.
final class WhoisFakeAPI: RIPEstatAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    var whoisByResource: [String: WhoisResponse] = [:]
    var networkByIP: [String: NetworkInfo] = [:]
    var overviewByPrefix: [String: PrefixOverview] = [:]
    var asOverviewByNumber: [UInt32: ASOverview] = [:]
    var abuseByResource: [String: AbuseContacts] = [:]
    var countryByResource: [String: String] = [:]
    var geoByIP: [String: GeoLocation] = [:]
    var holders: [UInt32: String] = [:]
    var publicIP: [IPVersion: Result<String, any Error>] = [:]
    var plainPublicIP: String?
    var failing: Set<String> = []          // "whois", "network-info", "as-names" ... fail with a given error
    var failureError: any Error = RIPEstatError.http(status: 502)
    var delay: Duration?

    var calls: [String] { lock.withLock { recorded } }
    func calls(_ prefix: String) -> [String] { calls.filter { $0.hasPrefix(prefix) } }

    private func record(_ call: String) async throws {
        lock.withLock { recorded.append(call) }
        if let delay { try await Task.sleep(for: delay) }
        let name = String(call.split(separator: ":").first ?? "")
        if failing.contains(name) || failing.contains(call) { throw failureError }
    }

    func whois(_ resource: String) async throws -> WhoisResponse {
        try await record("whois:\(resource)")
        guard let response = whoisByResource[resource] else { throw RIPEstatError.offline }
        return response
    }

    func networkInfo(_ ip: String) async throws -> NetworkInfo {
        try await record("network-info:\(ip)")
        guard let info = networkByIP[ip] else { throw RIPEstatError.offline }
        return info
    }

    func prefixOverview(_ prefix: String) async throws -> PrefixOverview {
        try await record("prefix-overview:\(prefix)")
        guard let overview = overviewByPrefix[prefix] else { throw RIPEstatError.offline }
        return overview
    }

    func asOverview(_ asn: UInt32) async throws -> ASOverview {
        try await record("as-overview:AS\(asn)")
        guard let overview = asOverviewByNumber[asn] else { throw RIPEstatError.offline }
        return overview
    }

    func abuseContacts(_ resource: String) async throws -> AbuseContacts {
        try await record("abuse:\(resource)")
        guard let abuse = abuseByResource[resource] else { throw RIPEstatError.offline }
        return abuse
    }

    func registeredCountry(_ resource: String) async throws -> String? {
        try await record("country:\(resource)")
        return countryByResource[resource]
    }

    func geolocation(_ ip: String) async throws -> GeoLocation? {
        try await record("geo:\(ip)")
        return geoByIP[ip]
    }

    func asNames(_ asns: [UInt32]) async throws -> [UInt32: String] {
        try await record("as-names:" + asns.map(String.init).joined(separator: ","))
        return holders.filter { asns.contains($0.key) }
    }

    func whatsMyIP(over version: IPVersion) async throws -> WhatsMyIP {
        try await record("my-ip:\(version.rawValue)")
        switch publicIP[version] {
        case let .success(ip)?: return WhatsMyIP(ip: ip)
        case let .failure(error)?: throw error
        case nil: throw RIPEstatError.offline
        }
    }

    func whatsMyIP() async throws -> WhatsMyIP {
        try await record("my-ip:plain")
        guard let plainPublicIP else { throw RIPEstatError.offline }
        return WhatsMyIP(ip: plainPublicIP)
    }

    func lookingGlass(_ resource: String) async throws -> LookingGlass { throw RIPEstatError.offline }
    func announcedPrefixes(_ asn: UInt32) async throws -> [String] { throw RIPEstatError.offline }
    func routingStatus(_ prefix: String) async throws -> RoutingStatus { throw RIPEstatError.offline }
}

// MARK: Builders

func whoisRecord(_ pairs: [(String, String)], id: Int = 0) -> WhoisRecord {
    WhoisRecord(id: id, fields: pairs.map { WhoisField(key: $0.0, value: $0.1, link: nil) })
}

func whoisResponse(_ resource: String, records: [WhoisRecord], irr: [WhoisRecord] = [], authorities: [String] = [],
                   queryTime: Date? = nil) -> WhoisResponse {
    WhoisResponse(resource: resource, authorities: authorities, records: records, irrRecords: irr, warnings: [],
                  queryTime: queryTime)
}

func noMatchResponse(_ resource: String) -> WhoisResponse {
    whoisResponse(resource, records: [whoisRecord([("No match found for + ! 2001", "4860:4860::8888.")])])
}

func objectResponse(_ resource: String, irr: [WhoisRecord] = []) -> WhoisResponse {
    whoisResponse(resource, records: [whoisRecord([("NetRange", "8.8.8.0 - 8.8.8.255"), ("NetName", "GOGL")])], irr: irr,
                  authorities: ["arin"])
}

func ip(_ text: String) -> IPAddress { IPAddress(text)! }

/// Stand-ins for D's pure functions, so loader and model run on their own.
extension WhoisSeams {
    static let stub = WhoisSeams(
        summarize: { query, subject, inputs in
            var notes: [WhoisSummary.Note] = inputs.failed.sorted { "\($0)" < "\($1)" }.map { .missing($0) }
            if inputs.network?.originASNs.isEmpty == true { notes.append(.notAnnounced) }
            let origins = inputs.network?.originASNs ?? inputs.prefixOverview?.origins.map(\.asn) ?? []
            return WhoisSummary(
                subject: subject, query: query, cidrs: inputs.whois?.records.first?.fields.first.map { [$0.value] } ?? [],
                name: inputs.whois?.records.first?.fields.dropFirst().first?.value, country: inputs.country,
                routedPrefix: inputs.network?.prefix ?? inputs.prefixOverview?.resource, originASNs: origins,
                abuseEmails: inputs.abuse?.emails ?? [], notes: notes)
        },
        isNoMatch: { $0.records.allSatisfy { $0.primaryKey.hasPrefix("No match found") } },
        isEmpty: { $0.cidrs.isEmpty && $0.routedPrefix == nil && $0.country == nil && $0.abuseEmails.isEmpty })
}

extension WhoisRules {
    /// 10/8 and 192.168/16 are "Private use", ::ffff:0:0/96 is IPv4-mapped, AS64512-65534 is private.
    static let stub = WhoisRules(
        specialRange: { address, length in
            let b = address.bytes
            if address.family == .v4, b[0] == 10 || (b[0] == 192 && b[1] == 168) {
                return SpecialPurposeRange(network: address, length: min(length, b[0] == 10 ? 8 : 16), kind: .privateUse,
                                           name: "Private use", rfc: "RFC 1918")
            }
            if address.family == .v6, b.prefix(10).allSatisfy({ $0 == 0 }), b[10] == 0xFF, b[11] == 0xFF {
                return SpecialPurposeRange(network: address, length: 96, kind: .ipv4Mapped, name: "IPv4-mapped", rfc: "RFC 4291")
            }
            return nil
        },
        reservedASN: { (64512...65534).contains($0) ? ReservedASN(range: 64512...65534, name: "Private use", rfc: "RFC 6996") : nil },
        embeddedIPv4: { IPAddress(bytes: Array($0.bytes.suffix(4))) },
        masked: { address, length in
            var bytes = address.bytes
            for index in bytes.indices {
                let bits = max(0, min(8, length - index * 8))
                bytes[index] &= UInt8(truncatingIfNeeded: 0xFF << (8 - bits))
            }
            return IPAddress(bytes: bytes)!
        })
}

/// Network conditions a test can change after the model is built.
@MainActor final class NetworkBox {
    var state = WhoisNetworkState()
}

@MainActor func makeWhoisModel(api: WhoisFakeAPI, recents: RecentsStore? = nil, router: AppRouter = AppRouter(selectedTool: .whois),
                               network: NetworkBox = NetworkBox(),
                               resolve: @escaping @Sendable (String, AddressPreference) async throws -> ResolvedTarget = { host, _ in
                                   throw NetError.resolutionFailed(host: host, reason: "no")
                               }) -> WhoisModel {
    let model = WhoisModel(api: api, recents: recents ?? makeRecents(), router: router, settings: makeSettings(),
                           resolve: resolve, reverseName: { _ in "rev.example" }, localAddresses: { [] })
    model.rules = .stub
    model.seams = .stub
    model.networkDebounce = .milliseconds(20)
    model.networkRecheckInterval = 0
    model.networkState = { network.state }
    return model
}

func sampleNetwork(_ api: WhoisFakeAPI, ip address: String = "8.8.8.8", prefix: String = "8.8.8.0/24", origins: [UInt32] = [15169]) {
    api.networkByIP[address] = NetworkInfo(prefix: prefix, originASNs: origins)
    api.whoisByResource[address] = objectResponse(address)
    api.abuseByResource[address] = AbuseContacts(emails: ["abuse@example.net"], authoritativeRIR: "arin")
    api.countryByResource[address] = "US"
    api.holders[15169] = "GOOGLE - Google LLC"
}
