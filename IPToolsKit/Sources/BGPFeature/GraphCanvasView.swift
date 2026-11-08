// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import BGPGraph
import SwiftUI

/// Edges and row captions, drawn in one `Canvas` under the given pan/zoom transform.
struct GraphEdgesLayer: View {
    let layout: GraphLayout
    let highlight: BGPHighlight?
    /// Dim the overlay path (a node is selected that is not on it).
    var overlayDimmed = false
    var zoom = ZoomPanState()

    var body: some View {
        Canvas { context, _ in
            context.translateBy(x: zoom.offset.width, y: zoom.offset.height)
            context.scaleBy(x: zoom.scale, y: zoom.scale)
            let (normal, lit) = partition()
            for edge in normal { stroke(edge, lit: false, in: &context) }
            for edge in lit { stroke(edge, lit: true, in: &context) }
            for edge in layout.edges where edge.overlay != nil { strokeOverlay(edge, in: &context) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func partition() -> ([EdgeGeometry], [EdgeGeometry]) {
        // Overlay edges are drawn by `strokeOverlay`, on top, at least as wide as the edge they replace.
        let sorted = layout.edges.filter { $0.overlay == nil }.sorted { $0.lineWidth < $1.lineWidth }
        guard let highlight else { return (sorted, []) }
        return (sorted.filter { !highlight.edges.contains($0.id) }, sorted.filter { highlight.edges.contains($0.id) })
    }

    private func curve(_ edge: EdgeGeometry) -> Path {
        var path = Path()
        path.move(to: edge.start)
        path.addCurve(to: edge.end, control1: edge.control1, control2: edge.control2)
        return path
    }

    private func stroke(_ edge: EdgeGeometry, lit: Bool, in context: inout GraphicsContext) {
        let color: Color
        if lit {
            color = .accentColor
        } else {
            color = Color.secondary.opacity(highlight == nil ? 0.35 : 0.12)
        }
        let width = edge.lineWidth + (lit ? 1 : 0)
        var style = StrokeStyle(lineWidth: width, lineCap: .round)
        if edge.kind != .forward { style.dash = [5, 4] }
        context.stroke(curve(edge), with: .color(color), style: style)
    }

    /// Your path: system blue, solid for known hops and dashed for the unknown stretch. Where the selection
    /// highlight runs over it, the highlight colour goes underneath and a thin blue line stays on top.
    private func strokeOverlay(_ edge: EdgeGeometry, in context: inout GraphicsContext) {
        var style = StrokeStyle(lineWidth: edge.lineWidth, lineCap: .round)
        if edge.overlay == .unknownSegment { style.dash = [7, 5] }
        if highlight?.edges.contains(edge.id) == true {
            var wide = style
            wide.lineWidth = edge.lineWidth + 1
            context.stroke(curve(edge), with: .color(Color.accentColor), style: wide)
            var thin = style
            thin.lineWidth = 1.5
            context.stroke(curve(edge), with: .color(Color.blue), style: thin)
            return
        }
        let opacity = overlayDimmed ? 0.2 : 1.0
        context.stroke(curve(edge), with: .color(Color.blue.opacity(opacity)), style: style)
    }
}

/// Row captions (ORIGIN / 1 HOP / 2 HOPS), drawn in screen space and pinned to the left edge of the viewport.
struct RowCaptionsLayer: View {
    let layout: GraphLayout
    var zoom = ZoomPanState()

    var body: some View {
        Canvas { context, size in
            for header in layout.rowHeaders {
                let y = zoom.offset.height + header.centerY * zoom.scale
                guard y >= -10, y <= size.height + 10 else { continue }
                let x = max(8, zoom.offset.width + header.minX * zoom.scale)
                let label = context.resolve(Text(Self.title(header.layer)).font(.caption2.weight(.semibold)).foregroundStyle(.secondary))
                let textSize = label.measure(in: size)
                let box = CGRect(x: x - 4, y: y - textSize.height / 2 - 2, width: textSize.width + 8, height: textSize.height + 4)
                context.fill(Path(roundedRect: box, cornerRadius: 5), with: .color(Self.background.opacity(0.85)))
                context.draw(label, at: CGPoint(x: x, y: y), anchor: .leading)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static var background: Color {
        #if os(iOS)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    static func title(_ layer: Int) -> String {
        switch layer {
        case 0: String(localized: "ORIGIN")
        case 1: String(localized: "1 HOP")
        default: String(localized: "\(layer) HOPS")
        }
    }
}

/// Interactive graph: pinch to zoom, drag to pan, tap a node to highlight the paths through it.
struct GraphCanvasView: View {
    let model: BGPMapModel

    @State private var zoom = ZoomPanState()
    @State private var viewSize: CGSize = .zero
    @State private var lastTranslation: CGSize = .zero
    @State private var lastMagnification: CGFloat = 1
    @State private var userMoved = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if let layout = model.layout, let result = model.result, !layout.frames.isEmpty {
                    surface(layout: layout, result: result, size: geo.size)
                } else {
                    ContentUnavailableView("Nothing to draw", systemImage: "point.3.connected.trianglepath.dotted",
                                           description: Text("No usable AS paths were returned for this prefix."))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.04)))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onAppear { updateSize(geo.size, initial: true) }
            .onChange(of: geo.size) { _, new in updateSize(new, initial: false) }
        }
        .onChange(of: model.graphToken) { _, _ in
            userMoved = false
            applyInitial(animated: false)
        }
        .onChange(of: model.layoutVersion) { _, _ in
            if userMoved {
                zoom = zoom.clamped(content: contentSize, in: viewSize)
            } else {
                applyInitial(animated: false)
            }
        }
        .onChange(of: model.fitToken) { _, _ in fit(animated: true) }
        .sensoryFeedback(.selection, trigger: model.selection)
    }

    private var contentSize: CGSize { model.layout?.size ?? .zero }
    private var minScale: CGFloat { ZoomPanState.minScale(content: contentSize, in: viewSize) }

    private func surface(layout: GraphLayout, result: BGPResult, size: CGSize) -> some View {
        let stats = model.stats
        let nodes = result.graph.nodes
        let selectedID = model.selectedNodeID
        let order = readingOrder(nodes: nodes, layout: layout)
        return ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture(count: 2).onEnded { toggleFit(at: $0.location) })
                .gesture(SpatialTapGesture(count: 1).onEnded { _ in model.selection = nil })
            GraphEdgesLayer(layout: layout, highlight: model.highlight, overlayDimmed: model.overlayDimmed, zoom: zoom)
            ZStack(alignment: .topLeading) {
                ForEach(nodes) { node in
                    if let frame = layout.frames[node.id], let summary = stats?.summary(for: node.id, graph: result.graph) {
                        let name = node.id.asnValue.flatMap { BGPText.shortName(model.holder(of: $0)) }
                        nodeButton(node, frame: frame, summary: summary, name: name, result: result,
                                   selectedID: selectedID, order: order)
                    }
                }
            }
            .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
            .scaleEffect(zoom.scale, anchor: .topLeading)
            .offset(zoom.offset)
            .animation(.snappy(duration: 0.2), value: result.names.count)
            RowCaptionsLayer(layout: layout, zoom: zoom)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .highPriorityGesture(pan)
        .simultaneousGesture(magnify)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(canvasLabel(nodeCount: nodes.count, rows: layout.rowHeaders.count))
        .accessibilityAction(named: Text("Show as list")) { model.displayMode = .list }
    }

    @ViewBuilder
    private func nodeButton(_ node: GraphNode, frame: CGRect, summary: BGPStats.Summary, name: String?,
                            result: BGPResult, selectedID: NodeID?, order: [NodeID: Double]) -> some View {
        let dimmed = model.highlight.map { !$0.nodes.contains(node.id) } ?? false
        let onPath = result.graph.highlightPathNodeIDs.contains(node.id)
        let isSelected = selectedID == node.id
        Button { tap(node) } label: {
            NodeView(node: node, name: name, isSelected: isSelected, isDimmed: dimmed, isOnPath: onPath, isYou: isYou(node))
        }
        .buttonStyle(.plain)
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
        .accessibilityLabel(nodeLabel(node, summary: summary, result: result))
        .accessibilityHint(Text("Double-tap to highlight its paths"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilitySortPriority(order[node.id] ?? 0)
    }

    private func canvasLabel(nodeCount: Int, rows: Int) -> String {
        let base = String(localized: "AS path graph, \(nodeCount) networks, \(rows) rows")
        guard model.route.pathStatus != .hidden else { return base }
        let sentence = model.route.accessibilitySentence
        return sentence.isEmpty ? base : base + ". " + sentence
    }

    private func nodeLabel(_ node: GraphNode, summary: BGPStats.Summary, result: BGPResult) -> String {
        var prefix = ""
        if isYou(node) {
            prefix = String(localized: "Your network, ")
        } else if result.graph.highlightPathNodeIDs.contains(node.id) {
            prefix = String(localized: "On your path, ")
        }
        return prefix + BGPText.accessibilityLabel(for: summary, names: result.names)
    }

    private func isYou(_ node: GraphNode) -> Bool {
        guard let mine = model.myASN, case let .asn(asn) = node.id else { return false }
        return asn == mine
    }

    // MARK: Gestures

    private var pan: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                let delta = CGSize(width: value.translation.width - lastTranslation.width,
                                   height: value.translation.height - lastTranslation.height)
                lastTranslation = value.translation
                userMoved = true
                var next = zoom
                next.offset.width += delta.width
                next.offset.height += delta.height
                zoom = next.clamped(content: contentSize, in: viewSize)
            }
            .onEnded { _ in lastTranslation = .zero }
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let ratio = value.magnification / lastMagnification
                lastMagnification = value.magnification
                userMoved = true
                zoom = zoom.zoomed(by: ratio, at: value.startLocation, minScale: minScale)
                    .clamped(content: contentSize, in: viewSize)
            }
            .onEnded { _ in lastMagnification = 1 }
    }

    // MARK: Fit

    private func updateSize(_ size: CGSize, initial: Bool) {
        let changed = size != viewSize
        viewSize = size
        guard changed else { return }
        if initial || !userMoved { applyInitial(animated: false) }
    }

    private func applyInitial(animated: Bool) {
        guard viewSize.width > 0, contentSize.width > 0 else { return }
        var originFrame: CGRect?
        var focus: ZoomPanState.PathFocus?
        if let layout = model.layout, let graph = model.result?.graph, let origin = graph.origins.first {
            originFrame = layout.frames[.asn(origin)]
            let frames = graph.highlightPathNodeIDs.compactMap { layout.frames[$0] }
            if let originFrame { focus = ZoomPanState.PathFocus(origin: originFrame, overlay: frames) }
        }
        let state = ZoomPanState.initial(content: contentSize, in: viewSize, originMidX: originFrame?.midX, path: focus)
        set(state, animated: animated)
    }

    private func fit(animated: Bool) {
        userMoved = true
        set(ZoomPanState.fitted(content: contentSize, in: viewSize), animated: animated)
    }

    private func toggleFit(at point: CGPoint) {
        userMoved = true
        if abs(zoom.scale - 1) > 0.02 {
            set(zoom.actualSize(at: point, minScale: minScale).clamped(content: contentSize, in: viewSize), animated: true)
        } else {
            set(ZoomPanState.fitted(content: contentSize, in: viewSize), animated: true)
        }
    }

    private func set(_ state: ZoomPanState, animated: Bool) {
        if animated && !reduceMotion {
            withAnimation(.snappy(duration: 0.3)) { zoom = state }
        } else {
            zoom = state
        }
    }

    private func tap(_ node: GraphNode) {
        var opensDetails = isYou(node)
        if case .more = node.id { opensDetails = true }
        if opensDetails {
            model.requestDetails(for: node.id)
        } else {
            model.select(node.id)
        }
    }

    /// Higher priority is read first: origin row outward, left to right.
    private func readingOrder(nodes: [GraphNode], layout: GraphLayout) -> [NodeID: Double] {
        var order: [NodeID: Double] = [:]
        for node in nodes {
            let x = layout.frames[node.id]?.minX ?? 0
            order[node.id] = 1_000_000 - Double(node.layer) * 10_000 - Double(x)
        }
        return order
    }
}

extension NodeID {
    var asnValue: UInt32? {
        if case let .asn(asn) = self { return asn }
        return nil
    }
}
