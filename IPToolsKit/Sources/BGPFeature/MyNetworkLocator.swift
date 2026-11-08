// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore
import RIPEstat

public struct MyNetwork: Hashable, Sendable {
    public let ip: String
    public let asn: UInt32?
    public let prefix: String?
    public var name: String?
    public init(ip: String, asn: UInt32?, prefix: String?, name: String? = nil) {
        self.ip = ip
        self.asn = asn
        self.prefix = prefix
        self.name = name
    }
}

/// whats-my-ip -> network-info, cached per `pathGeneration` (<= 30 min). Failures are never cached.
actor MyNetworkLocator {
    static let maxAge: TimeInterval = 30 * 60

    private let api: any RIPEstatAPI
    private let now: @Sendable () -> Date
    private var cached: (generation: Int, date: Date, network: MyNetwork)?
    private var inflight: (generation: Int, task: Task<(network: MyNetwork, complete: Bool)?, Never>)?

    init(api: any RIPEstatAPI, now: @escaping @Sendable () -> Date = { Date() }) {
        self.api = api
        self.now = now
    }

    func current(generation: Int) async -> MyNetwork? {
        if let cached, cached.generation == generation, now().timeIntervalSince(cached.date) < Self.maxAge {
            return cached.network
        }
        if let inflight, inflight.generation == generation {
            return await inflight.task.value?.network
        }
        let api = api
        let task = Task { await Self.lookup(api) }
        inflight = (generation, task)
        let result = await task.value
        if let current = inflight, current.generation == generation { inflight = nil }
        guard let result else { return nil }
        if result.complete { cached = (generation, now(), result.network) }
        return result.network
    }

    /// `complete` is false when network-info failed, so the next call tries again.
    private static func lookup(_ api: any RIPEstatAPI) async -> (network: MyNetwork, complete: Bool)? {
        guard let mine = try? await api.whatsMyIP(), IPAddress(mine.ip) != nil else { return nil }
        guard let info = try? await api.networkInfo(mine.ip) else {
            return (MyNetwork(ip: mine.ip, asn: nil, prefix: nil), false)
        }
        return (MyNetwork(ip: mine.ip, asn: info.originASNs.first, prefix: info.prefix), true)
    }
}
