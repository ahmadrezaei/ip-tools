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

/// Cache around `RIPEstatAPI` (the client limits concurrency): `network-info` cached per hop IP (a covering
/// prefix is never reused: a more specific route may belong to another AS), and `as-names` for the ASNs found. Failures are never cached and never thrown.
public actor ASNLookup {
    private let api: any RIPEstatAPI
    private var byAddress: [IPAddress: HopASN?] = [:]
    private var names: [UInt32: String] = [:]

    public init(api: any RIPEstatAPI) {
        self.api = api
    }

    /// Origin AS of the prefix covering `address`. Nil when not announced or when the request failed.
    public func lookup(_ address: IPAddress) async -> HopASN? {
        if let cached = byAddress[address] { return cached.map(withName) }
        let api = self.api
        let text = address.description
        let info = try? await api.networkInfo(text)
        guard let info else { return nil }        // failure: try again next time
        guard let origin = info.originASNs.first else {
            byAddress[address] = .some(nil)       // not announced
            return nil
        }
        let hop = HopASN(asn: origin, name: names[origin], prefix: info.prefix)
        byAddress[address] = .some(hop)
        return hop
    }

    /// Short holder names for `asns` (cached; unknown ones are fetched in one bulk request).
    public func names(for asns: [UInt32]) async -> [UInt32: String] {
        let missing = Array(Set(asns.filter { names[$0] == nil })).sorted()
        if !missing.isEmpty {
            let api = self.api
            if let fetched = try? await api.asNames(missing) {
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
}
