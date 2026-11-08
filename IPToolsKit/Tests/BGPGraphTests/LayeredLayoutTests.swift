// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import CoreGraphics
import Foundation
import Testing
@testable import BGPGraph

@Suite struct LayeredLayoutTests {
    private let metrics = LayoutMetrics()

    private func realGraphs() async throws -> [ASGraph] {
        let paths = try await fixturePaths("1.1.1.0/24")
        return [6, 12, 30].map { GraphBuilder.build(from: paths, options: .init(maxNodesPerLayer: $0)) }
    }

    private func assertNoOverlaps(_ layout: GraphLayout) {
        let frames = Array(layout.frames.values)
        for i in 0..<frames.count {
            #expect(CGRect(origin: .zero, size: layout.size).contains(frames[i]))
            for j in (i + 1)..<max(i + 1, frames.count) {
                #expect(!frames[i].intersects(frames[j]), "\(frames[i]) overlaps \(frames[j])")
            }
        }
    }

    @Test func emptyGraphGivesEmptyLayout() {
        let layout = LayeredLayout.layout(GraphBuilder.build(from: []))
        #expect(layout.size == .zero && layout.frames.isEmpty && layout.edges.isEmpty && layout.rowHeaders.isEmpty)
    }

    @Test func noOverlapsOnRealGraphsAtEveryK() async throws {
        for graph in try await realGraphs() {
            let layout = LayeredLayout.layout(graph)
            #expect(layout.frames.count == graph.nodes.count)
            assertNoOverlaps(layout)
        }
    }

    @Test func rowsAreOrderedByLayerWithOriginAtTheBottom() async throws {
        for graph in try await realGraphs() {
            let layout = LayeredLayout.layout(graph)
            var yByLayer: [Int: CGFloat] = [:]
            for node in graph.nodes {
                let frame = try #require(layout.frames[node.id])
                if let y = yByLayer[node.layer] { #expect(y == frame.minY) } else { yByLayer[node.layer] = frame.minY }
            }
            let layers = yByLayer.keys.sorted()
            let pitch = metrics.headerHeight + metrics.nodeSize.height + metrics.rowSpacing
            for (a, b) in zip(layers, layers.dropFirst()) {
                #expect(yByLayer[a]! > yByLayer[b]!, "layer \(a) must be below layer \(b)")
                #expect(yByLayer[a]! - yByLayer[b]! == pitch)
            }
            #expect(yByLayer[0] == layout.size.height - metrics.padding - metrics.nodeSize.height)
            #expect(yByLayer[graph.layerCount - 1] == metrics.padding + metrics.headerHeight)
        }
    }

    @Test func moreBucketIsLastInItsRow() async throws {
        let graph = try await realGraphs()[0]
        let layout = LayeredLayout.layout(graph)
        var buckets = 0
        for node in graph.nodes {
            guard case .more = node.id else { continue }
            buckets += 1
            let frame = layout.frames[node.id]!
            for other in graph.nodes where other.layer == node.layer && other.id != node.id {
                #expect(layout.frames[other.id]!.maxX <= frame.minX)
            }
        }
        #expect(buckets == 3)
    }

    @Test func sizeAndHorizontalCentringFollowTheFormulas() async throws {
        let graph = try await realGraphs()[0]            // 4 layers, widest row 7 nodes
        let layout = LayeredLayout.layout(graph)
        let rows = CGFloat(graph.layerCount - 1)
        let widest = CGFloat(graph.layerSizes().max()!)
        let w = widest * 104 + (widest - 1) * 10
        #expect(layout.size.width == 16 * 2 + w)
        #expect(layout.size.height == 16 * 2 + (rows + 1) * (18 + 44) + rows * 44)
        // The origin row (1 node) is horizontally centred against the widest row.
        let origin = layout.frames[.asn(13335)]!
        #expect(origin.midX == 16 + w / 2)
        // Nodes in a row are 104 + 10 apart.
        let row1 = graph.nodes.filter { $0.layer == 1 }.map { layout.frames[$0.id]! }.sorted { $0.minX < $1.minX }
        for (a, b) in zip(row1, row1.dropFirst()) { #expect(b.minX - a.minX == 114) }
        #expect(layout.frames.values.allSatisfy { $0.size == CGSize(width: 104, height: 44) })
    }

    @Test func rowHeadersRunTopToBottomEndingWithTheOrigin() async throws {
        let graph = try await realGraphs()[0]
        let layout = LayeredLayout.layout(graph)
        #expect(layout.rowHeaders.map(\.layer) == [3, 2, 1, 0])
        let ys = layout.rowHeaders.map(\.centerY)
        #expect(ys == ys.sorted())
        let originTop = layout.frames[.asn(13335)]!.minY
        #expect(layout.rowHeaders.last!.centerY < originTop)
        #expect(layout.rowHeaders.allSatisfy { $0.minX == metrics.padding })
    }

    @Test func layoutIsDeterministic() async throws {
        let paths = try await fixturePaths("1.1.1.0/24")
        for k in [6, 12, 30] {
            let a = LayeredLayout.layout(GraphBuilder.build(from: paths, options: .init(maxNodesPerLayer: k)))
            let b = LayeredLayout.layout(GraphBuilder.build(from: paths, options: .init(maxNodesPerLayer: k)))
            let c = LayeredLayout.layout(GraphBuilder.build(from: Array(paths.reversed()), options: .init(maxNodesPerLayer: k)))
            #expect(a.frames == b.frames && a.edges == b.edges && a.size == b.size)
            #expect(a.frames == c.frames)
        }
    }

    @Test func barycentreOrderUntanglesRows() {
        // Origins 10 (more paths) and 20; peer A reaches 20, peer B reaches 10: B must sit left of A.
        let paths = repeated(3, [1, 10]) + repeated(1, [2, 20]) + [path(8, 1, 10)]
        // 1 -> 10 (4 paths), 2 -> 20 (1): sorted by barycentre 1 above 2 regardless of ASN order.
        let swapped = repeated(3, [2, 10]) + repeated(1, [1, 20])
        for input in [paths, swapped] {
            let g = GraphBuilder.build(from: input)
            let layout = LayeredLayout.layout(g)
            let top10 = layout.frames[.asn(10)]!.minX < layout.frames[.asn(20)]!.minX
            #expect(top10)
            let toward10 = g.edges.first { $0.to == .asn(10) }!.from
            let toward20 = g.edges.first { $0.to == .asn(20) }!.from
            #expect(layout.frames[toward10]!.minX < layout.frames[toward20]!.minX)
        }
    }

    @Test func forwardEdgeGeometry() async throws {
        let graph = try await realGraphs()[0]
        let layout = LayeredLayout.layout(graph)
        let forward = layout.edges.filter { $0.kind == .forward }
        #expect(!forward.isEmpty)
        for geometry in forward {
            let edge = try #require(graph.edges.first { $0.id == geometry.id })
            let from = layout.frames[edge.from]!, to = layout.frames[edge.to]!
            #expect(geometry.start == CGPoint(x: from.midX, y: from.maxY))
            #expect(geometry.end == CGPoint(x: to.midX, y: to.minY))
            #expect(geometry.start.y < geometry.end.y)          // flows downward
            let my = (geometry.start.y + geometry.end.y) / 2
            #expect(geometry.control1 == CGPoint(x: geometry.start.x, y: my))
            #expect(geometry.control2 == CGPoint(x: geometry.end.x, y: my))
        }
    }

    @Test func lateralEdgesArcAboveTheRowAndStrokeWidthFollowsCount() {
        let g = GraphBuilder.build(from: [path(1, 2, 20), path(2, 20), path(1, 20), path(1, 2, 20)])
        let layout = LayeredLayout.layout(g)
        let lateral = layout.edges.first { $0.kind == .lateral }
        let geometry = try! #require(lateral)
        let from = layout.frames[.asn(1)]!, to = layout.frames[.asn(2)]!
        #expect(geometry.start == CGPoint(x: from.midX, y: from.minY))
        #expect(geometry.end == CGPoint(x: to.midX, y: to.minY))
        let pull = min(40, 18 + abs(to.midX - from.midX) * 0.2)
        #expect(geometry.control1.y == from.minY - pull && geometry.control2.y == to.minY - pull)
        for e in layout.edges {
            let count = g.edges.first { $0.id == e.id }!.pathCount
            let expected = 1.5 + 6 * CGFloat((Double(count) / Double(g.totalPaths)).squareRoot())
            #expect(abs(e.lineWidth - expected) < 1e-9)
        }
        // Drawn in ascending count.
        let counts = layout.edges.map { id in g.edges.first { $0.id == id.id }!.pathCount }
        #expect(counts == counts.sorted())
    }

    @Test func singleNodeGraph() {
        let g = GraphBuilder.build(from: [path(13335)])
        let layout = LayeredLayout.layout(g)
        #expect(layout.frames.count == 1)
        #expect(layout.size == CGSize(width: 16 * 2 + 104, height: 16 * 2 + 18 + 44))
        #expect(layout.edges.isEmpty)
    }

    @Test func moasAndFewPathsFixtures() async throws {
        for resource in ["80.249.208.0/21", "2606:4700:4700::/48"] {
            let g = GraphBuilder.build(from: try await fixturePaths(resource))
            let layout = LayeredLayout.layout(g)
            #expect(layout.frames.count == g.nodes.count)
            assertNoOverlaps(layout)
        }
    }
}

@Suite struct LayeredLayoutOverlayTests {
    @Test func overlayEdgesAreAtLeastThreePointsWideAndCarryTheirStyle() {
        let g = GraphBuilder.build(from: repeated(5, [1, 10]) + repeated(5, [2, 10]),
                                   options: .init(highlightPath: [7, 1, 10], highlightPathHasGap: true))
        let layout = LayeredLayout.layout(g)
        let seven = layout.edges.first { $0.id == "\(NodeID.asn(7))>\(NodeID.asn(1))" }
        let last = layout.edges.first { $0.id == "\(NodeID.asn(1))>\(NodeID.asn(10))" }
        #expect(seven?.overlay == .path && (seven?.lineWidth ?? 0) >= 3)
        #expect(last?.overlay == .unknownSegment && (last?.lineWidth ?? 0) >= 3)
        #expect(layout.edges.first { $0.id == "\(NodeID.asn(2))>\(NodeID.asn(10))" }?.overlay == nil)
        // The overlay-only node sits one row above AS1 and does not overlap anything.
        let a = layout.frames[.asn(7)]!, b = layout.frames[.asn(1)]!
        #expect(a.maxY < b.minY)
        #expect(LayeredLayout.layout(g).frames == layout.frames)
    }

    private func assertNoOverlaps(_ layout: GraphLayout) {
        let frames = Array(layout.frames.values)
        for i in 0..<frames.count {
            for j in (i + 1)..<max(i + 1, frames.count) { #expect(!frames[i].intersects(frames[j])) }
        }
    }

    private func multiRowGraph() -> ASGraph {
        GraphBuilder.build(from: repeated(3, [100, 174, 15169]) + repeated(1, [200, 174, 15169]),
                           options: .init(highlightPath: [100, 15169]))
    }

    @Test func multiRowDropIsForwardWithVerticalGeometry() throws {
        let graph = multiRowGraph()
        let e = try #require(graph.edge(.asn(100), .asn(15169)))
        #expect(e.kind == .forward)
        let layout = LayeredLayout.layout(graph)
        let g = try #require(layout.edges.first { $0.id == e.id })
        let f = try #require(layout.frames[.asn(100)]), t = try #require(layout.frames[.asn(15169)])
        #expect(g.start == CGPoint(x: f.midX, y: f.maxY))
        #expect(g.end == CGPoint(x: t.midX, y: t.minY))
        #expect(layout.frames == LayeredLayout.layout(graph).frames)
        assertNoOverlaps(layout)
    }

    @Test func backwardEdgeLoopsOutToTheRight() throws {
        let e = GraphEdge(from: .asn(15169), to: .asn(174), pathCount: 0, kind: .backward)
        var graph = multiRowGraph()
        graph = ASGraph(nodes: graph.nodes, edges: graph.edges + [e], origins: graph.origins,
                        totalPaths: graph.totalPaths, discardedPaths: 0, layerCount: graph.layerCount,
                        cleanedPaths: graph.cleanedPaths)
        let layout = LayeredLayout.layout(graph)
        let g = try #require(layout.edges.first { $0.id == e.id })
        let f = try #require(layout.frames[.asn(15169)]), t = try #require(layout.frames[.asn(174)])
        #expect(g.start == CGPoint(x: f.maxX, y: f.midY) && g.end == CGPoint(x: t.maxX, y: t.midY))
        #expect(g.control1.x > max(f.maxX, t.maxX) - 0.001 && g.control2.x > max(f.maxX, t.maxX) - 0.001)
        assertNoOverlaps(layout)
    }

    @Test func overlayOnlyASNsAreReported() {
        let graph = GraphBuilder.build(from: repeated(2, [100, 174, 15169]),
                                       options: .init(highlightPath: [999, 15169]))
        #expect(graph.isOverlayOnly(999) && !graph.isOverlayOnly(174))
        #expect(graph.layerByASN[999] != nil)
    }
}
