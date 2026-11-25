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

    func slot(_ version: IPVersion) -> Slot { version == .v4 ? v4 : v6 }

    /// The address of a family, when it was found.
    func address(_ version: IPVersion) -> IPAddress? {
        if case let .found(address, _) = slot(version) { address } else { nil }
    }

    var isChecking: Bool { v4 == .checking || v6 == .checking }

    var hasFailure: Bool {
        for slot in [v4, v6] { if case .failed = slot { return true } }
        return false
    }

    var bothFailed: Bool {
        if case .failed = v4, case .failed = v6 { return true }
        return false
    }

    var foundAny: Bool { address(.v4) != nil || address(.v6) != nil }
}

actor MyIPLocator {
    static let cacheLifetime: TimeInterval = 30 * 60

    private enum Outcome: Sendable {
        case found(IPAddress, String?), noRoute, mismatch, failed(String)

        var isFailure: Bool { if case .failed = self { true } else { false } }
    }

    private let api: any RIPEstatAPI
    private let reverseName: @Sendable (IPAddress) async -> String?
    private let now: @Sendable () -> Date
    private var cached: MyIPSnapshot?

    init(api: any RIPEstatAPI, reverseName: @escaping @Sendable (IPAddress) async -> String?,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.api = api
        self.reverseName = reverseName
        self.now = now
    }

    /// Yields a snapshot with `.checking` slots first, then one per answer. A fresh cached snapshot of the same
    /// generation is yielded alone. Failures are never cached.
    func snapshot(generation: Int, supportsV4: Bool, supportsV6: Bool, viaVPN: Bool, force: Bool) -> AsyncStream<MyIPSnapshot> {
        let (stream, continuation) = AsyncStream.makeStream(of: MyIPSnapshot.self)
        if !force, let cached, cached.generation == generation, now().timeIntervalSince(cached.fetchedAt) < Self.cacheLifetime {
            continuation.yield(cached)
            continuation.finish()
            return stream
        }
        let task = Task {
            await self.run(generation: generation, supportsV6: supportsV6, viaVPN: viaVPN, continuation: continuation)
            continuation.finish()
        }
        continuation.onTermination = { @Sendable _ in task.cancel() }
        return stream
    }

    private func run(generation: Int, supportsV6: Bool, viaVPN: Bool, continuation: AsyncStream<MyIPSnapshot>.Continuation) async {
        var snapshot = MyIPSnapshot(v4: .checking, v6: supportsV6 ? .checking : .unavailable(.noRoute), viaVPN: viaVPN,
                                    generation: generation, fetchedAt: now())
        continuation.yield(snapshot)
        let versions: [IPVersion] = supportsV6 ? [.v4, .v6] : [.v4]
        var outcomes: [IPVersion: Outcome] = [:]
        await withTaskGroup(of: (IPVersion, Outcome).self) { group in
            for version in versions {
                group.addTask { (version, await self.fetch(version)) }
            }
            for await (version, outcome) in group {
                outcomes[version] = outcome
                Self.place(outcome, version: version, supportsV6: supportsV6, in: &snapshot)
                continuation.yield(snapshot)
            }
        }
        guard !Task.isCancelled else { return }
        // "IPv6-only network" only makes sense when IPv6 did answer.
        if case .noRoute? = outcomes[.v4], case .noRoute? = outcomes[.v6] {
            snapshot.v4 = .unavailable(.noRoute)
            continuation.yield(snapshot)
        }

        // A proxy that breaks raw TLS: ask once the ordinary way and file the answer under its own family.
        if !outcomes.isEmpty, outcomes.values.allSatisfy(\.isFailure), let answer = try? await api.whatsMyIP(),
           let address = IPAddress(answer.ip) {
            let version: IPVersion = address.family == .v4 ? .v4 : .v6
            let name = await reverseName(address)
            Self.place(.found(address, name), version: version, supportsV6: supportsV6, in: &snapshot)
            continuation.yield(snapshot)
        }
        guard !Task.isCancelled else { return }
        if !snapshot.isChecking, !snapshot.hasFailure { cached = snapshot }
    }

    private static func place(_ outcome: Outcome, version: IPVersion, supportsV6: Bool, in snapshot: inout MyIPSnapshot) {
        let slot: MyIPSnapshot.Slot
        switch (outcome, version) {
        case let (.found(address, name), _): slot = .found(address, reverseName: name)
        case (.noRoute, .v4): slot = .unavailable(supportsV6 ? .ipv6OnlyNetwork : .noRoute)
        case (.noRoute, .v6): slot = .unavailable(.noRoute)
        case (.mismatch, .v6): slot = .unavailable(.mismatch)
        case (.mismatch, .v4): slot = .failed(WhoisFailure.myIPMessage(for: PublicIPError.tls))
        case let (.failed(message), _): slot = .failed(message)
        }
        if version == .v4 { snapshot.v4 = slot } else { snapshot.v6 = slot }
    }

    private nonisolated func fetch(_ version: IPVersion) async -> Outcome {
        do {
            let answer = try await api.whatsMyIP(over: version)
            guard let address = IPAddress(answer.ip) else {
                return .failed(WhoisFailure.myIPMessage(for: PublicIPError.tls))
            }
            guard address.family == (version == .v4 ? .v4 : .v6) else { return .mismatch }
            return .found(address, await reverseName(address))
        } catch PublicIPError.noRoute {
            return .noRoute
        } catch {
            return .failed(WhoisFailure.myIPMessage(for: error))
        }
    }
}
