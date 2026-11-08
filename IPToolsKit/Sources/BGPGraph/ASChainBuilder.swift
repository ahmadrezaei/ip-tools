// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation

/// Builds the "Your route" chain (DESIGN 6.11). Every function is pure and deterministic.
public enum ASChainBuilder {
    // MARK: fromTrace (6.11.6)

    private struct Segment {
        var asn: UInt32?
        var hops: [ChainHop]
        var droppedBefore: Int      // hops without a known network dropped between the previous segment and this one
        let isYou: Bool
    }

    /// DESIGN 6.11.6. Pure; call on every update.
    ///
    /// Notes for callers: `lastTTL` is the TTL of the last hop that answered (nil when none did). A node's
    /// `ttls` spans every hop folded into it, absorbed ones included; `answeredHops` counts the non-silent hops;
    /// `rttRange` covers the answered probes of the node's network hops (for the You node, of every answered hop
    /// in it, local ones included).
    public static func fromTrace(_ hops: [ChainHop], myASN: UInt32?, origins: [UInt32], finished: Bool,
                                 source: ASChain.Source) -> ASChain {
        var ordered = hops.enumerated().sorted { a, b in
            a.element.ttl != b.element.ttl ? a.element.ttl < b.element.ttl : a.offset < b.offset
        }.map(\.element)
        // The probe target is inside the mapped prefix by construction, so a hop that reached it belongs to the
        // origin network even when its own ASN lookup failed (or it is unknown/silent).
        if let origin = origins.first {
            ordered = ordered.map { hop in
                guard hop.reachedTarget else { return hop }
                switch hop.kind {
                case .unknownNetwork, .silent:
                    return ChainHop(ttl: hop.ttl, kind: .network(origin), address: hop.address,
                                    hostname: hop.hostname, rtts: hop.rtts, reachedTarget: true)
                default: return hop
                }
            }
        }
        let originSet = Set(origins)

        // Rule 2: the leading block (everything before the first network hop) belongs to You.
        var leading: [ChainHop] = []
        var index = 0
        while index < ordered.count {
            if case .network = ordered[index].kind { break }
            leading.append(ordered[index])
            index += 1
        }
        var segments: [Segment] = [Segment(asn: myASN, hops: leading, droppedBefore: 0, isYou: true)]

        // Rules 3 and 4: merge runs, absorb or drop non-network hops, fold loops.
        var pending: [ChainHop] = []
        for hop in ordered[index...] {
            guard case let .network(asn) = hop.kind else {
                pending.append(hop)
                continue
            }
            if let j = segments.lastIndex(where: { $0.asn == asn }) {
                var merged = segments[j]
                for later in segments[(j + 1)...] { merged.hops += later.hops }
                merged.hops += pending
                merged.hops.append(hop)
                segments.removeSubrange(j...)
                segments.append(merged)
            } else {
                segments.append(Segment(asn: asn, hops: [hop], droppedBefore: pending.count, isYou: false))
            }
            pending = []
        }

        // If an origin AS appears mid-chain, the last such segment is the destination and anything measured
        // after it is dropped. Appending an expected destination instead would give two nodes the same id
        // ("AS<origin>"), and reaching the origin already completes the route per 6.11.6 rule 6.
        if let k = segments.indices.dropFirst().last(where: { segments[$0].asn.map(originSet.contains) ?? false }),
           k < segments.count - 1 {
            segments.removeSubrange((k + 1)...)
        }

        let skipped = segments.reduce(0) { $0 + $1.droppedBefore }
        let reached = ordered.contains { $0.reachedTarget }
        let lastTTL = ordered.last { $0.kind != .silent }?.ttl

        // Rule 7: the destination is on your own network.
        if let myASN, originSet.contains(myASN) {
            let node = makeNode(asn: myASN, hops: ordered, role: .youAndDestination, isYou: true)
            return ASChain(nodes: [node], source: source, completion: .complete, reachedTarget: reached,
                           lastTTL: lastTTL, skippedHops: 0)
        }

        // Rule 5 is built into the seeded You segment: it is the first segment, with `myASN` as its ASN.
        var nodes: [ASChain.Node] = segments.enumerated().map { i, segment in
            makeNode(asn: segment.asn, hops: segment.hops, role: i == 0 ? .you : .transit, isYou: segment.isYou)
        }

        // Rule 6: destination.
        let completion: ASChain.Completion
        if nodes.count > 1, let last = segments.last?.asn, originSet.contains(last) {
            nodes[nodes.count - 1] = withRole(nodes[nodes.count - 1], .destination)
            completion = .complete
        } else {
            completion = finished ? .gap : .inProgress
            if let origin = origins.first {
                nodes.append(ASChain.Node(asn: origin, role: .destination, provenance: .expected, gapBefore: true))
            }
        }
        return ASChain(nodes: nodes, source: source, completion: completion, reachedTarget: reached,
                       lastTTL: lastTTL, skippedHops: skipped)
    }

    private static func makeNode(asn: UInt32?, hops: [ChainHop], role: ASChain.Node.Role, isYou: Bool) -> ASChain.Node {
        let answered = hops.filter { $0.kind != .silent }
        let rttSource: [ChainHop] = isYou ? answered : answered.filter {
            if case .network = $0.kind { return true } else { return false }
        }
        let rtts = rttSource.flatMap(\.rtts)
        let ttlValues = hops.map(\.ttl)
        return ASChain.Node(
            asn: asn, role: role, provenance: .measured,
            ttls: ttlValues.min().flatMap { lo in ttlValues.max().map { lo...$0 } },
            answeredHops: answered.count,
            rttRange: rtts.min().flatMap { lo in rtts.max().map { lo...$0 } },
            hops: hops)
    }

    private static func withRole(_ n: ASChain.Node, _ role: ASChain.Node.Role) -> ASChain.Node {
        ASChain.Node(asn: n.asn, role: role, provenance: n.provenance, ttls: n.ttls, answeredHops: n.answeredHops,
                     rttRange: n.rttRange, hops: n.hops, routeCount: n.routeCount, gapBefore: n.gapBefore)
    }

    // MARK: BGP suffixes (6.11.4, 6.11.7)

    private struct Suffix {
        let asns: [UInt32]
        var count: Int
        var collectors: Set<String>
    }

    /// Groups the suffixes `p[i...]` starting at `start`, best first: most paths, then shorter, then
    /// lexicographically smaller.
    private static func rankedSuffixes(_ paths: [ObservedPath], from start: UInt32) -> [Suffix] {
        var grouped: [[UInt32]: Suffix] = [:]
        for path in paths {
            guard let i = path.asns.firstIndex(of: start) else { continue }
            let suffix = Array(path.asns[i...])
            var entry = grouped[suffix] ?? Suffix(asns: suffix, count: 0, collectors: [])
            entry.count += 1
            entry.collectors.insert(path.collector)
            grouped[suffix] = entry
        }
        return grouped.values.sorted { a, b in
            if a.count != b.count { return a.count > b.count }
            if a.asns.count != b.asns.count { return a.asns.count < b.asns.count }
            return a.asns.lexicographicallyPrecedes(b.asns)
        }
    }

    /// DESIGN 6.11.4. nil when no cleaned path contains myASN.
    public static func fromBGP(_ cleanedPaths: [ObservedPath], myASN: UInt32, origins: [UInt32]) -> ASChain? {
        guard let best = rankedSuffixes(cleanedPaths, from: myASN).first else { return nil }
        let asns = best.asns
        let nodes: [ASChain.Node] = asns.enumerated().map { i, asn in
            let role: ASChain.Node.Role
            if asns.count == 1 { role = .youAndDestination }
            else if i == 0 { role = .you }
            else if i == asns.count - 1 { role = .destination }
            else { role = .transit }
            return ASChain.Node(asn: asn, role: role, provenance: .bgp, routeCount: best.count)
        }
        return ASChain(nodes: nodes, source: .bgp(collectors: best.collectors.sorted()), completion: .complete,
                       reachedTarget: false)
    }

    /// DESIGN 6.11.7. Returns `chain` unchanged unless completion == .gap and a suffix exists.
    public static func stitch(_ chain: ASChain, cleanedPaths: [ObservedPath], origins: [UInt32]) -> ASChain {
        guard chain.completion == .gap, !chain.reachedTarget,
              let measuredIndex = chain.nodes.lastIndex(where: { $0.provenance == .measured }),
              let x = chain.nodes[measuredIndex].asn else { return chain }
        let used = Set(chain.nodes[...measuredIndex].compactMap(\.asn))
        let originSet = Set(origins)
        let eligible = rankedSuffixes(cleanedPaths, from: x).filter { suffix in
            suffix.asns.count >= 2
                && (originSet.isEmpty || originSet.contains(suffix.asns[suffix.asns.count - 1]))
        }
        guard let rankIndex = eligible.firstIndex(where: { $0.asns.dropFirst().allSatisfy { !used.contains($0) } })
        else { return chain }
        let best = eligible[rankIndex]
        var nodes = Array(chain.nodes[...measuredIndex])
        let tail = best.asns.dropFirst()
        for (i, asn) in tail.enumerated() {
            let last = i == tail.count - 1
            nodes.append(ASChain.Node(asn: asn, role: last ? .destination : .transit, provenance: .bgp,
                                      routeCount: best.count))
        }
        return ASChain(nodes: nodes, source: chain.source, completion: .stitched,
                       reachedTarget: chain.reachedTarget, lastTTL: chain.lastTTL, skippedHops: chain.skippedHops,
                       stitchedRouteCount: best.count, stitchedRank: rankIndex + 1)
    }
}
