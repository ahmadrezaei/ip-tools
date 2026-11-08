// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import CoreGraphics

/// Pan/zoom transform of the graph: `screen = offset + scale * content`.
struct ZoomPanState: Equatable {
    var scale: CGFloat = 1
    var offset: CGSize = .zero

    static let maxScale: CGFloat = 3
    static let minVisible: CGFloat = 80
    static let anchoredScale: CGFloat = 0.7

    static func fitScale(content: CGSize, in view: CGSize) -> CGFloat {
        guard content.width > 0, content.height > 0, view.width > 0, view.height > 0 else { return 1 }
        return min(view.width / content.width, view.height / content.height)
    }

    /// Lowest zoom allowed: 0.3, or the fit scale when the graph is huge.
    static func minScale(content: CGSize, in view: CGSize) -> CGFloat {
        min(0.3, fitScale(content: content, in: view))
    }

    /// The whole graph, centred.
    static func fitted(content: CGSize, in view: CGSize) -> ZoomPanState {
        let scale = min(fitScale(content: content, in: view), 1)
        return ZoomPanState(scale: scale, offset: CGSize(width: (view.width - content.width * scale) / 2,
                                                         height: (view.height - content.height * scale) / 2))
    }

    /// Where the opening view should look when a your-path overlay is drawn (content coordinates).
    struct PathFocus: Equatable {
        /// The origin node's frame.
        var origin: CGRect
        /// The YOU node: the overlay node farthest from the origin.
        var you: CGRect
        /// Horizontal extent of the overlay nodes plus the origin.
        var minX: CGFloat
        var maxX: CGFloat

        init(origin: CGRect, you: CGRect, minX: CGFloat, maxX: CGFloat) {
            self.origin = origin
            self.you = you
            self.minX = minX
            self.maxX = maxX
        }

        /// Nil when there are no overlay frames.
        init?(origin: CGRect, overlay: [CGRect]) {
            guard let first = overlay.first else { return nil }
            func distance(_ frame: CGRect) -> CGFloat {
                hypot(frame.midX - origin.midX, frame.midY - origin.midY)
            }
            let far = overlay.dropFirst().reduce(first) { distance($1) > distance($0) ? $1 : $0 }
            let lows = overlay.map(\.minX) + [origin.minX]
            let highs = overlay.map(\.maxX) + [origin.maxX]
            self.init(origin: origin, you: far, minX: lows.min() ?? origin.minX, maxX: highs.max() ?? origin.maxX)
        }
    }

    static let youMargin: CGFloat = 8

    /// Opening view: the graph fills the view height (at least 0.7x, at most 1.0x), whatever its width, with the
    /// origin row (the bottom of the graph) against the bottom edge when the graph is taller than the view.
    /// Horizontally it centres on the your-path span (overlay nodes plus origin) when that fits the view;
    /// otherwise it favours the YOU node and shows as much of the origin as fits. Without an overlay it
    /// centres on the origin node (`originMidX`).
    static func initial(content: CGSize, in view: CGSize, originMidX: CGFloat? = nil,
                        path: PathFocus? = nil) -> ZoomPanState {
        guard content.width > 0, content.height > 0, view.width > 0, view.height > 0 else { return ZoomPanState() }
        let scale = min(1.0, max(anchoredScale, view.height / content.height))
        let width = content.width * scale, height = content.height * scale
        var offsetX = view.width / 2 - (originMidX ?? content.width / 2) * scale
        if let path {
            offsetX = pathOffsetX(path, scale: scale, viewWidth: view.width)
        }
        if width > view.width { offsetX = min(max(offsetX, view.width - width), 0) }
        let offsetY = height <= view.height ? (view.height - height) / 2 : view.height - height
        return ZoomPanState(scale: scale, offset: CGSize(width: offsetX, height: offsetY))
            .clamped(content: content, in: view)
    }

    private static func pathOffsetX(_ path: PathFocus, scale: CGFloat, viewWidth: CGFloat) -> CGFloat {
        let spanWidth = (path.maxX - path.minX) * scale
        if spanWidth <= viewWidth {
            return viewWidth / 2 - (path.minX + path.maxX) / 2 * scale
        }
        let margin = youMargin
        if path.origin.midX >= path.you.midX {
            return margin - path.you.minX * scale
        }
        return viewWidth - margin - path.you.maxX * scale
    }

    /// Keeps at least `minVisible` points of the graph on screen on each axis.
    func clamped(content: CGSize, in view: CGSize) -> ZoomPanState {
        var result = self
        let width = content.width * scale, height = content.height * scale
        let keep = Self.minVisible
        result.offset.width = min(max(offset.width, keep - width), view.width - keep)
        result.offset.height = min(max(offset.height, keep - height), view.height - keep)
        return result
    }

    /// Multiplies the scale by `ratio`, keeping the content point under `point` fixed.
    func zoomed(by ratio: CGFloat, at point: CGPoint, minScale: CGFloat) -> ZoomPanState {
        let target = min(max(scale * ratio, minScale), Self.maxScale)
        let factor = target / scale
        return ZoomPanState(scale: target, offset: CGSize(width: point.x - (point.x - offset.width) * factor,
                                                          height: point.y - (point.y - offset.height) * factor))
    }

    /// 1.0x with the content point under `point` staying put.
    func actualSize(at point: CGPoint, minScale: CGFloat) -> ZoomPanState {
        zoomed(by: 1 / scale, at: point, minScale: minScale)
    }
}
