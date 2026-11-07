// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import Testing
import RIPEstat
@testable import BGPGraph

@Suite struct GraphBuilderTests {
    // MARK: Rule 1: clean each path

    @Test func prependingIsCollapsed() {
        let g = GraphBuilder.build(from: [path(1, 1, 1, 2, 2, 3)])
        #expect(g.cleanedPaths.map(\.asns) == [[1, 2, 3]])
        #expect(g.edge(.asn(1), .asn(2))?.pathCount == 1)
        #expect(g.edge(.asn(1), .asn(1)) == nil)
        #expect(g.discardedPaths == 0)
    }

    @Test func asSetFlagIsCountedAndKept() {
        let g = GraphBuilder.build(from: [path(1, 2, set: true), path(1, 2), path(3, 2, set: true)])
        #expect(g.asSetPaths == 2)
        #expect(g.cleanedPaths.filter(\.hadASSet).count == 2)
        #expect(g.totalPaths == 3)
    }

    @Test func loopsAndEmptyPathsAreDiscarded() {
        let g = GraphBuilder.build(from: [path(1, 2, 3), path(1, 2, 1, 3), path(), path(5, 6, 7, 5)])
        #expect(g.totalPaths == 1)
        #expect(g.discardedPaths == 3)
        #expect(g.cleanedPaths.count == 1)
        #expect(g.node(.asn(5)) == nil)               // discarded paths leave no trace
        // Prepending is not a loop.
        #expect(GraphBuilder.build(from: [path(1, 2, 2, 3)]).discardedPaths == 0)
    }

    @Test func emptyInput() {
        let g = GraphBuilder.build(from: [])
        #expect(g.nodes.isEmpty && g.edges.isEmpty && g.origins.isEmpty)
        #expect(g.layerCount == 0 && g.totalPaths == 0)
        let allBad = GraphBuilder.build(from: [path(1, 2, 1)])
        #expect(allBad.nodes.isEmpty && allBad.discardedPaths == 1)
    }

    // MARK: Rule 2: origins, MOAS

    @Test func singleOrigin() {
        let g = GraphBuilder.build(from: repeated(3, [1, 10]) + repeated(2, [2, 3, 10]))
        #expect(g.origins == [10])
        #expect(g.node(.asn(10))?.isOrigin == true)
        #expect(g.node(.asn(10))?.layer == 0)
        #expect(g.node(.asn(10))?.role == .origin)
    }

    @Test func moasPutsAllOriginsInLayerZeroMostFrequentFirst() {
        let g = GraphBuilder.build(from: repeated(1, [1, 20]) + repeated(3, [2, 10]) + repeated(3, [3, 15]))
        #expect(g.origins == [10, 15, 20])           // 3, 3 (tie: lower ASN first), 1
        for o: UInt32 in [10, 15, 20] {
            #expect(g.node(.asn(o))?.layer == 0)
            #expect(g.node(.asn(o))?.isOrigin == true)
        }
        #expect(g.layerSizes() == [3, 3])
    }

    // MARK: Rule 3: counts

    @Test func countsPerAS() {
        // 1 is a peer and transit; 2 is only ever a peer; 3 is transit only; 10 origin.
        let g = GraphBuilder.build(from: [path(1, 3, 10), path(2, 3, 10), path(3, 10), path(2, 1, 3, 10)])
        let n3 = g.node(.asn(3))!, n1 = g.node(.asn(1))!, n2 = g.node(.asn(2))!, n10 = g.node(.asn(10))!
        #expect(n3.pathCount == 4)
        #expect(n3.transitCount == 3)              // paths where 3 is neither first nor last
        #expect(n3.isPeer)                         // it is the first ASN of path [3,10]
        #expect(n1.pathCount == 2 && n1.transitCount == 1 && n1.isPeer)
        #expect(n2.pathCount == 2 && n2.transitCount == 0 && n2.isPeer && n2.role == .peer)
        #expect(n10.pathCount == 4 && n10.transitCount == 0 && !n10.isPeer)
        let transitOnly = GraphBuilder.build(from: [path(1, 3, 10)])
        #expect(transitOnly.node(.asn(3))?.role == .transit)
    }

    // MARK: Rules 4 and 5: edges and layers

    @Test func edgesAreDirectedTowardTheOriginWithCounts() {
        let g = GraphBuilder.build(from: repeated(2, [1, 2, 10]) + repeated(3, [3, 2, 10]))
        #expect(g.edge(.asn(1), .asn(2))?.pathCount == 2)
        #expect(g.edge(.asn(3), .asn(2))?.pathCount == 3)
        #expect(g.edge(.asn(2), .asn(10))?.pathCount == 5)
        #expect(g.edge(.asn(2), .asn(1)) == nil)
        #expect(g.edges.count == 3)
        #expect(g.edges.allSatisfy { $0.kind == .forward })
    }

    @Test func layersAreShortestDistanceNotPathPosition() {
        // 3 appears 3 hops out in the long path but 1 hop out in the short one.
        let g = GraphBuilder.build(from: [path(3, 2, 1, 10), path(3, 10)])
        #expect(g.node(.asn(3))?.layer == 1)
        #expect(g.node(.asn(1))?.layer == 1)
        #expect(g.node(.asn(2))?.layer == 2)
        #expect(g.edge(.asn(3), .asn(2))?.kind == .backward)        // layer 1 -> layer 2
        #expect(g.edge(.asn(2), .asn(1))?.kind == .forward)
        #expect(g.edge(.asn(3), .asn(10))?.kind == .forward)
    }

    @Test func everyNonOriginNodeReachesTheNextColumn() async throws {
        let paths = try await fixturePaths("1.1.1.0/24")
        let g = GraphBuilder.build(from: paths, options: .init(maxNodesPerLayer: 30))
        for node in g.nodes where node.layer > 0 {
            let hasForward = g.edges.contains { $0.from == node.id && $0.kind == .forward }
            #expect(hasForward, "node \(node.id) has no forward edge")
        }
    }

    @Test func lateralAndBackwardKinds() {
        // 1 and 2 are both one hop out: 1->2 is lateral. 10 is an origin; 5 is one hop from origin 20: 10->5 backward.
        let g = GraphBuilder.build(from: [path(1, 2, 20), path(2, 20), path(1, 20), path(9, 10), path(10, 5, 20), path(5, 20)])
        #expect(g.edge(.asn(1), .asn(2))?.kind == .lateral)
        #expect(g.node(.asn(10))?.layer == 0 && g.node(.asn(20))?.layer == 0)
        #expect(g.node(.asn(5))?.layer == 1)
        #expect(g.edge(.asn(10), .asn(5))?.kind == .backward)
        #expect(g.edge(.asn(5), .asn(20))?.kind == .forward)
    }

    // MARK: Rule 6 and 7: rank and collapse

    /// Layer 1 has ASNs 1...8, ASN `a` carrying `9 - a` paths ([200 + a, a, 100]); one more peer 300 uses 4 and 5.
    private func wideGraph(k: Int) -> ASGraph {
        var paths: [ObservedPath] = []
        for a in UInt32(1)...8 { paths += repeated(Int(9 - a), [200 + a, a, 100]) }
        return GraphBuilder.build(from: paths, options: .init(maxNodesPerLayer: k))
    }

    @Test func topKPerLayerAndMoreBucket() {
        let g = wideGraph(k: 3)
        let layer1 = g.nodes.filter { $0.layer == 1 }
        #expect(layer1.map(\.id) == [.asn(1), .asn(2), .asn(3), .more(layer: 1)])
        let more = g.node(.more(layer: 1))!
        #expect(more.collapsed == [4, 5, 6, 7, 8])                  // ranked order
        #expect(more.pathCount == 5 + 4 + 3 + 2 + 1)
        #expect(more.transitCount == 5 + 4 + 3 + 2 + 1)
        #expect(!more.isOrigin && !more.isPeer)
        #expect(g.allASNs(inLayer: 1) == [1, 2, 3, 4, 5, 6, 7, 8])  // uncollapsed
        // The origin layer is never collapsed.
        #expect(g.node(.asn(100)) != nil)
    }

    @Test func noCollapseWhenLayerFitsInK() {
        let g = wideGraph(k: 8)
        #expect(g.nodes.allSatisfy { if case .more = $0.id { false } else { true } })
        #expect(g.nodes.filter { $0.layer == 1 }.count == 8)
    }

    @Test func originLayerIsNeverCollapsed() {
        var paths: [ObservedPath] = []
        for o in UInt32(10)...19 { paths.append(path(1, o)) }
        let g = GraphBuilder.build(from: paths, options: .init(maxNodesPerLayer: 2))
        #expect(g.nodes.filter { $0.layer == 0 }.count == 10)
    }

    @Test func rankingUsesTransitDoubleAndLowerASNTieBreak() {
        // 7 has 2 paths as transit (score 4); 5 and 6 have 3 paths as peers only (score 3). Tie 5 vs 6: lower first.
        let g = GraphBuilder.build(from: repeated(2, [50, 7, 100]) + repeated(3, [5, 100]) + repeated(3, [6, 100]),
                                   options: .init(maxNodesPerLayer: 2))
        let layer1 = g.nodes.filter { $0.layer == 1 }.map(\.id)
        #expect(layer1 == [.asn(7), .asn(5), .more(layer: 1)])
        #expect(g.node(.more(layer: 1))?.collapsed == [6])
        #expect(g.allASNs(inLayer: 1) == [7, 5, 6])
    }

    @Test func edgesAreRepointedMergedAndSelfLoopsDropped() {
        var paths = repeated(8, [3, 100]) + repeated(7, [4, 100])      // clear top 2 of layer 1 (K = 2)
        paths += [path(1, 100), path(2, 100)]
        paths += [path(1, 2, 100)]                                      // lateral between two bucket members
        paths += [path(9, 1, 100), path(9, 2, 100)]                     // peer 9 reaches both bucket members
        let g = GraphBuilder.build(from: paths, options: .init(maxNodesPerLayer: 2))
        let more = NodeID.more(layer: 1)
        #expect(g.node(more)?.collapsed == [2, 1])                      // scores 5 and 4
        #expect(g.node(.asn(9))?.layer == 2)
        // Parallel edges merged: 9->1 and 9->2 become one edge into the bucket with the summed count.
        #expect(g.edge(.asn(9), more)?.pathCount == 2)
        #expect(g.edges.filter { $0.from == .asn(9) }.count == 1)
        // 1->100 (2) and 2->100 (3) merge into more->100 (5).
        #expect(g.edges.filter { $0.from == more && $0.to == .asn(100) }.map(\.pathCount) == [5])
        // The 1->2 edge became a self-loop and is dropped.
        #expect(!g.edges.contains { $0.from == $0.to })
        #expect(g.edges.allSatisfy { g.node($0.from) != nil && g.node($0.to) != nil })
        #expect(g.edge(.asn(3), .asn(100))?.pathCount == 8)
    }

    @Test func edgeIdsAreUniqueAndStable() {
        let g = wideGraph(k: 3)
        #expect(Set(g.edges.map(\.id)).count == g.edges.count)
    }

    // MARK: Rule 8: output helpers

    @Test func outputFieldsAndHelpers() {
        let g = GraphBuilder.build(from: [path(1, 3, 10, collector: "RRC01"), path(2, 3, 10, collector: "RRC02"),
                                          path(1, 3, 10, collector: "RRC03"), path(3, 2, 3, 10)])
        #expect(g.totalPaths == 3 && g.discardedPaths == 1)
        #expect(g.layerCount == 3)                    // 10 / 3 / {1,2}
        #expect(g.paths(through: 3).count == 3)
        #expect(g.paths(through: 2).count == 1)
        #expect(g.paths(through: 99).isEmpty)
        let unique = g.uniquePaths()
        #expect(unique.first?.asns == [1, 3, 10] && unique.first?.count == 2 && unique.first?.collectors == 2)
        #expect(unique.count == 2)
        let ids = g.highlightedEdges(through: 2)
        #expect(ids == [GraphEdge(from: .asn(2), to: .asn(3), pathCount: 0, kind: .forward).id,
                        GraphEdge(from: .asn(3), to: .asn(10), pathCount: 0, kind: .forward).id])
        #expect(g.nodeID(for: 3) == .asn(3))
    }

    @Test func highlightedEdgesFollowCollapsedBuckets() {
        let g = wideGraph(k: 3)
        // ASN 8 is inside .more(layer: 1); its path is 208 -> 8 -> 100, and 208 is in .more(layer: 2)? (K = 3).
        #expect(g.nodeID(for: 8) == .more(layer: 1))
        let ids = g.highlightedEdges(through: 8)
        #expect(ids.count == 2)
        for id in ids { #expect(g.edges.contains { $0.id == id }) }
    }

    // MARK: Determinism

    @Test func buildIsDeterministicAndInputOrderIndependent() async throws {
        let paths = try await fixturePaths("1.1.1.0/24")
        let a = GraphBuilder.build(from: paths)
        let b = GraphBuilder.build(from: paths)
        #expect(a.nodes == b.nodes && a.edges == b.edges)
        let reversed = GraphBuilder.build(from: Array(paths.reversed()))
        #expect(a.nodes == reversed.nodes && a.edges == reversed.edges && a.origins == reversed.origins)
    }

    // MARK: Real data

    @Test func realData111Graph() async throws {
        let paths = try await fixturePaths("1.1.1.0/24")
        #expect(paths.count == 365)
        let full = GraphBuilder.build(from: paths, options: .init(maxNodesPerLayer: 1000))
        let g = GraphBuilder.build(from: paths, options: .init(maxNodesPerLayer: 6))
        print("REAL 1.1.1.0/24 paths=\(g.totalPaths) discarded=\(g.discardedPaths) layers=\(g.layerCount) fullLayerSizes=\(full.layerSizes()) k6Sizes=\(g.layerSizes()) k6Nodes=\(g.nodes.count) k6Edges=\(g.edges.count) fullNodes=\(full.nodes.count) fullEdges=\(full.edges.count) origins=\(g.origins)")
        #expect(g.origins == [13335])
        #expect(g.totalPaths + g.discardedPaths == 365)
        #expect(g.layerCount == 4)
        #expect(full.layerSizes()[0] == 1)
        #expect(full.nodes.count == 297)
        #expect(g.layerSizes().dropFirst().allSatisfy { $0 <= 7 })      // K + the .more bucket
        #expect(g.nodes.count < 30)
        for l in 1..<g.layerCount {
            #expect(g.allASNs(inLayer: l).count == full.layerSizes()[l])
        }
        #expect(g.edges.allSatisfy { $0.pathCount > 0 })
    }

    @Test func realDataFewPathsAndPrivate() async throws {
        let few = GraphBuilder.build(from: try await fixturePaths("80.249.208.0/21"))
        #expect(few.totalPaths == 2)
        #expect(few.origins.sorted() == [7713, 35598])      // MOAS-looking: two paths, two last ASNs
        #expect(few.layerCount == 3)                        // 7713 <- 56308 <- 133210; 35598 alone
        let none = GraphBuilder.build(from: try await fixturePaths("10.0.0.0/8"))
        #expect(none.nodes.isEmpty)
    }

    @Test func realDataIPv6() async throws {
        let g = GraphBuilder.build(from: try await fixturePaths("2606:4700:4700::/48"))
        #expect(g.origins == [13335])
        #expect(g.totalPaths > 300)
    }

    @Test func syntheticLookingGlassFixtureStillBuilds() async throws {
        // 1.1.1.0/24 looking-glass copy (synthetic): 360 paths, layer sizes 1 / 240 / 48 / 7 per DESIGN 6.3.
        let url = try #require(Bundle.module.url(forResource: "looking-glass_1.1.1.0-24", withExtension: "json",
                                                 subdirectory: "Fixtures"))
        let data = try Data(contentsOf: url)
        let lg = try decodeLookingGlass(data)
        let g = GraphBuilder.build(from: lg, options: .init(maxNodesPerLayer: 1000))
        #expect(g.totalPaths == 360)
        #expect(g.layerCount == 4)
        #expect(g.layerSizes() == [1, 240, 48, 7])
    }
}

@Suite struct GraphDerivedDataTests {
    @Test func countsGroupsAndHighlight() {
        let g = GraphBuilder.build(from: [path(1, 2, 9), path(1, 2, 9, collector: "RRC01"), path(3, 9)],
                                   options: .init(maxNodesPerLayer: 6))
        #expect(g.pathCounts[2] == 2 && g.transitCounts[2] == 2 && g.transitCounts[9] == nil)
        #expect(g.collectorsByASN[2] == ["RRC00", "RRC01"])
        #expect(g.layerByASN[9] == 0 && g.layerByASN[1] == 2)
        #expect(g.pathGroups.first?.count == 2 && g.pathGroups.first?.collectors == 2)
        #expect(g.pathGroups(through: [3]).count == 1)
        let h = g.highlight(through: [2])
        #expect(h.nodes == [.asn(1), .asn(2), .asn(9)])
        #expect(!h.nodes.contains(.asn(3)))
        #expect(h.edges.count == 2)
    }
}
