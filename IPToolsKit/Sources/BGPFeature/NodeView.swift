// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import BGPGraph
import SwiftUI

/// One AS (or the "+N more" bucket) in the graph.
struct NodeView: View {
    let node: GraphNode
    let name: String?
    var isSelected = false
    var isDimmed = false

    private var isOrigin: Bool { node.isOrigin }

    var body: some View {
        ZStack {
            shape.fill(.background)
            shape.fill(isOrigin ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.06)))
            outline
            label
            if node.isPeer, case .asn = node.id {
                Circle().fill(.green).frame(width: 7, height: 7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(5)
            }
        }
        .opacity(isDimmed ? 0.35 : 1)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .contentShape(shape)
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 10, style: .continuous) }

    @ViewBuilder private var outline: some View {
        if case .more = node.id {
            shape.strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: isSelected ? 2.5 : 1.2, dash: [4, 3]))
        } else if isSelected {
            shape.strokeBorder(Color.accentColor, lineWidth: 2.5)
        } else {
            shape.strokeBorder(Color.primary.opacity(isOrigin ? 0 : 0.18), lineWidth: 1)
        }
    }

    private var label: some View {
        VStack(spacing: 1) {
            switch node.id {
            case let .asn(asn):
                Text(verbatim: "AS\(asn)")
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(isOrigin ? Color.white : Color.primary)
                if let name {
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(isOrigin ? Color.white.opacity(0.85) : Color.secondary)
                        .lineLimit(1)
                }
            case .more:
                Text("+\(node.collapsed.count) more")
                    .font(.subheadline.weight(.semibold))
                Text("\(node.pathCount) paths")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 8)
    }
}
