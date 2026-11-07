// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import BGPGraph
import SwiftUI

/// Edges and column headers, drawn in one `Canvas` under the given pan/zoom transform.
struct GraphEdgesLayer: View {
    let layout: GraphLayout
    let highlight: BGPHighlight?
    var zoom = ZoomPanState()
    var metrics = LayoutMetrics()

    var body: some View {
        Canvas { context, _ in
            context.translateBy(x: zoom.offset.width, y: zoom.offset.height)
            context.scaleBy(x: zoom.scale, y: zoom.scale)
            drawHeaders(&context)
            let (normal, lit) = partition()
            for edge in normal { stroke(edge, lit: false, in: &context) }
            for edge in lit { stroke(edge, lit: true, in: &context) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func partition() -> ([EdgeGeometry], [EdgeGeometry]) {
        let sorted = layout.edges.sorted { $0.lineWidth < $1.lineWidth }
        guard let highlight else { return (sorted, []) }
        return (sorted.filter { !highlight.edges.contains($0.id) }, sorted.filter { highlight.edges.contains($0.id) })
    }

    private func stroke(_ edge: EdgeGeometry, lit: Bool, in context: inout GraphicsContext) {
        var path = Path()
        path.move(to: edge.start)
        path.addCurve(to: edge.end, control1: edge.control1, control2: edge.control2)
        let color: Color
        if lit {
            color = .accentColor
        } else {
            color = Color.secondary.opacity(highlight == nil ? 0.35 : 0.12)
        }
        let width = edge.lineWidth + (lit ? 1 : 0)
        var style = StrokeStyle(lineWidth: width, lineCap: .round)
        if edge.kind != .forward { style.dash = [5, 4] }
        context.stroke(path, with: .color(color), style: style)
    }

    private func drawHeaders(_ context: inout GraphicsContext) {
        for header in layout.columnHeaders {
            let title: String
            switch header.layer {
            case 0: title = String(localized: "ORIGIN")
            case 1: title = String(localized: "1 HOP")
            default: title = String(localized: "\(header.layer) HOPS")
            }
            let text = Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            context.draw(text, at: CGPoint(x: header.centerX, y: metrics.padding + metrics.headerHeight / 2), anchor: .center)
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
        .onChange(of: model.layoutVersion) { _, _ in
            userMoved = false
            applyInitial(animated: false)
        }
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
            GraphEdgesLayer(layout: layout, highlight: model.highlight, zoom: zoom)
            ZStack(alignment: .topLeading) {
                ForEach(nodes) { node in
                    if let frame = layout.frames[node.id], let summary = stats?.summary(for: node.id, graph: result.graph) {
                        let name = node.id.asnValue.flatMap { BGPText.shortName(result.holder(of: $0)) }
                        Button { tap(node) } label: {
                            NodeView(node: node, name: name, isSelected: selectedID == node.id,
                                     isDimmed: model.highlight.map { !$0.nodes.contains(node.id) } ?? false)
                        }
                        .buttonStyle(.plain)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .accessibilityLabel(BGPText.accessibilityLabel(for: summary, names: result.names))
                        .accessibilityHint(Text("Double-tap to highlight its paths"))
                        .accessibilityAddTraits(selectedID == node.id ? .isSelected : [])
                        .accessibilitySortPriority(order[node.id] ?? 0)
                    }
                }
            }
            .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
            .scaleEffect(zoom.scale, anchor: .topLeading)
            .offset(zoom.offset)
            .animation(.snappy(duration: 0.2), value: result.names.count)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .simultaneousGesture(pan)
        .simultaneousGesture(magnify)
        .overlay(alignment: .bottomTrailing) {
            Button { fit(animated: true) } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.body.weight(.semibold))
                    .padding(10)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Fit graph to screen"))
            .padding(12)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "AS path graph, \(nodes.count) networks, \(layout.columnHeaders.count) columns"))
        .accessibilityAction(named: Text("Show as list")) { model.displayMode = .list }
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
        set(ZoomPanState.initial(content: contentSize, in: viewSize), animated: animated)
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
        if case .more = node.id {
            model.requestDetails(for: node.id)
        } else {
            model.select(node.id)
        }
    }

    /// Higher priority is read first: origin column outward, top to bottom.
    private func readingOrder(nodes: [GraphNode], layout: GraphLayout) -> [NodeID: Double] {
        var order: [NodeID: Double] = [:]
        for node in nodes {
            let y = layout.frames[node.id]?.minY ?? 0
            order[node.id] = 1_000_000 - Double(node.layer) * 10_000 - Double(y)
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
