// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SharedUI
import SwiftUI

/// iPad / Mac sidebar: tools, recents, and a Settings row.
struct Sidebar: View {
    let environment: AppEnvironment
    @Binding var showSettings: Bool

    var body: some View {
        @Bindable var router = environment.router
        List(selection: Binding<Tool?>(get: { router.selectedTool }, set: { if let tool = $0 { router.selectedTool = tool } })) {
            Section("Tools") {
                ForEach(Tool.allCases) { tool in
                    Label(tool.title, systemImage: tool.systemImage).tag(tool)
                }
            }
            if !environment.recents.items.isEmpty {
                Section("Recent") {
                    ForEach(environment.recents.items) { item in
                        Button {
                            router.open(item.lastTool, target: item.display, autostart: false)
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.display).lineLimit(1).truncationMode(.middle)
                                (Text(item.lastTool.title) + Text(verbatim: " · \(Format.relative(item.date))"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { environment.recents.remove(item) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            Section {
                Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                    .accessibilityIdentifier("sidebarSettings")
            }
        }
        .navigationTitle("IP Tools")
    }
}

#Preview {
    NavigationStack { Sidebar(environment: .preview(), showSettings: .constant(false)) }
}
