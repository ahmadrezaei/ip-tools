// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SwiftUI

public struct ExampleChips: View {
    private let examples: [String]
    private let onTap: (String) -> Void

    public init(_ examples: [String], onTap: @escaping (String) -> Void) {
        self.examples = examples
        self.onTap = onTap
    }

    public var body: some View {
        ChipFlowLayout(spacing: 8) {
            ForEach(examples, id: \.self) { example in
                Button(example) { onTap(example) }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
            }
        }
        .padding(.horizontal)
    }
}

/// Centred flow layout: places subviews left to right and starts a new row when the next one does not fit.
struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 8

    private func rows(for subviews: Subviews, maxWidth: CGFloat) -> [[Int]] {
        var rows: [[Int]] = [[]]
        var x: CGFloat = 0
        for index in subviews.indices {
            let width = subviews[index].sizeThatFits(.unspecified).width
            if x > 0, x + width > maxWidth {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append(index)
            x += width + spacing
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var height: CGFloat = 0
        var widest: CGFloat = 0
        let rows = rows(for: subviews, maxWidth: maxWidth)
        for row in rows {
            let sizes = row.map { subviews[$0].sizeThatFits(.unspecified) }
            height += (sizes.map(\.height).max() ?? 0)
            widest = max(widest, sizes.map(\.width).reduce(0, +) + spacing * CGFloat(max(sizes.count - 1, 0)))
        }
        height += spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, maxWidth: bounds.width) {
            let sizes = row.map { subviews[$0].sizeThatFits(.unspecified) }
            let rowWidth = sizes.map(\.width).reduce(0, +) + spacing * CGFloat(max(sizes.count - 1, 0))
            let rowHeight = sizes.map(\.height).max() ?? 0
            var x = bounds.minX + (bounds.width - rowWidth) / 2
            for (offset, index) in row.enumerated() {
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sizes[offset]))
                x += sizes[offset].width + spacing
            }
            y += rowHeight + spacing
        }
    }
}
