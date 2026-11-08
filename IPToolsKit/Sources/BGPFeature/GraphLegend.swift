// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SharedUI
import SwiftUI

/// The legend, wrapping to as many rows as it needs (DESIGN 6.12 item 5). ⓘ and Fit sit trailing.
struct GraphLegend: View {
    var showsYou = false
    var onFit: () -> Void = {}
    var onInfo: () -> Void = {}

    var body: some View {
        LegendItems(showsYou: showsYou)
            .padding(.leading, 12).padding(.vertical, 6)
            .padding(.trailing, 72)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 10) {
                    Button(action: onFit) { Image(systemName: "arrow.up.left.and.arrow.down.right").font(.body) }
                        .accessibilityLabel(Text("Fit graph to screen"))
                    Button(action: onInfo) { Image(systemName: "info.circle").font(.body) }
                        .accessibilityLabel(Text("How to read this map"))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12).padding(.top, 5)
            }
            .background(.bar, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Left-aligned flow: items keep their size and wrap onto the next row.
private struct LegendFlow: Layout {
    var spacing: CGFloat = 10
    var lineSpacing: CGFloat = 4

    private func rows(_ subviews: Subviews, width: CGFloat) -> [[(index: Int, size: CGSize)]] {
        var rows: [[(Int, CGSize)]] = [[]]
        var x: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { rows.append([]); x = 0 }
            rows[rows.count - 1].append((index, size))
            x += size.width + spacing
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let laid = rows(subviews, width: width)
        let height = laid.map { $0.map(\.size.height).max() ?? 0 }.reduce(0, +) + lineSpacing * CGFloat(max(laid.count - 1, 0))
        let used = laid.map { $0.map(\.size.width).reduce(0, +) + spacing * CGFloat(max($0.count - 1, 0)) }.max() ?? 0
        return CGSize(width: proposal.width ?? used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            let rowHeight = row.map(\.size.height).max() ?? 0
            var x = bounds.minX
            for (index, size) in row {
                subviews[index].place(at: CGPoint(x: x, y: y + (rowHeight - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeight + lineSpacing
        }
    }
}

private struct LegendItems: View {
    var showsYou: Bool
    var body: some View {
        LegendFlow(spacing: 10, lineSpacing: 4) {
            ForEach(items(), id: \.title) { item in
                HStack(spacing: 4) {
                    item.mark.frame(width: 14, height: 12)
                    Text(item.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                .fixedSize()
            }
        }
    }

    struct Item { let title: String; let mark: AnyView }

    func items() -> [Item] {
        var list = [
            Item(title: String(localized: "Destination"), mark: AnyView(RoundedRectangle(cornerRadius: 3).fill(Color.accentColor))),
            Item(title: String(localized: "Thicker = more routes"), mark: AnyView(
                VStack(spacing: 2) {
                    Capsule().fill(Color.secondary).frame(height: 1)
                    Capsule().fill(Color.secondary).frame(height: 3)
                })),
            Item(title: String(localized: "RIPE peer"), mark: AnyView(Circle().fill(.green).frame(width: 7, height: 7))),
            Item(title: String(localized: "Grouped (+N more)"), mark: AnyView(
                RoundedRectangle(cornerRadius: 3).strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [2, 2])))),
        ]
        if showsYou {
            list.append(Item(title: String(localized: "You"), mark: AnyView(
                RoundedRectangle(cornerRadius: 3).strokeBorder(Color.green, lineWidth: 2))))
        }
        return list
    }
}

/// "How to read this map" sheet.
struct GraphLegendSheet: View {
    var showsYou = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LegendRow(mark: AnyView(RoundedRectangle(cornerRadius: 3).fill(Color.accentColor)),
                              text: String(localized: "Destination: the network that announces the prefix."))
                    LegendRow(mark: AnyView(VStack(spacing: 2) {
                        Capsule().fill(Color.secondary).frame(height: 1)
                        Capsule().fill(Color.secondary).frame(height: 3)
                    }), text: String(localized: "Thicker lines carry more of the routes."))
                    LegendRow(mark: AnyView(Circle().fill(.green).frame(width: 8, height: 8)),
                              text: String(localized: "RIPE peer: a network that reports its routes to RIPE collectors."))
                    LegendRow(mark: AnyView(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))),
                              text: String(localized: "Grouped (+N more): networks folded together to keep the map readable."))
                    if showsYou {
                        LegendRow(mark: AnyView(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.green, lineWidth: 2)),
                                  text: String(localized: "You: the network your traffic leaves from."))
                    }
                } footer: {
                    Text("Columns count steps away from the destination. Routes are seen by RIPE RIS collectors, not measured from your device.")
                }
            }
            .navigationTitle("How to read this map")
            .inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

private struct LegendRow: View {
    let mark: AnyView
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            mark.frame(width: 24, height: 16)
            Text(text).font(.subheadline)
        }
    }
}
