// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import NetCore
import SharedUI
import SwiftUI

public struct PingSettingsView: View {
    @Bindable private var settings: SettingsStore
    @Environment(\.aboutSection) private var about
    private let showsAbout: Bool
    @State private var showCustom = false

    /// `showsAbout` appends the app shell's About section (when one is injected) to the form.
    public init(settings: SettingsStore, showsAbout: Bool = true) {
        self.settings = settings
        self.showsAbout = showsAbout
    }

    private static let counts: [Int?] = [5, 10, 20, 50, 100, nil]
    private static let intervals: [Double] = [0.2, 0.5, 1, 2]
    private static let timeouts: [Double] = [1, 2, 5]
    private static let sizes: [Int] = [16, 56, 120, 512, 1024, 1472]

    public var body: some View {
        Form {
            Section {
                Picker("Count", selection: $settings.ping.count) {
                    ForEach(Self.counts, id: \.self) { count in
                        if let count { Text("\(count)").tag(Optional(count)) } else { Text("Until stopped").tag(Optional<Int>.none) }
                    }
                    if let custom = PingCount.customValue(settings.ping.count) {
                        Text("Custom (\(custom))").tag(Optional(custom))
                    }
                }
                Button("Custom…") { showCustom = true }
                Picker("Interval", selection: $settings.ping.interval) {
                    ForEach(Self.intervals, id: \.self) { Text("\($0, format: .number) s").tag($0) }
                }
                Picker("Timeout", selection: $settings.ping.timeout) {
                    ForEach(Self.timeouts, id: \.self) { Text("\($0, format: .number) s").tag($0) }
                }
                Picker("Packet size", selection: $settings.ping.payloadSize) {
                    ForEach(Self.sizes, id: \.self) { Text("\($0) bytes").tag($0) }
                }
            } footer: {
                Text("Packet size is the payload in bytes. IPv6 is limited to 1452.")
            }
            Section {
                Picker("IP version", selection: $settings.addressPreference) {
                    Text("Automatic").tag(AddressPreference.automatic)
                    Text("IPv4").tag(AddressPreference.ipv4)
                    Text("IPv6").tag(AddressPreference.ipv6)
                }
            } footer: {
                Text("Shared with Traceroute. Automatic follows the system's address ordering.")
            }
            if showsAbout, let about { about }
        }
        .pingCountAlert(isPresented: $showCustom, count: $settings.ping.count)
        .navigationTitle("Ping Settings")
    }
}

#Preview {
    NavigationStack { PingSettingsView(settings: SettingsStore(defaults: UserDefaults(suiteName: "preview.pingsettings") ?? .standard)) }
}
