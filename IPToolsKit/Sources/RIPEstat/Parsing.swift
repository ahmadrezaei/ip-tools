// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation

/// Turns raw RIPEstat response bodies into the public models. Shared by the live client and `MockRIPEstat`.
enum RIPEstatParsing {
    // MARK: Envelope

    /// Checks the envelope (`status`, 429) and decodes `data`. Throws `.api`, `.rateLimited` or `.decoding`.
    static func payload<P: Decodable & Sendable>(_ data: Data, as type: P.Type) throws -> P {
        let decoder = JSONDecoder()
        let probe: EnvelopeProbe
        do { probe = try decoder.decode(EnvelopeProbe.self, from: data) } catch {
            throw RIPEstatError.decoding("Not a RIPEstat response")
        }
        if probe.statusCode == 429 { throw RIPEstatError.rateLimited }
        guard probe.status == "ok" else { throw RIPEstatError.api(messages: probe.errorTexts) }
        do {
            let envelope = try decoder.decode(Envelope<P>.self, from: data)
            guard let payload = envelope.data else { throw RIPEstatError.decoding("Missing data") }
            return payload
        } catch let error as RIPEstatError {
            throw error
        } catch {
            throw RIPEstatError.decoding(String(describing: error))
        }
    }

    // MARK: network-info

    struct NetworkInfoDTO: Decodable, Sendable {
        let prefix: String?
        let asns: [FlexASN]?
    }

    static func networkInfo(_ data: Data) throws -> NetworkInfo {
        let dto = try payload(data, as: NetworkInfoDTO.self)
        let prefix = dto.prefix?.trimmingCharacters(in: .whitespaces)
        return NetworkInfo(prefix: (prefix?.isEmpty ?? true) ? nil : prefix,
                           originASNs: (dto.asns ?? []).compactMap(\.value))
    }

    // MARK: whats-my-ip

    struct WhatsMyIPDTO: Decodable, Sendable { let ip: String? }

    static func whatsMyIP(_ data: Data) throws -> WhatsMyIP {
        let dto = try payload(data, as: WhatsMyIPDTO.self)
        guard let ip = dto.ip?.trimmingCharacters(in: .whitespacesAndNewlines), !ip.isEmpty else {
            throw RIPEstatError.decoding("Missing ip")
        }
        return WhatsMyIP(ip: ip)
    }

    // MARK: prefix-overview

    struct PrefixOverviewDTO: Decodable, Sendable {
        struct Origin: Decodable, Sendable { let asn: FlexASN?; let holder: String? }
        let announced: Bool?
        let asns: [Lossy<Origin>]?
        let resource: String?
    }

    static func prefixOverview(_ data: Data, resource: String) throws -> PrefixOverview {
        let dto = try payload(data, as: PrefixOverviewDTO.self)
        let origins = (dto.asns ?? []).compactMap { $0.value }.compactMap { origin -> ASHolder? in
            guard let asn = origin.asn?.value else { return nil }
            return ASHolder(asn: asn, holder: origin.holder ?? "")
        }
        return PrefixOverview(resource: dto.resource ?? resource, announced: dto.announced ?? false, origins: origins)
    }

    // MARK: as-overview

    struct ASOverviewDTO: Decodable, Sendable {
        let holder: String?
        let announced: Bool?
    }

    static func asOverview(_ data: Data, asn: UInt32) throws -> ASOverview {
        let dto = try payload(data, as: ASOverviewDTO.self)
        let holder = dto.holder?.trimmingCharacters(in: .whitespaces)
        return ASOverview(asn: asn, holder: (holder?.isEmpty ?? true) ? nil : holder, announced: dto.announced ?? false)
    }

    // MARK: as-names

    struct ASNamesDTO: Decodable, Sendable {
        let names: [String: String?]?
    }

    static func asNames(_ data: Data) throws -> [UInt32: String] {
        let dto = try payload(data, as: ASNamesDTO.self)
        var result: [UInt32: String] = [:]
        for (key, value) in dto.names ?? [:] {
            guard let asn = ASNText.parse(key), let name = value?.trimmingCharacters(in: .whitespaces),
                  !name.isEmpty else { continue }
            result[asn] = name
        }
        return result
    }

    // MARK: announced-prefixes

    struct AnnouncedPrefixesDTO: Decodable, Sendable {
        struct Item: Decodable, Sendable { let prefix: String? }
        let prefixes: [Lossy<Item>]?
    }

    /// IPv4 first, then shortest prefix first, then by address text. Duplicates removed.
    static func announcedPrefixes(_ data: Data) throws -> [String] {
        let dto = try payload(data, as: AnnouncedPrefixesDTO.self)
        let unique = Set((dto.prefixes ?? []).compactMap { $0.value?.prefix }.filter { !$0.isEmpty })
        func key(_ p: String) -> (Int, Int, String) {
            let length = p.split(separator: "/").last.flatMap { Int($0) } ?? 999
            return (p.contains(":") ? 1 : 0, length, p)
        }
        return unique.sorted { key($0) < key($1) }
    }

    // MARK: routing-status

    struct RoutingStatusDTO: Decodable, Sendable {
        struct Vis: Decodable, Sendable {
            let risPeersSeeing: Int?
            let totalRisPeers: Int?
            enum CodingKeys: String, CodingKey {
                case risPeersSeeing = "ris_peers_seeing"
                case totalRisPeers = "total_ris_peers"
            }
        }
        struct Visibility: Decodable, Sendable { let v4: Vis?; let v6: Vis? }
        struct Origin: Decodable, Sendable { let origin: FlexASN? }
        let visibility: Visibility?
        let origins: [Lossy<Origin>]?
    }

    static func routingStatus(_ data: Data) throws -> RoutingStatus {
        let dto = try payload(data, as: RoutingStatusDTO.self)
        func map(_ v: RoutingStatusDTO.Vis?) -> RoutingStatus.Visibility? {
            guard let total = v?.totalRisPeers, total > 0 else { return nil }
            return .init(seeing: v?.risPeersSeeing ?? 0, total: total)
        }
        return RoutingStatus(v4: map(dto.visibility?.v4), v6: map(dto.visibility?.v6),
                             origins: (dto.origins ?? []).compactMap { $0.value?.origin?.value })
    }

    // MARK: looking-glass

    struct LookingGlassDTO: Decodable, Sendable {
        struct Peer: Decodable, Sendable {
            let asPath: String?
            let prefix: String?
            let peer: String?
            let lastUpdated: String?
            enum CodingKeys: String, CodingKey {
                case asPath = "as_path"
                case prefix, peer
                case lastUpdated = "last_updated"
            }
        }
        struct RRC: Decodable, Sendable {
            let rrc: String?
            let location: String?
            let peers: [Lossy<Peer>]?
        }
        let rrcs: [Lossy<RRC>]?
        let latestTime: String?
        enum CodingKeys: String, CodingKey {
            case rrcs
            case latestTime = "latest_time"
        }
    }

    static func lookingGlass(_ data: Data) throws -> LookingGlass {
        let dto = try payload(data, as: LookingGlassDTO.self)
        var collectors: [LookingGlass.Collector] = []
        var routes: [LookingGlass.Route] = []
        for rrc in (dto.rrcs ?? []).compactMap({ $0.value }) {
            let id = (rrc.rrc ?? "").uppercased()
            collectors.append(.init(id: id, location: rrc.location ?? ""))
            for peer in (rrc.peers ?? []).compactMap({ $0.value }) {
                let raw = peer.asPath ?? ""
                let parsed = parseASPath(raw)
                routes.append(.init(collector: id, peerIP: peer.peer ?? "", prefix: peer.prefix ?? "",
                                    asPath: parsed.asns, hadASSet: parsed.hadASSet, rawASPath: raw,
                                    lastUpdated: DateParsing.parse(peer.lastUpdated)))
            }
        }
        return LookingGlass(collectors: collectors, routes: routes, latestTime: DateParsing.parse(dto.latestTime))
    }

    /// Splits a space separated AS path. `{a,b}` (AS_SET) and `(a b)` (confederation) segments are dropped and
    /// reported through `hadASSet`. Unparseable tokens are skipped.
    static func parseASPath(_ raw: String) -> (asns: [UInt32], hadASSet: Bool) {
        var asns: [UInt32] = []
        var hadSet = false
        var token = ""
        var depth = 0
        func flush() {
            if !token.isEmpty, let asn = ASNText.parse(token) { asns.append(asn) }
            token = ""
        }
        for ch in raw {
            switch ch {
            case "{", "(":
                if depth == 0 { flush(); hadSet = true }
                depth += 1
            case "}", ")":
                depth = max(0, depth - 1)
            case " ", "\t", "\n":
                if depth == 0 { flush() }
            default:
                if depth == 0 { token.append(ch) }
            }
        }
        flush()
        return (asns, hadSet)
    }

    // MARK: bgp-state (fallback for looking-glass)

    struct BGPStateDTO: Decodable, Sendable {
        struct Entry: Decodable, Sendable {
            let targetPrefix: String?
            let sourceID: String?
            let path: PathValue?
            enum CodingKeys: String, CodingKey {
                case targetPrefix = "target_prefix"
                case sourceID = "source_id"
                case path
            }
        }
        /// `path` is an array of ASNs (ints or strings); a space separated string is tolerated too.
        enum PathValue: Decodable, Sendable {
            case asns([UInt32])
            case text(String)
            init(from decoder: Decoder) throws {
                if let list = try? [FlexASN](from: decoder) {
                    self = .asns(list.compactMap(\.value))
                } else {
                    self = .text(try String(from: decoder))
                }
            }
        }
        let bgpState: [Lossy<Entry>]?
        let timestamp: String?
        enum CodingKeys: String, CodingKey {
            case bgpState = "bgp_state"
            case timestamp
        }
    }

    static func bgpState(_ data: Data) throws -> LookingGlass {
        let dto = try payload(data, as: BGPStateDTO.self)
        let stamp = DateParsing.parse(dto.timestamp)
        var routes: [LookingGlass.Route] = []
        var seen: [String] = []
        for entry in (dto.bgpState ?? []).compactMap({ $0.value }) {
            let source = entry.sourceID ?? ""
            let split = source.firstIndex(of: "-")
            let number = split.map { String(source[..<$0]) } ?? ""
            let peerIP = split.map { String(source[source.index(after: $0)...]) } ?? source
            let collector = Int(number).map { String(format: "RRC%02d", $0) } ?? (number.isEmpty ? "" : number.uppercased())
            if !seen.contains(collector) { seen.append(collector) }
            var asns: [UInt32] = []
            var hadSet = false
            var raw = ""
            switch entry.path {
            case .asns(let list)?:
                asns = list
                raw = list.map(String.init).joined(separator: " ")
            case .text(let text)?:
                raw = text
                (asns, hadSet) = parseASPath(text)
            case nil:
                break
            }
            routes.append(.init(collector: collector, peerIP: peerIP, prefix: entry.targetPrefix ?? "",
                                asPath: asns, hadASSet: hadSet, rawASPath: raw, lastUpdated: stamp))
        }
        let collectors = seen.sorted().map { LookingGlass.Collector(id: $0, location: rrcLocations[$0] ?? "") }
        return LookingGlass(collectors: collectors, routes: routes, latestTime: stamp)
    }

    /// RIS route collector sites (bgp-state does not report them).
    static let rrcLocations: [String: String] = [
        "RRC00": "Amsterdam, NL", "RRC01": "London, GB", "RRC03": "Amsterdam, NL", "RRC04": "Geneva, CH",
        "RRC05": "Vienna, AT", "RRC06": "Otemachi, JP", "RRC07": "Stockholm, SE", "RRC10": "Milan, IT",
        "RRC11": "New York, US", "RRC12": "Frankfurt, DE", "RRC13": "Moscow, RU", "RRC14": "Palo Alto, US",
        "RRC15": "Sao Paulo, BR", "RRC16": "Miami, US", "RRC18": "Barcelona, ES", "RRC19": "Johannesburg, ZA",
        "RRC20": "Zurich, CH", "RRC21": "Paris, FR", "RRC22": "Bucharest, RO", "RRC23": "Singapore, SG",
        "RRC24": "Montevideo, UY", "RRC25": "Amsterdam, NL", "RRC26": "Dubai, AE",
    ]
}
