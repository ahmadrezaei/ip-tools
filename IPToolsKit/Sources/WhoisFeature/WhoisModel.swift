// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore
import Observation
import RIPEstat
import SharedUI

@MainActor @Observable public final class WhoisModel {
    public enum Phase: Equatable {
        case myIP                                    // default; field empty or ‹ My IP tapped
        case resolving(String)
        case loading(WhoisSubject)
        case loaded(WhoisResult)
        case local(LocalVerdict)
        case failed(WhoisFailure)
    }

    public enum Classified: Equatable { case subject(WhoisSubject), hostname(String), local(LocalVerdict) }

    public var targetText: String = ""
    public private(set) var phase: Phase = .myIP
    public private(set) var myIP: MyIPSnapshot?
    /// Selected own address; setting it loads that whois if needed.
    public var myFamily: IPVersion = .v4
    public private(set) var myWhois: [IPVersion: WhoisLoad] = [:]
    public private(set) var localAddresses: [LocalAddress] = []
    /// iPad, session only.
    public var inspectorShown: Bool = false

    @ObservationIgnored private let api: any RIPEstatAPI
    @ObservationIgnored private let recents: RecentsStore
    @ObservationIgnored private let router: AppRouter
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let network: NetworkMonitor?
    @ObservationIgnored private let resolve: @Sendable (String, AddressPreference) async throws -> ResolvedTarget
    @ObservationIgnored private let reverseName: @Sendable (IPAddress) async -> String?
    @ObservationIgnored private let readLocalAddresses: @Sendable () -> [LocalAddress]
    @ObservationIgnored private let includeLocation: Bool

    public init(api: any RIPEstatAPI, recents: RecentsStore, router: AppRouter, settings: SettingsStore,
                network: NetworkMonitor? = nil,
                resolve: @escaping @Sendable (String, AddressPreference) async throws -> ResolvedTarget = {
                    try await Resolver.resolve($0, preference: $1)
                },
                reverseName: @escaping @Sendable (IPAddress) async -> String? = { await Resolver.reverseName(for: $0) },
                localAddresses: @escaping @Sendable () -> [LocalAddress] = { LocalInterfaces.current() },
                includeLocation: Bool = true) {
        self.api = api
        self.recents = recents
        self.router = router
        self.settings = settings
        self.network = network
        self.resolve = resolve
        self.reverseName = reverseName
        self.readLocalAddresses = localAddresses
        self.includeLocation = includeLocation
    }

    /// Parses `targetText` (TargetParser .bgp).
    public func lookUp() {}
    /// Drill-down / raw link / embedded IPv4: sets `targetText` too.
    public func lookUp(_ resource: String) {}
    public func cancel() {}
    /// ‹ My IP: clears `targetText`, `phase = .myIP`.
    public func showMyIP() {}
    /// DESIGN §14.5.4 triggers.
    public func appeared() {}
    public func refreshMyIP() {}
    /// Router: pre-fill, auto-start if requested.
    public func handle(_ request: ToolRequest) {}
    /// `router.open(.ping, …)` for the current subject.
    public func ping() {}
    public func trace() {}
    public func map() {}
    public func stopForBackground() {}

    /// DESIGN §14.12 summary or My IP text.
    public var exportText: String { "" }
    /// `exportText` plus raw records.
    public var exportFullText: String { "" }

    /// Pure, no network; nil = invalid input.
    public static func classify(_ text: String) -> Classified? { nil }
}
