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

    /// Opening view: fit if it is readable. Otherwise the graph is scaled to the view width (at least 0.7x, at
    /// most 1x), centred horizontally on the origin node (`originMidX`) when it is wider than the view, with
    /// the origin row (the bottom of the graph) against the bottom edge.
    static func initial(content: CGSize, in view: CGSize, originMidX: CGFloat? = nil) -> ZoomPanState {
        if fitScale(content: content, in: view) >= anchoredScale { return fitted(content: content, in: view) }
        let widthScale = view.width / max(content.width, 1)
        let scale = min(1, max(anchoredScale, widthScale))
        let width = content.width * scale, height = content.height * scale
        var offsetX = (view.width - width) / 2
        if width > view.width, let originMidX { offsetX = view.width / 2 - originMidX * scale }
        let offsetY = height <= view.height ? (view.height - height) / 2 : view.height - height
        return ZoomPanState(scale: scale, offset: CGSize(width: offsetX, height: offsetY))
            .clamped(content: content, in: view)
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
