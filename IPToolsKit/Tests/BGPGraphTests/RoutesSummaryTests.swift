// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import Testing
@testable import BGPGraph

@Suite struct RoutesSummaryTests {
    @Test func realFixtureNumbers() async throws {
        let graph = GraphBuilder.build(from: try await fixturePaths("8.8.8.0/24"))
        let summary = RoutesSummary(graph: graph, collectorCount: 23, myASN: nil)
        #expect(summary.totalRoutes == 369)
        #expect(summary.collectorCount == 23)
        #expect(Int((summary.directFraction * 100).rounded()) == 75)
        #expect(summary.handoffs == [214292, 3356])
        #expect(summary.myASNRouteCount == nil)
    }

    @Test func myASNRouteCount() async throws {
        let graph = GraphBuilder.build(from: try await fixturePaths("8.8.8.0/24"))
        #expect(RoutesSummary(graph: graph, collectorCount: 23, myASN: 3320).myASNRouteCount == 2)
        #expect(RoutesSummary(graph: graph, collectorCount: 23, myASN: 24940).myASNRouteCount == 0)
    }

    @Test func handoffsTieBreakAndOmission() {
        // Layer 1: 10 (transit 2), 11 (transit 2), 12 (no transit, direct only).
        let paths = repeated(2, [1, 10, 9]) + repeated(2, [2, 11, 9]) + repeated(1, [12, 9])
            + [path(3, 11, 9), path(4, 10, 9)]
        let g = GraphBuilder.build(from: paths)
        let s = RoutesSummary(graph: g, collectorCount: 1, myASN: nil)
        #expect(!s.handoffs.contains(12))
        #expect(s.handoffs.count == 2)
        let direct = RoutesSummary(graph: GraphBuilder.build(from: repeated(3, [1, 9])), collectorCount: 1, myASN: nil)
        #expect(direct.handoffs.isEmpty)
        #expect(direct.directFraction == 1)
    }

    @Test func emptyGraph() {
        let s = RoutesSummary(graph: GraphBuilder.build(from: []), collectorCount: 0, myASN: 5)
        #expect(s.totalRoutes == 0 && s.directFraction == 0 && s.handoffs.isEmpty && s.myASNRouteCount == 0)
    }
}

@Suite struct PinnedTests {
    @Test func pinnedAS3320StaysVisibleWithK6OnTheRealFixture() async throws {
        let paths = try await fixturePaths("8.8.8.0/24")
        let plain = GraphBuilder.build(from: paths)
        #expect(plain.nodeID(for: 3320) == .more(layer: 1))      // folded without pinning
        let pinned = GraphBuilder.build(from: paths, options: .init(maxNodesPerLayer: 6, pinned: [3320]))
        #expect(pinned.nodeID(for: 3320) == .asn(3320))
        let layer1 = pinned.nodes.filter { $0.layer == 1 }
        let plainLayer1 = plain.nodes.filter { $0.layer == 1 }
        // Top K unchanged, the pinned node follows it, then the (smaller) bucket.
        #expect(Array(layer1.prefix(6).map(\.id)) == Array(plainLayer1.prefix(6).map(\.id)))
        #expect(layer1[6].id == .asn(3320))
        #expect(layer1.last?.id == .more(layer: 1))
        #expect(layer1.count == 8)
        let bucket = try #require(layer1.last)
        let plainBucket = try #require(plainLayer1.last)
        #expect(bucket.collapsed.count == plainBucket.collapsed.count - 1)
        #expect(!bucket.collapsed.contains(3320))
    }

    @Test func pinnedInTopKChangesNothing() {
        let paths = (1...10).flatMap { repeated(11 - $0, [UInt32(100 + $0), 9]) }
        let a = GraphBuilder.build(from: paths, options: .init(maxNodesPerLayer: 6))
        let b = GraphBuilder.build(from: paths, options: .init(maxNodesPerLayer: 6, pinned: [101]))
        #expect(a.nodes == b.nodes && a.edges == b.edges)
    }

    @Test func bucketDisappearsWhenOnlyPinnedRemain() {
        let paths = (1...7).flatMap { repeated(8 - $0, [UInt32(100 + $0), 9]) }
        let g = GraphBuilder.build(from: paths, options: .init(maxNodesPerLayer: 6, pinned: [107]))
        let layer1 = g.nodes.filter { $0.layer == 1 }
        #expect(layer1.count == 7)
        #expect(layer1.allSatisfy { if case .more = $0.id { return false } else { return true } })
        #expect(layer1.last?.id == .asn(107))
    }

    @Test func pinnedOriginAndUnknownAreHarmless() {
        let g = GraphBuilder.build(from: repeated(2, [1, 9]), options: .init(pinned: [9, 777]))
        #expect(g.nodes.count == 2)
    }

    @Test func defaultOptionsHaveNoPins() {
        #expect(GraphBuildOptions().pinned.isEmpty)
    }
}
