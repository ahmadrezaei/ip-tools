// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore
import RIPEstat
import SharedUI

/// Polls `condition` every 10 ms until it holds or `timeout` passes.
@MainActor func waitUntil(timeout: Duration = .seconds(5), _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

@MainActor func makeSettings() -> SettingsStore {
    let name = "iptools.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return SettingsStore(defaults: defaults)
}

@MainActor func makeRecents(limit: Int = 20) -> RecentsStore {
    let name = "iptools.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return RecentsStore(defaults: defaults, limit: limit)
}

func resolvedTarget(_ text: String, hostname: String? = nil) -> ResolvedTarget {
    let ip = IPAddress(text)!
    return ResolvedTarget(input: hostname ?? text, address: ip, hostname: hostname, allAddresses: [ip])
}

func utc(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: iso)!
}

/// RIPEstat stand-in that answers `network-info` / `as-names` with fixed data and counts calls.
final class FakeRIPEstat: RIPEstatAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var networkInfoCalls: [String] = []
    private var asNamesCalls: [[UInt32]] = []
    var infoByIP: [String: NetworkInfo] = [:]
    var names: [UInt32: String] = [:]

    var networkInfoCallCount: Int { lock.withLock { networkInfoCalls.count } }
    var asNamesCallCount: Int { lock.withLock { asNamesCalls.count } }

    func networkInfo(_ ip: String) async throws -> NetworkInfo {
        lock.withLock { networkInfoCalls.append(ip) }
        guard let info = infoByIP[ip] else { throw RIPEstatError.offline }
        return info
    }

    func asNames(_ asns: [UInt32]) async throws -> [UInt32: String] {
        lock.withLock { asNamesCalls.append(asns) }
        return names.filter { asns.contains($0.key) }
    }

    func prefixOverview(_ prefix: String) async throws -> PrefixOverview { throw RIPEstatError.offline }
    func lookingGlass(_ resource: String) async throws -> LookingGlass { throw RIPEstatError.offline }
    func asOverview(_ asn: UInt32) async throws -> ASOverview { throw RIPEstatError.offline }
    func announcedPrefixes(_ asn: UInt32) async throws -> [String] { throw RIPEstatError.offline }
    func routingStatus(_ prefix: String) async throws -> RoutingStatus { throw RIPEstatError.offline }
}
