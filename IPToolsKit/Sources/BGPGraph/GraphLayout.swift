// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import CoreGraphics

public struct LayoutMetrics: Hashable, Sendable {
    public var nodeSize = CGSize(width: 112, height: 44)
    public var columnSpacing: CGFloat = 56
    public var rowSpacing: CGFloat = 12
    public var padding: CGFloat = 24
    public var headerHeight: CGFloat = 18
    public init() {}
}

public struct EdgeGeometry: Identifiable, Hashable, Sendable {
    public let id: String
    public let start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint
    public let lineWidth: CGFloat
    public let kind: GraphEdge.Kind

    public init(id: String, start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint,
                lineWidth: CGFloat, kind: GraphEdge.Kind) {
        self.id = id
        self.start = start
        self.control1 = control1
        self.control2 = control2
        self.end = end
        self.lineWidth = lineWidth
        self.kind = kind
    }
}

public struct GraphLayout: Sendable {
    public let size: CGSize
    public let frames: [NodeID: CGRect]
    public let edges: [EdgeGeometry]
    public let columnHeaders: [(layer: Int, centerX: CGFloat)]

    public init(size: CGSize, frames: [NodeID: CGRect], edges: [EdgeGeometry],
                columnHeaders: [(layer: Int, centerX: CGFloat)]) {
        self.size = size
        self.frames = frames
        self.edges = edges
        self.columnHeaders = columnHeaders
    }
}
