// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import CoreGraphics

public enum LayeredLayout {
    /// Stub: returns an empty layout. The real algorithm (DESIGN §6.4) is owned by the graph agent.
    public static func layout(_ graph: ASGraph, metrics: LayoutMetrics = .init()) -> GraphLayout {
        GraphLayout(size: .zero, frames: [:], edges: [], columnHeaders: [])
    }
}
