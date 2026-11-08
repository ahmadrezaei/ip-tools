// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import BGPGraph
import SwiftUI

/// iPad chain: left = you, right = destination (DESIGN 6.11.8).
struct HorizontalChainView: View {
    let route: YourRouteModel

    /// `nodes x 150 + (nodes - 1) x 26 <= width`.
    static func fits(nodes: Int, width: CGFloat) -> Bool {
        CGFloat(nodes) * 150 + CGFloat(max(nodes - 1, 0)) * 26 <= width
    }

    var body: some View {
        if let chain = route.chain {
            HStack(alignment: .center, spacing: 0) {
                ForEach(Array(chain.nodes.enumerated()), id: \.element.id) { index, node in
                    if index > 0 { ChainArrow(style: RouteLayout.rail(into: node, chain: chain)) }
                    Button { route.selection = route.selection == node.id ? nil : node.id } label: {
                        ChainNodeView(node: node, route: route, layout: .column, isSelected: route.selection == node.id,
                                      isLastSeen: RouteLayout.isLastSeen(node, chain: chain), isMeasuring: route.isMeasuring)
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 150, maxWidth: 220)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
