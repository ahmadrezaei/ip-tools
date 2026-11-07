// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SharedUI
import SwiftUI

/// Sheet listing the prefixes an AS announces; picking one maps it.
struct PrefixPickerView: View {
    let asn: UInt32
    let holder: String?
    let prefixes: [String]
    let onPick: (String) -> Void
    var onCancel: () -> Void = {}

    @State private var query = ""

    private var filtered: [String] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return needle.isEmpty ? prefixes : prefixes.filter { $0.lowercased().contains(needle) }
    }

    var body: some View {
        let list = filtered
        let v4 = list.filter { !$0.contains(":") }
        let v6 = list.filter { $0.contains(":") }
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        if let name = BGPText.fullName(holder) { Text(name).font(.headline) }
                        Text("\(prefixes.count.formatted()) prefixes").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                if !v4.isEmpty {
                    Section("IPv4 · \(v4.count.formatted())") { rows(v4) }
                }
                if !v6.isEmpty {
                    Section("IPv6 · \(v6.count.formatted())") { rows(v6) }
                }
                if list.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, prompt: Text("Search prefixes"))
            .navigationTitle(String(localized: "Prefixes announced by AS\(String(asn))"))
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
            }
        }
    }

    private func rows(_ items: [String]) -> some View {
        ForEach(items, id: \.self) { prefix in
            Button { onPick(prefix) } label: {
                Text(verbatim: prefix)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
