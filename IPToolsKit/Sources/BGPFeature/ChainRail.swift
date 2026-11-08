// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SharedUI
import SwiftUI

/// How the link into a node is drawn.
enum RailStyle: Equatable {
    /// Measured link.
    case solid
    /// From BGP, or not reached yet.
    case dashed
    /// Unknown networks in between: dashed with a "?" bubble.
    case gap
}

/// Vertical connector between two chain cards: a 2.5 pt line centred under the 32 pt role circles.
struct ChainRail: View {
    let style: RailStyle
    var label: String?
    var height: CGFloat = 30

    @ScaledMetric(relativeTo: .body) private var circle: CGFloat = 32

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                line
                if style == .gap {
                    Text("?")
                        .font(.caption.weight(.bold))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.cardBackground))
                        .overlay(Circle().strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])))
                }
            }
            .frame(width: circle, height: height)
            .padding(.leading, 12)
            if let label {
                Text(label).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: height)
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(label == nil)
        .accessibilityLabel(label ?? "")
    }

    @ViewBuilder private var line: some View {
        switch style {
        case .solid:
            Capsule().fill(Color.accentColor).frame(width: 2.5)
        case .dashed, .gap:
            VLine().stroke(Color.secondary, style: StrokeStyle(lineWidth: 2.5, lineCap: .butt, dash: [4, 4]))
                .frame(width: 2.5)
        }
    }
}

private struct VLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

/// Horizontal connector for the iPad chain: a 26 pt arrow, or the "?" bubble.
struct ChainArrow: View {
    let style: RailStyle

    var body: some View {
        ZStack {
            switch style {
            case .solid:
                Image(systemName: "arrow.right").font(.body.weight(.semibold)).foregroundStyle(Color.accentColor)
            case .dashed:
                Image(systemName: "arrow.right").font(.body.weight(.semibold)).foregroundStyle(.secondary)
            case .gap:
                Text("?")
                    .font(.caption.weight(.bold))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.cardBackground))
                    .overlay(Circle().strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])))
            }
        }
        .frame(width: 26)
        .accessibilityHidden(true)
    }
}
