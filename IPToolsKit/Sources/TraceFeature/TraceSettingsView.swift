// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import NetCore
import SharedUI
import SwiftUI

public struct TraceSettingsView: View {
    @Bindable private var settings: SettingsStore
    @Environment(\.aboutSection) private var about
    private let showsAbout: Bool

    /// `showsAbout` appends the app shell's About section (when one is injected) to the form.
    public init(settings: SettingsStore, showsAbout: Bool = true) {
        self.settings = settings
        self.showsAbout = showsAbout
    }

    private static let maxHops = [15, 30, 64]
    private static let timeouts: [Double] = [1, 2, 3]
    private static let probes = [1, 3]

    public var body: some View {
        Form {
            Section {
                Picker("Max hops", selection: $settings.trace.options.maxHops) {
                    ForEach(Self.maxHops, id: \.self) { Text("\($0)").tag($0) }
                }
                Picker("Timeout per probe", selection: $settings.trace.options.timeout) {
                    ForEach(Self.timeouts, id: \.self) { Text("\($0, format: .number) s").tag($0) }
                }
                Picker("Probes per hop", selection: $settings.trace.options.probesPerHop) {
                    ForEach(Self.probes, id: \.self) { Text("\($0)").tag($0) }
                }
            }
            Section {
                Toggle("Resolve hostnames (reverse DNS)", isOn: $settings.trace.resolveHostnames)
                Toggle("Look up networks (ASN, via RIPEstat)", isOn: $settings.trace.lookUpASNs)
            } footer: {
                Text("Sends the public hop IP addresses to RIPEstat (RIPE NCC) to find which network they belong to.")
            }
            Section {
                Picker("IP version", selection: $settings.addressPreference) {
                    Text("Automatic").tag(AddressPreference.automatic)
                    Text("IPv4").tag(AddressPreference.ipv4)
                    Text("IPv6").tag(AddressPreference.ipv6)
                }
            } footer: {
                Text("Shared with Ping. Automatic follows the system's address ordering.")
            }
            if showsAbout, let about { about }
        }
        .navigationTitle("Traceroute Settings")
    }
}

#Preview {
    NavigationStack { TraceSettingsView(settings: SettingsStore(defaults: UserDefaults(suiteName: "preview.tracesettings") ?? .standard)) }
}
