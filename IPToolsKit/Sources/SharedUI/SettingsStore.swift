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

    private enum CodingKeys: String, CodingKey { case options, resolveHostnames, lookUpASNs }

    /// Tolerant: a missing or unreadable field falls back to its default instead of failing the whole decode.
    public init(from decoder: any Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? container.decodeIfPresent(TolerantTraceOptions.self, forKey: .options) { options = value.options }
        resolveHostnames = (try? container.decodeIfPresent(Bool.self, forKey: .resolveHostnames)) ?? resolveHostnames
        lookUpASNs = (try? container.decodeIfPresent(Bool.self, forKey: .lookUpASNs)) ?? lookUpASNs
    }
}

/// Decodes NetCore's `PingOptions` field by field (it lives outside this module, so it is wrapped here).
/// An absent `count` means "until stopped", which is how `PingOptions` encodes nil.
struct TolerantPingOptions: Decodable {
    var options = PingOptions.default
    private enum CodingKeys: String, CodingKey { case count, interval, timeout, payloadSize }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        options.count = (try? c.decodeIfPresent(Int.self, forKey: .count)) ?? nil
        options.interval = (try? c.decodeIfPresent(TimeInterval.self, forKey: .interval)) ?? options.interval
        options.timeout = (try? c.decodeIfPresent(TimeInterval.self, forKey: .timeout)) ?? options.timeout
        options.payloadSize = (try? c.decodeIfPresent(Int.self, forKey: .payloadSize)) ?? options.payloadSize
    }
}

struct TolerantTraceOptions: Decodable {
    var options = TraceOptions.default
    private enum CodingKeys: String, CodingKey { case maxHops, probesPerHop, timeout }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        options.maxHops = (try? c.decodeIfPresent(Int.self, forKey: .maxHops)) ?? options.maxHops
        options.probesPerHop = (try? c.decodeIfPresent(Int.self, forKey: .probesPerHop)) ?? options.probesPerHop
        options.timeout = (try? c.decodeIfPresent(TimeInterval.self, forKey: .timeout)) ?? options.timeout
    }
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

        init(ping: PingOptions, trace: TraceSettings, addressPreference: AddressPreference) {
            self.ping = ping
            self.trace = trace
            self.addressPreference = addressPreference
        }

        private enum CodingKeys: String, CodingKey { case ping, trace, addressPreference }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            ping = (try? c.decodeIfPresent(TolerantPingOptions.self, forKey: .ping))?.options ?? .default
            trace = (try? c.decodeIfPresent(TraceSettings.self, forKey: .trace)) ?? TraceSettings()
            addressPreference = (try? c.decodeIfPresent(AddressPreference.self, forKey: .addressPreference)) ?? .automatic
        }
    }

    /// Decodes stored settings JSON, tolerating missing or unknown fields (internal for tests).
    static func decodeSnapshot(_ data: Data) -> (ping: PingOptions, trace: TraceSettings, addressPreference: AddressPreference)? {
        guard let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return nil }
        return (snapshot.ping, snapshot.trace, snapshot.addressPreference)
    }

    /// Persists on change (JSON, key "settings.v1").
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let snapshot = Self.decodeSnapshot(data) {
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
