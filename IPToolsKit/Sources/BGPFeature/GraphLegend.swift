// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SharedUI
import SwiftUI

/// One compact row at the bottom of the canvas (DESIGN 6.12 item 5). The info button opens "How to read this map".
struct GraphLegend: View {
    var showsYou = false
    var onInfo: () -> Void = {}

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            LegendItems(showsYou: showsYou)
            Spacer(minLength: 0)
            Button(action: onInfo) { Image(systemName: "info.circle").font(.body) }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("How to read this map"))
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .frame(minHeight: 24)
        .background(.bar, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct LegendItems: View {
    var showsYou: Bool
    var body: some View {
        HStack(spacing: 10) {
            ForEach(items(), id: \.title) { item in
                HStack(spacing: 4) {
                    item.mark.frame(width: 14, height: 12)
                    Text(item.title).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
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
