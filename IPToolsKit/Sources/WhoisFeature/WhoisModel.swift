// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore
import Observation
import RIPEstat
import SharedUI

/// The NetCore tables classification relies on. Defaults are the real ones; tests swap them.
struct WhoisRules: Sendable {
    var specialRange: @Sendable (IPAddress, Int) -> SpecialPurposeRange?
    var reservedASN: @Sendable (UInt32) -> ReservedASN?
    var embeddedIPv4: @Sendable (IPAddress) -> IPAddress?
    var masked: @Sendable (IPAddress, Int) -> IPAddress

    static let live = WhoisRules(
        specialRange: { SpecialPurposeRange.containing($0, length: $1) },
        reservedASN: { ReservedASN.lookup($0) },
        embeddedIPv4: { $0.embeddedIPv4 },
        masked: { $0.masked(to: $1) })
}

/// What the model reads from `NetworkMonitor`; tests supply their own.
struct WhoisNetworkState {
    var online = true
    var supportsIPv4 = true
    var supportsIPv6 = true
    var usesVPN = false
    var generation = 0
}

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
    public var myFamily: IPVersion = .v4 {
        didSet {
            guard oldValue != myFamily, !adjustingFamily else { return }
            userPickedFamily = true
            loadMyWhoisIfNeeded()
        }
    }
    public private(set) var myWhois: [IPVersion: WhoisLoad] = [:]
    public private(set) var localAddresses: [LocalAddress] = []
    /// iPad, session only.
    public var inspectorShown: Bool = false
    /// Other addresses of a host name that was looked up.
    public private(set) var hostAddresses: [IPAddress] = []
    /// "1.1.1.0/24" when the typed prefix had host bits set.
    public private(set) var shownAs: String?

    /// The iPad default (shown when the window is wide) is applied once per session.
    @ObservationIgnored var inspectorDecided = false

    @ObservationIgnored let api: any RIPEstatAPI
    @ObservationIgnored let recents: RecentsStore
    @ObservationIgnored let router: AppRouter
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let network: NetworkMonitor?
    @ObservationIgnored private let resolve: @Sendable (String, AddressPreference) async throws -> ResolvedTarget
    @ObservationIgnored private let reverseName: @Sendable (IPAddress) async -> String?
    @ObservationIgnored private let readLocalAddresses: @Sendable () -> [LocalAddress]
    @ObservationIgnored private let includeLocation: Bool
    @ObservationIgnored private let locator: MyIPLocator

    @ObservationIgnored var rules = WhoisRules.live
    @ObservationIgnored var seams = WhoisSeams.live
    @ObservationIgnored var now: () -> Date = { Date() }
    @ObservationIgnored var networkDebounce: Duration = .seconds(2)
    @ObservationIgnored var networkState: () -> WhoisNetworkState = { WhoisNetworkState() }

    @ObservationIgnored private var runID = 0
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var myIPTask: Task<Void, Never>?
    @ObservationIgnored private var myIPRun = 0
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var myWhoisTasks: [IPVersion: Task<Void, Never>] = [:]
    @ObservationIgnored private var myWhoisAddress: [IPVersion: IPAddress] = [:]
    @ObservationIgnored private var userPickedFamily = false
    @ObservationIgnored private var adjustingFamily = false
    @ObservationIgnored private var visible = false

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
        self.locator = MyIPLocator(api: api, reverseName: reverseName)
        if let network {
            networkState = {
                WhoisNetworkState(online: network.isOnline, supportsIPv4: network.supportsIPv4,
                                  supportsIPv6: network.supportsIPv6, usesVPN: network.usesVPN,
                                  generation: network.pathGeneration)
            }
        }
    }

    // MARK: Derived state

    var recentsStore: RecentsStore { recents }
    var pathGeneration: Int { networkState().generation }
    var isMyIPMode: Bool { phase == .myIP }

    /// The whois of the selected own address, once it is loaded.
    var myResult: WhoisResult? {
        if case let .loaded(result)? = myWhois[myFamily] { result } else { nil }
    }

    /// The result of the current subject: a lookup, or your own address in My IP mode.
    var currentResult: WhoisResult? {
        switch phase {
        case let .loaded(result): result
        case .myIP: myResult
        default: nil
        }
    }

    var isLookingUp: Bool {
        switch phase {
        case .resolving, .loading: true
        default: false
        }
    }

    // MARK: Classification

    /// Pure, no network; nil = invalid input.
    public static func classify(_ text: String) -> Classified? { classify(text, rules: .live) }

    static func classify(_ text: String, rules: WhoisRules) -> Classified? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let target = TargetParser.parse(trimmed, mode: .bgp) else { return nil }
        switch target {
        case let .ip(ip):
            return classifyAddress(ip, hostname: nil, input: trimmed, rules: rules)
        case let .prefix(ip, length):
            let network = rules.masked(ip, length)
            if let range = rules.specialRange(network, length) {
                return .local(LocalVerdict(input: trimmed, reason: .address(range), embeddedIPv4: nil))
            }
            return .subject(.prefix(network, length: length))
        case let .asn(number):
            if let reserved = rules.reservedASN(number) {
                return .local(LocalVerdict(input: trimmed, reason: .asn(reserved), embeddedIPv4: nil))
            }
            return .subject(.asn(number))
        case let .hostname(host):
            return .hostname(host)
        }
    }

    static func classifyAddress(_ ip: IPAddress, hostname: String?, input: String, rules: WhoisRules) -> Classified {
        guard let range = rules.specialRange(ip, ip.family == .v4 ? 32 : 128) else {
            return .subject(.address(ip, hostname: hostname))
        }
        let embeds: Set<SpecialPurposeRange.Kind> = [.ipv4Mapped, .nat64, .sixToFour]
        let embedded = embeds.contains(range.kind) ? rules.embeddedIPv4(ip) : nil
        return .local(LocalVerdict(input: input, reason: .address(range), embeddedIPv4: embedded))
    }

    // MARK: Lookup

    /// Parses `targetText` (TargetParser .bgp).
    public func lookUp() {
        let text = targetText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let classified = Self.classify(text, rules: rules) else {
            stopRunning()
            phase = .failed(.invalidInput)
            return
        }
        start(classified, text: text)
    }

    /// Drill-down / raw link / embedded IPv4: sets `targetText` too.
    public func lookUp(_ resource: String) {
        targetText = resource
        lookUp()
    }

    public func cancel() {
        let wasRunning = isLookingUp
        stopRunning()
        if wasRunning { phase = .myIP }
    }

    /// ‹ My IP: clears `targetText`, `phase = .myIP`.
    public func showMyIP() {
        stopRunning()
        targetText = ""
        hostAddresses = []
        shownAs = nil
        phase = .myIP
    }

    private func stopRunning() {
        runID += 1
        runTask?.cancel()
        runTask = nil
    }

    private func start(_ classified: Classified, text: String) {
        stopRunning()
        hostAddresses = []
        shownAs = nil
        let id = runID
        switch classified {
        case let .local(verdict):
            recents.record(text, tool: .whois)
            phase = .local(verdict)
        case let .subject(subject):
            recents.record(text, tool: .whois)
            if case .prefix = subject, subject.resource != text { shownAs = subject.resource }
            phase = .loading(subject)
            runTask = Task { [weak self] in await self?.run(subject, id: id) }
        case let .hostname(host):
            phase = .resolving(host)
            let preference = settings.addressPreference
            runTask = Task { [weak self] in await self?.resolveAndRun(host, text: text, preference: preference, id: id) }
        }
    }

    private func resolveAndRun(_ host: String, text: String, preference: AddressPreference, id: Int) async {
        do {
            let resolved = try await resolve(host, preference)
            guard id == runID else { return }
            recents.record(text, tool: .whois)
            hostAddresses = resolved.allAddresses
            switch Self.classifyAddress(resolved.address, hostname: host, input: host, rules: rules) {
            case let .local(verdict): phase = .local(verdict)
            case let .subject(subject):
                phase = .loading(subject)
                await run(subject, id: id)
            case .hostname: break
            }
        } catch is CancellationError {
            return
        } catch {
            guard id == runID else { return }
            phase = .failed(WhoisFailure.from(error))
        }
    }

    private func run(_ subject: WhoisSubject, id: Int) async {
        do {
            let result = try await makeLoader().load(subject)
            guard id == runID else { return }
            phase = .loaded(result)
        } catch is CancellationError {
            return
        } catch {
            guard id == runID else { return }
            phase = .failed(WhoisFailure.from(error))
        }
    }

    private func makeLoader() -> WhoisLoader {
        WhoisLoader(api: api, reverseName: reverseName, includeLocation: includeLocation, seams: seams)
    }

    // MARK: Router

    /// Router: pre-fill, auto-start if requested.
    public func handle(_ request: ToolRequest) {
        targetText = request.target
        if request.autostart { lookUp() }
    }

    func consumeRouterRequest() {
        guard let request = router.takeRequest(for: .whois) else { return }
        handle(request)
    }

    private var probeTarget: String? {
        switch phase {
        case let .loaded(result):
            if case let .address(ip, hostname) = result.subject { hostname ?? ip.description } else { nil }
        case let .local(verdict):
            if case .address = verdict.reason { verdict.input } else { nil }
        default:
            nil
        }
    }

    /// `router.open(.ping, …)` for the current subject.
    public func ping() {
        if let target = probeTarget { router.open(.ping, target: target, autostart: true) }
    }

    public func trace() {
        if let target = probeTarget { router.open(.traceroute, target: target, autostart: true) }
    }

    public func map() {
        if case let .loaded(result) = phase { router.open(.bgp, target: result.subject.resource, autostart: true) }
    }

    /// "Map in BGP" for one of your own addresses.
    func mapMyIP(_ version: IPVersion) {
        if let address = myIP?.address(version) { router.open(.bgp, target: address.description, autostart: true) }
    }

    // MARK: My IP

    /// DESIGN §14.5.4 triggers: first appearance, a new network generation, or an expired snapshot.
    public func appeared() {
        visible = true
        localAddresses = readLocalAddresses()
        guard myIPTask == nil, !myIPIsFresh else { return }
        loadMyIP(force: false)
    }

    func disappeared() {
        visible = false
        debounceTask?.cancel()
    }

    /// Called by the view when the network path changed while the tool is visible; debounced.
    func pathGenerationChanged() {
        guard visible else { return }
        debounceTask?.cancel()
        let delay = networkDebounce
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.loadMyIP(force: false)
        }
    }

    public func refreshMyIP() {
        loadMyIP(force: true)
    }

    /// Pull to refresh: returns when the check is done.
    func refreshMyIPAndWait() async {
        loadMyIP(force: true)
        await myIPTask?.value
    }

    private var myIPIsFresh: Bool {
        guard let myIP, !myIP.isChecking, !myIP.hasFailure else { return false }
        let state = networkState()
        return myIP.generation == state.generation && state.online != isOfflineSnapshot(myIP)
            && now().timeIntervalSince(myIP.fetchedAt) < MyIPLocator.cacheLifetime
    }

    private func isOfflineSnapshot(_ snapshot: MyIPSnapshot) -> Bool {
        snapshot.v4 == .unavailable(.offline)
    }

    private func loadMyIP(force: Bool) {
        myIPTask?.cancel()
        myIPRun += 1
        let run = myIPRun
        let state = networkState()
        localAddresses = readLocalAddresses()
        guard state.online else {
            myIPTask = nil
            applyMyIP(MyIPSnapshot(v4: .unavailable(.offline), v6: .unavailable(.offline), viaVPN: false,
                                   generation: state.generation, fetchedAt: now()))
            return
        }
        let viaVPN = state.usesVPN || localAddresses.contains { $0.interface == .vpn }
        let locator = locator
        myIPTask = Task { [weak self] in
            let stream = await locator.snapshot(generation: state.generation, supportsV4: state.supportsIPv4,
                                                supportsV6: state.supportsIPv6, viaVPN: viaVPN, force: force)
            for await snapshot in stream {
                guard let self, !Task.isCancelled, run == self.myIPRun else { return }
                self.applyMyIP(snapshot)
            }
            self?.finishMyIP(run)
        }
    }

    private func finishMyIP(_ run: Int) {
        if run == myIPRun { myIPTask = nil }
    }

    private func applyMyIP(_ snapshot: MyIPSnapshot) {
        let newGeneration = myIP?.generation != snapshot.generation
        myIP = snapshot
        if newGeneration { userPickedFamily = false }
        let target = chooseFamily(snapshot)
        if target != myFamily {
            adjustingFamily = true
            myFamily = target
            adjustingFamily = false
        }
        for version in IPVersion.allCases where myWhoisAddress[version] != snapshot.address(version) {
            myWhoisTasks[version]?.cancel()
            myWhoisTasks[version] = nil
            myWhois[version] = nil
            myWhoisAddress[version] = nil
        }
        loadMyWhoisIfNeeded()
    }

    /// IPv4 if found, else IPv6; never leaves a family that is still being checked.
    private func chooseFamily(_ snapshot: MyIPSnapshot) -> IPVersion {
        let other: IPVersion = myFamily == .v4 ? .v6 : .v4
        if userPickedFamily {
            switch snapshot.slot(myFamily) {
            case .unavailable, .failed: return snapshot.address(other) != nil ? other : myFamily
            case .checking, .found: return myFamily
            }
        }
        switch snapshot.v4 {
        case .checking, .found: return .v4
        case .unavailable, .failed: return snapshot.address(.v6) != nil ? .v6 : .v4
        }
    }

    private func loadMyWhoisIfNeeded() {
        let family = myFamily
        guard let address = myIP?.address(family), myWhois[family] == nil else { return }
        myWhois[family] = .loading
        myWhoisAddress[family] = address
        let subject = WhoisSubject.address(address, hostname: nil)
        myWhoisTasks[family] = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.makeLoader().load(subject)
                guard self.myWhoisAddress[family] == address else { return }
                self.myWhois[family] = .loaded(result)
            } catch is CancellationError {
                return
            } catch {
                guard self.myWhoisAddress[family] == address else { return }
                self.myWhois[family] = .failed(WhoisFailure.from(error))
            }
        }
    }

    /// Try Again under the summary of your own address.
    func retryMyWhois() {
        myWhoisTasks[myFamily]?.cancel()
        myWhois[myFamily] = nil
        loadMyWhoisIfNeeded()
    }

    /// Cancels everything in flight. Anything still waiting turns into a failure with Try Again.
    public func stopForBackground() {
        debounceTask?.cancel()
        stopRunning()
        switch phase {
        case .loading, .resolving: phase = .failed(.backgrounded)
        default: break
        }
        myIPRun += 1
        myIPTask?.cancel()
        myIPTask = nil
        for (family, task) in myWhoisTasks {
            task.cancel()
            if myWhois[family] == .loading { myWhois[family] = .failed(.backgrounded) }
        }
        myWhoisTasks = [:]
        if var snapshot = myIP, snapshot.isChecking {
            let message = String(localized: "Stopped — app moved to background.")
            if snapshot.v4 == .checking { snapshot.v4 = .failed(message) }
            if snapshot.v6 == .checking { snapshot.v6 = .failed(message) }
            myIP = snapshot
        }
    }

    // MARK: Export

    /// DESIGN §14.12 summary or My IP text.
    public var exportText: String {
        switch phase {
        case let .loaded(result):
            WhoisExport.summary(result, now: now())
        case .myIP:
            myIP.map { WhoisExport.myIP($0, result: myResult, now: now()) } ?? ""
        default:
            ""
        }
    }

    /// `exportText` plus raw records.
    public var exportFullText: String {
        if case let .loaded(result) = phase { WhoisExport.full(result, now: now()) } else { exportText }
    }

    // MARK: Preview support

    /// Puts the model into a fixed state for previews.
    func applyPreview(phase: Phase = .myIP, myIP: MyIPSnapshot? = nil, myWhois: [IPVersion: WhoisLoad] = [:],
                      localAddresses: [LocalAddress] = []) {
        self.phase = phase
        self.myIP = myIP
        self.myWhois = myWhois
        self.localAddresses = localAddresses
        if case let .loaded(result) = phase { targetText = result.subject.resource }
    }
}
