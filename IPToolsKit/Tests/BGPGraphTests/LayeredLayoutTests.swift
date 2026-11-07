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
        #expect(layout.size == .zero && layout.frames.isEmpty && layout.edges.isEmpty && layout.columnHeaders.isEmpty)
    }

    @Test func noOverlapsOnRealGraphsAtEveryK() async throws {
        for graph in try await realGraphs() {
            let layout = LayeredLayout.layout(graph)
            #expect(layout.frames.count == graph.nodes.count)
            assertNoOverlaps(layout)
        }
    }

    @Test func columnsAreOrderedByLayerWithOriginOnTheRight() async throws {
        for graph in try await realGraphs() {
            let layout = LayeredLayout.layout(graph)
            var xByLayer: [Int: CGFloat] = [:]
            for node in graph.nodes {
                let frame = try #require(layout.frames[node.id])
                if let x = xByLayer[node.layer] { #expect(x == frame.minX) } else { xByLayer[node.layer] = frame.minX }
            }
            let layers = xByLayer.keys.sorted()
            for (a, b) in zip(layers, layers.dropFirst()) {
                #expect(xByLayer[a]! > xByLayer[b]!, "layer \(a) must be right of layer \(b)")
                #expect(xByLayer[a]! - xByLayer[b]! == metrics.nodeSize.width + metrics.columnSpacing)
            }
            #expect(xByLayer[0] == layout.size.width - metrics.padding - metrics.nodeSize.width)
            #expect(xByLayer[graph.layerCount - 1] == metrics.padding)
        }
    }

    @Test func moreBucketIsLastInItsColumn() async throws {
        let graph = try await realGraphs()[0]
        let layout = LayeredLayout.layout(graph)
        var buckets = 0
        for node in graph.nodes {
            guard case .more = node.id else { continue }
            buckets += 1
            let frame = layout.frames[node.id]!
            for other in graph.nodes where other.layer == node.layer && other.id != node.id {
                #expect(layout.frames[other.id]!.maxY <= frame.minY)
            }
        }
        #expect(buckets == 3)
    }

    @Test func sizeAndVerticalCentringFollowTheFormulas() async throws {
        let graph = try await realGraphs()[0]            // 4 layers, tallest column 7 nodes
        let layout = LayeredLayout.layout(graph)
        let l = CGFloat(graph.layerCount - 1)
        let tallest = CGFloat(graph.layerSizes().max()!)
        let h = tallest * 44 + (tallest - 1) * 12
        #expect(layout.size.width == 24 * 2 + (l + 1) * 112 + l * 56)
        #expect(layout.size.height == 24 * 2 + 18 + h)
        // Origin column (1 node) is vertically centred against the tallest column.
        let origin = layout.frames[.asn(13335)]!
        #expect(origin.midY == 24 + 18 + h / 2)
        // Rows in a column are 44 + 12 apart.
        let col1 = graph.nodes.filter { $0.layer == 1 }.map { layout.frames[$0.id]! }.sorted { $0.minY < $1.minY }
        for (a, b) in zip(col1, col1.dropFirst()) { #expect(b.minY - a.minY == 56) }
        #expect(layout.frames.values.allSatisfy { $0.size == CGSize(width: 112, height: 44) })
    }

    @Test func columnHeadersRunLeftToRightEndingWithTheOrigin() async throws {
        let graph = try await realGraphs()[0]
        let layout = LayeredLayout.layout(graph)
        #expect(layout.columnHeaders.map(\.layer) == [3, 2, 1, 0])
        let xs = layout.columnHeaders.map(\.centerX)
        #expect(xs == xs.sorted())
        #expect(layout.columnHeaders.last?.centerX == layout.frames[.asn(13335)]!.midX)
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

    @Test func barycentreOrderUntanglesColumns() {
        // Origins 10 (more paths) and 20; peer A reaches 20, peer B reaches 10: B must sit above A.
        let paths = repeated(3, [1, 10]) + repeated(1, [2, 20]) + [path(8, 1, 10)]
        // 1 -> 10 (4 paths), 2 -> 20 (1): sorted by barycentre 1 above 2 regardless of ASN order.
        let swapped = repeated(3, [2, 10]) + repeated(1, [1, 20])
        for input in [paths, swapped] {
            let g = GraphBuilder.build(from: input)
            let layout = LayeredLayout.layout(g)
            let top10 = layout.frames[.asn(10)]!.minY < layout.frames[.asn(20)]!.minY
            #expect(top10)
            let toward10 = g.edges.first { $0.to == .asn(10) }!.from
            let toward20 = g.edges.first { $0.to == .asn(20) }!.from
            #expect(layout.frames[toward10]!.minY < layout.frames[toward20]!.minY)
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
            #expect(geometry.start == CGPoint(x: from.maxX, y: from.midY))
            #expect(geometry.end == CGPoint(x: to.minX, y: to.midY))
            let mx = (geometry.start.x + geometry.end.x) / 2
            #expect(geometry.control1 == CGPoint(x: mx, y: geometry.start.y))
            #expect(geometry.control2 == CGPoint(x: mx, y: geometry.end.y))
        }
    }

    @Test func lateralEdgesLoopLeftAndStrokeWidthFollowsCount() {
        let g = GraphBuilder.build(from: [path(1, 2, 20), path(2, 20), path(1, 20), path(1, 2, 20)])
        let layout = LayeredLayout.layout(g)
        let lateral = layout.edges.first { $0.kind == .lateral }
        let geometry = try! #require(lateral)
        let from = layout.frames[.asn(1)]!, to = layout.frames[.asn(2)]!
        #expect(geometry.start == CGPoint(x: from.minX, y: from.midY))
        #expect(geometry.end == CGPoint(x: to.minX, y: to.midY))
        let pull = min(45, 20 + abs(to.midY - from.midY) * 0.25)
        #expect(geometry.control1.x == from.minX - pull && geometry.control2.x == to.minX - pull)
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
        #expect(layout.size == CGSize(width: 24 * 2 + 112, height: 24 * 2 + 18 + 44))
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
