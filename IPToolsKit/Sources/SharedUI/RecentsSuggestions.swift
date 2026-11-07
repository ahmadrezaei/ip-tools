// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SwiftUI

/// Suggestion list shown under the target field while it is focused.
struct RecentsSuggestions: View {
    let suggestions: [RecentTarget]
    let onPick: (RecentTarget) -> Void
    let onDelete: (RecentTarget) -> Void

    private let rowHeight: CGFloat = 52

    var body: some View {
        List {
            ForEach(suggestions) { item in
                Button { onPick(item) } label: {
                    RecentRowLabel(item: item)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { onDelete(item) } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
        .listStyle(.plain)
        .scrollDisabled(true)
        .frame(height: rowHeight * CGFloat(suggestions.count))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// "1.1.1.1" over "Ping · 2 min ago".
struct RecentRowLabel: View {
    let item: RecentTarget

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.display).lineLimit(1).truncationMode(.middle)
                (Text(item.lastTool.title) + Text(verbatim: " · \(Format.relative(item.date))"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}
