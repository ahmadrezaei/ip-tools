// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore
import Observation
import SharedUI

public struct TraceHop: Identifiable, Hashable, Sendable {
    public var id: Int { ttl }
    public let ttl: Int
    public var probes: [ProbeResult]
    public var addresses: [IPAddress]          // distinct, in arrival order
    public var hostname: String?
    public var asn: HopASN?
    public var isDestination: Bool

    public init(ttl: Int, probes: [ProbeResult] = [], addresses: [IPAddress] = [], hostname: String? = nil,
                asn: HopASN? = nil, isDestination: Bool = false) {
        self.ttl = ttl
        self.probes = probes
        self.addresses = addresses
        self.hostname = hostname
        self.asn = asn
        self.isDestination = isDestination
    }
}

@MainActor @Observable public final class TraceModel {
    public enum Phase: Equatable { case idle, resolving, tracing(currentTTL: Int), finished(TraceCompletion), stopped(String?), failed(String) }

    public var targetText: String = ""
    public private(set) var phase: Phase = .idle
    public private(set) var hops: [TraceHop] = []

    @ObservationIgnored let service: any TraceService
    @ObservationIgnored let asnLookup: ASNLookup
    @ObservationIgnored let settings: SettingsStore
    @ObservationIgnored let recents: RecentsStore
    @ObservationIgnored let router: AppRouter
    public var recentsStore: RecentsStore { recents }

    public init(service: any TraceService, asnLookup: ASNLookup, settings: SettingsStore,
                recents: RecentsStore, router: AppRouter) {
        self.service = service
        self.asnLookup = asnLookup
        self.settings = settings
        self.recents = recents
        self.router = router
    }

    /// Stub: UI agent implements.
    public func start() {}
    /// Stub: UI agent implements.
    public func stop(reason: String? = nil) {}

    /// Stub: UI agent implements (format in DESIGN §5.6).
    public var exportText: String { TraceExport.text(hops: hops) }
}
