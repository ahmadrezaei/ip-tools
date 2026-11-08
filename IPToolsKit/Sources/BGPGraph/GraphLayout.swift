// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import CoreGraphics

public struct LayoutMetrics: Hashable, Sendable {
    public var nodeSize = CGSize(width: 104, height: 44)
    /// Horizontal gap between neighbouring nodes in a row.
    public var nodeSpacing: CGFloat = 10
    /// Vertical gap between one row's nodes and the caption of the row below.
    public var rowSpacing: CGFloat = 44
    public var padding: CGFloat = 16
    /// Height of the caption band above each row.
    public var headerHeight: CGFloat = 18
    /// Minimum line width of the overlay path, a little above the thinnest ordinary edge (1.5).
    public var overlayLineWidth: CGFloat = 3
    public init() {}
}

public struct EdgeGeometry: Identifiable, Hashable, Sendable {
    public let id: String
    public let start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint
    public let lineWidth: CGFloat
    public let kind: GraphEdge.Kind
    public let overlay: GraphEdge.Overlay?

    public init(id: String, start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint,
                lineWidth: CGFloat, kind: GraphEdge.Kind, overlay: GraphEdge.Overlay? = nil) {
        self.id = id
        self.start = start
        self.control1 = control1
        self.control2 = control2
        self.end = end
        self.lineWidth = lineWidth
        self.kind = kind
        self.overlay = overlay
    }
}

public struct GraphLayout: Sendable {
    public let size: CGSize
    public let frames: [NodeID: CGRect]
    public let edges: [EdgeGeometry]
    /// Row captions, top to bottom: `minX` is the left edge, `centerY` the vertical centre of the caption.
    public let rowHeaders: [(layer: Int, minX: CGFloat, centerY: CGFloat)]

    public init(size: CGSize, frames: [NodeID: CGRect], edges: [EdgeGeometry],
                rowHeaders: [(layer: Int, minX: CGFloat, centerY: CGFloat)]) {
        self.size = size
        self.frames = frames
        self.edges = edges
        self.rowHeaders = rowHeaders
    }
}
