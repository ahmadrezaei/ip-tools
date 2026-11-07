// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore
import Observation

public struct TraceSettings: Codable, Hashable, Sendable {
    public var options: TraceOptions = .default
    public var resolveHostnames = true
    public var lookUpASNs = true
    public init() {}
}

@MainActor @Observable public final class SettingsStore {
    public var ping: PingOptions { didSet { save() } }
    public var trace: TraceSettings { didSet { save() } }
    public var addressPreference: AddressPreference { didSet { save() } }

    @ObservationIgnored private let defaults: UserDefaults
    private static let storageKey = "settings.v1"

    private struct Snapshot: Codable {
        var ping: PingOptions
        var trace: TraceSettings
        var addressPreference: AddressPreference
    }

    /// Persists on change (JSON, key "settings.v1").
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            ping = snapshot.ping
            trace = snapshot.trace
            addressPreference = snapshot.addressPreference
        } else {
            ping = .default
            trace = TraceSettings()
            addressPreference = .automatic
        }
    }

    private func save() {
        let snapshot = Snapshot(ping: ping, trace: trace, addressPreference: addressPreference)
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: Self.storageKey) }
    }
}
