// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SwiftUI

/// Empty state for a tool: a `ContentUnavailableView`, example chips and the shared recents.
public struct ToolEmptyState: View {
    private let title: LocalizedStringKey
    private let systemImage: String
    private let message: LocalizedStringKey
    private let examples: [String]
    private let onExample: (String) -> Void
    private let recents: RecentsStore?
    private let onRecent: ((RecentTarget) -> Void)?

    public init(title: LocalizedStringKey, systemImage: String, message: LocalizedStringKey,
                examples: [String], onExample: @escaping (String) -> Void,
                recents: RecentsStore? = nil, onRecent: ((RecentTarget) -> Void)? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
        self.examples = examples
        self.onExample = onExample
        self.recents = recents
        self.onRecent = onRecent
    }

    public var body: some View {
        VStack(spacing: 8) {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                Text(message)
            }
            .frame(minHeight: 200)
            ExampleChips(examples, onTap: onExample)
            if let recents, let onRecent, !recents.items.isEmpty {
                RecentsList(recents: recents, onPick: onRecent)
                    .padding(.top, 16)
            }
        }
        .padding(.vertical)
    }
}

/// "Recent" card listing the shared recents; tapping one calls `onPick`.
public struct RecentsList: View {
    private let recents: RecentsStore
    private let limit: Int
    private let onPick: (RecentTarget) -> Void

    public init(recents: RecentsStore, limit: Int = 5, onPick: @escaping (RecentTarget) -> Void) {
        self.recents = recents
        self.limit = limit
        self.onPick = onPick
    }

    public var body: some View {
        let items = Array(recents.items.prefix(limit))
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recent")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Button { onPick(item) } label: {
                            RecentRowLabel(item: item).padding(.vertical, 10).padding(.horizontal, 12)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) { recents.remove(item) } label: { Label("Remove", systemImage: "trash") }
                        }
                        if index < items.count - 1 { Divider().padding(.leading, 40) }
                    }
                }
                .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal)
        }
    }
}

/// Centred spinner with a caption, for the Resolving/Loading state.
public struct LoadingStateView: View {
    private let title: LocalizedStringKey

    public init(_ title: LocalizedStringKey) {
        self.title = title
    }

    public var body: some View {
        ProgressView { Text(title) }
            .frame(maxWidth: .infinity, minHeight: 200)
    }
}

#Preview("Empty") {
    ToolEmptyState(title: "Ping a Host", systemImage: "dot.radiowaves.left.and.right",
                   message: "Measure round-trip time to any IPv4 or IPv6 address or hostname.",
                   examples: ["1.1.1.1", "2606:4700:4700::1111", "apple.com"], onExample: { _ in })
}

#Preview("Error") {
    ErrorStateView(ToolError(title: "Couldn't Resolve apple.cmo", message: "Check the spelling or your DNS.",
                             systemImage: "questionmark.circle"), retry: {})
}

#Preview("Loading") { LoadingStateView("Resolving…") }
