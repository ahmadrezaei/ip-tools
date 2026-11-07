// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import NetCore
import RIPEstat

public struct HopASN: Hashable, Sendable {
    public let asn: UInt32
    public let name: String?
    public let prefix: String?
    public init(asn: UInt32, name: String?, prefix: String?) {
        self.asn = asn
        self.name = name
        self.prefix = prefix
    }
}

/// Cache + concurrency limit around `RIPEstatAPI`: `network-info` per hop IP (reusing the covering prefix
/// for other IPs), and `as-names` for the ASNs found. Failures are never cached and never thrown.
public actor ASNLookup {
    private let api: any RIPEstatAPI
    private let limiter = AsyncLimiter(limit: 4)
    private var byAddress: [IPAddress: HopASN?] = [:]
    private var byPrefix: [(network: IPAddress, length: Int, asn: HopASN)] = []
    private var names: [UInt32: String] = [:]

    public init(api: any RIPEstatAPI) {
        self.api = api
    }

    /// Origin AS of the prefix covering `address`. Nil when not announced or when the request failed.
    public func lookup(_ address: IPAddress) async -> HopASN? {
        if let cached = byAddress[address] { return cached.map(withName) }
        if let hit = byPrefix.first(where: { Self.contains($0.network, length: $0.length, address) }) {
            byAddress[address] = .some(hit.asn)
            return withName(hit.asn)
        }
        let api = self.api
        let text = address.description
        let info = await limiter.run { try? await api.networkInfo(text) }
        guard let info else { return nil }        // failure: try again next time
        guard let origin = info.originASNs.first else {
            byAddress[address] = .some(nil)       // not announced
            return nil
        }
        let hop = HopASN(asn: origin, name: names[origin], prefix: info.prefix)
        byAddress[address] = .some(hop)
        if let prefix = info.prefix, let parsed = Self.parsePrefix(prefix) {
            byPrefix.append((parsed.network, parsed.length, hop))
        }
        return hop
    }

    /// Short holder names for `asns` (cached; unknown ones are fetched in one bulk request).
    public func names(for asns: [UInt32]) async -> [UInt32: String] {
        let missing = Array(Set(asns.filter { names[$0] == nil })).sorted()
        if !missing.isEmpty {
            let api = self.api
            if let fetched = await limiter.run({ try? await api.asNames(missing) }) {
                for (asn, holder) in fetched {
                    let short = ASName.short(holder)
                    if !short.isEmpty { names[asn] = short }
                }
            }
        }
        var result: [UInt32: String] = [:]
        for asn in asns { if let name = names[asn] { result[asn] = name } }
        return result
    }

    private func withName(_ hop: HopASN) -> HopASN {
        HopASN(asn: hop.asn, name: hop.name ?? names[hop.asn], prefix: hop.prefix)
    }

    static func parsePrefix(_ text: String) -> (network: IPAddress, length: Int)? {
        let parts = text.split(separator: "/")
        guard parts.count == 2, let address = IPAddress(String(parts[0])), let length = Int(parts[1]),
              length >= 0, length <= address.bytes.count * 8 else { return nil }
        return (address, length)
    }

    static func contains(_ network: IPAddress, length: Int, _ address: IPAddress) -> Bool {
        guard network.family == address.family else { return false }
        var remaining = length
        for (a, b) in zip(network.bytes, address.bytes) {
            if remaining <= 0 { return true }
            let bits = min(8, remaining)
            let mask = UInt8(truncatingIfNeeded: 0xFF << (8 - bits))
            if a & mask != b & mask { return false }
            remaining -= bits
        }
        return true
    }
}
