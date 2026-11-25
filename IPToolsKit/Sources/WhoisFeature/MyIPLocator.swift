// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore
import RIPEstat

/// Pinned-family public IP lookup for the My IP card (DESIGN §14.5.4).
public struct MyIPSnapshot: Hashable, Sendable {
    public enum Slot: Hashable, Sendable {
        case checking
        case found(IPAddress, reverseName: String?)
        case unavailable(Unavailable)
        case failed(String)
    }

    public enum Unavailable: Hashable, Sendable { case noRoute, ipv6OnlyNetwork, mismatch, offline }

    public var v4: Slot
    public var v6: Slot
    public let viaVPN: Bool
    public let generation: Int
    public let fetchedAt: Date

    public init(v4: Slot, v6: Slot, viaVPN: Bool, generation: Int, fetchedAt: Date) {
        self.v4 = v4
        self.v6 = v6
        self.viaVPN = viaVPN
        self.generation = generation
        self.fetchedAt = fetchedAt
    }
}

actor MyIPLocator {
    private let api: any RIPEstatAPI
    private let reverseName: @Sendable (IPAddress) async -> String?
    private let now: @Sendable () -> Date

    init(api: any RIPEstatAPI, reverseName: @escaping @Sendable (IPAddress) async -> String?,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.api = api
        self.reverseName = reverseName
        self.now = now
    }

    /// Step 0 stub: finishes immediately without yielding.
    func snapshot(generation: Int, supportsV4: Bool, supportsV6: Bool, viaVPN: Bool, force: Bool) -> AsyncStream<MyIPSnapshot> {
        AsyncStream { $0.finish() }
    }
}
