// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import RIPEstat
@testable import BGPGraph

func path(_ asns: UInt32..., collector: String = "RRC00", peer: String = "192.0.2.1", set: Bool = false) -> ObservedPath {
    ObservedPath(asns: asns, collector: collector, peerIP: peer, hadASSet: set)
}

func repeated(_ count: Int, _ asns: [UInt32]) -> [ObservedPath] {
    (0..<count).map { ObservedPath(asns: asns, collector: "RRC00", peerIP: "192.0.2.\($0)") }
}

/// Observed paths from a captured fixture, served through `MockRIPEstat` (real RIPEstat bgp-state data).
func fixturePaths(_ resource: String) async throws -> [ObservedPath] {
    let mock = MockRIPEstat(fixtureBundle: Bundle.module, latency: .zero)
    let lg = try await mock.lookingGlass(resource)
    return lg.routes.map { ObservedPath(asns: $0.asPath, collector: $0.collector, peerIP: $0.peerIP, hadASSet: $0.hadASSet) }
}

extension ASGraph {
    func layerSizes() -> [Int] {
        (0..<layerCount).map { l in nodes.filter { $0.layer == l }.count }
    }
    func edge(_ from: NodeID, _ to: NodeID) -> GraphEdge? { edges.first { $0.from == from && $0.to == to } }
}

/// Minimal decoder for the looking-glass JSON (RIPEstat's parser is internal): peer-first AS paths.
func decodeLookingGlass(_ data: Data) throws -> [ObservedPath] {
    struct Doc: Decodable {
        struct Data: Decodable {
            struct RRC: Decodable {
                struct Peer: Decodable { let as_path: String; let peer: String }
                let rrc: String
                let peers: [Peer]
            }
            let rrcs: [RRC]
        }
        let data: Data
    }
    let doc = try JSONDecoder().decode(Doc.self, from: data)
    return doc.data.rrcs.flatMap { rrc in
        rrc.peers.map { ObservedPath(asns: $0.as_path.split(separator: " ").compactMap { UInt32($0) },
                                     collector: rrc.rrc, peerIP: $0.peer) }
    }
}
