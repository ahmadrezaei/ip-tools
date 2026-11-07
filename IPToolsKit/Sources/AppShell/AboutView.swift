// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import SharedUI
import SwiftUI

/// The About sections: version, privacy summary, source link, licence, data attribution, Clear History.
/// Appended to each tool's settings sheet (via `\.aboutSection`) and shown in the combined settings.
struct AboutSections: View {
    let environment: AppEnvironment
    @State private var confirmClear = false

    static let repositoryURL = URL(string: "https://github.com/ahmadrezaei/ip-tools")!
    static let ripeStatURL = URL(string: "https://stat.ripe.net")!

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    var body: some View {
        Section("About") {
            LabeledContent("IP Tools", value: Self.versionString)
            Text("No accounts, ads, analytics or tracking. Ping and traceroute run on your device and talk only to the host you enter and your DNS resolver. BGP lookups, and traceroute hop addresses if lookups are on, are sent to RIPEstat (stat.ripe.net) without any identifier. Recent targets and settings stay on this device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Link(destination: Self.repositoryURL) {
                Label("Source code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            LabeledContent("License", value: "MIT")
        }
        Section {
            Link(destination: Self.ripeStatURL) {
                Label("RIPE NCC RIPEstat", systemImage: "network")
            }
        } header: {
            Text("Data sources")
        } footer: {
            Text("BGP data: RIPE NCC RIPEstat, built from RIPE RIS route collectors.")
        }
        Section {
            Button("Clear History", role: .destructive) { confirmClear = true }
                .disabled(environment.recents.items.isEmpty)
                .confirmationDialog("Clear all recent targets?", isPresented: $confirmClear, titleVisibility: .visible) {
                    Button("Clear History", role: .destructive) { environment.recents.clear() }
                }
        }
    }
}

struct AboutView: View {
    let environment: AppEnvironment

    var body: some View {
        Form { AboutSections(environment: environment) }
            .navigationTitle("About")
    }
}

#Preview {
    NavigationStack { AboutView(environment: .preview()) }
}
