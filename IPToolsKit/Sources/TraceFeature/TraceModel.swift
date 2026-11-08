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

    /// Round-trip times of the probes that were answered.
    public var rtts: [TimeInterval] { probes.compactMap(\.rtt) }
    public var averageRTT: TimeInterval? { rtts.isEmpty ? nil : rtts.reduce(0, +) / Double(rtts.count) }
    /// True when no probe was answered.
    public var isSilent: Bool { addresses.isEmpty }
    /// Number of additional addresses that answered for this TTL (ECMP).
    public var otherAddressCount: Int { max(addresses.count - 1, 0) }
    /// The reason when a probe came back as Destination Unreachable.
    public var unreachableReason: UnreachableReason? {
        for probe in probes {
            if case let .unreachable(from, _, code) = probe { return UnreachableReason(code: code, family: from.family) }
        }
        return nil
    }
}

@MainActor @Observable public final class TraceModel {
    public enum Phase: Equatable { case idle, resolving, tracing(currentTTL: Int), finished(TraceCompletion), stopped(String?), failed(String) }

    public typealias ResolveFunction = @Sendable (String, AddressPreference) async throws -> ResolvedTarget
    public typealias ReverseDNSFunction = @Sendable (IPAddress) async -> ReverseLookupResult

    public var targetText: String = ""
    public internal(set) var phase: Phase = .idle
    public internal(set) var hops: [TraceHop] = []
    public internal(set) var resolved: ResolvedTarget?
    public internal(set) var error: ToolError?
    public internal(set) var runTarget: String = ""
    /// Options of the current/last run.
    public internal(set) var activeOptions: TraceOptions = .default

    @ObservationIgnored let service: any TraceService
    @ObservationIgnored let asnLookup: ASNLookup
    @ObservationIgnored let settings: SettingsStore
    @ObservationIgnored let recents: RecentsStore
    @ObservationIgnored let router: AppRouter
    @ObservationIgnored let resolve: ResolveFunction
    @ObservationIgnored let reverseDNS: ReverseDNSFunction
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var requested: Set<IPAddress> = []
    @ObservationIgnored private var hostnameCache: [IPAddress: String?] = [:]
    @ObservationIgnored private var asnCache: [IPAddress: HopASN] = [:]
    @ObservationIgnored private var pendingNames: Set<UInt32> = []
    @ObservationIgnored private var nameTask: Task<Void, Never>?
    @ObservationIgnored private let dnsLimiter = AsyncLimiter(limit: 4)
    @ObservationIgnored private var resolveHostnames = true
    @ObservationIgnored private var lookUpASNs = true
    public var recentsStore: RecentsStore { recents }

    public init(service: any TraceService, asnLookup: ASNLookup, settings: SettingsStore,
                recents: RecentsStore, router: AppRouter,
                resolve: @escaping ResolveFunction = { try await Resolver.resolve($0, preference: $1) },
                reverseDNS: @escaping ReverseDNSFunction = { await Resolver.reverseLookup(for: $0, timeout: .seconds(5)) }) {
        self.service = service
        self.asnLookup = asnLookup
        self.settings = settings
        self.recents = recents
        self.router = router
        self.resolve = resolve
        self.reverseDNS = reverseDNS
    }

    public var isBusy: Bool {
        switch phase {
        case .resolving, .tracing: true
        default: false
        }
    }

    public var currentTTL: Int? {
        if case let .tracing(ttl) = phase { return ttl }
        return nil
    }

    // MARK: - Control

    public func start() {
        guard !isBusy else { return }
        let input = targetText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        reset()
        runTarget = input
        guard TargetParser.parse(input, mode: .host) != nil else {
            fail(ToolError(.invalidTarget(input)))
            return
        }
        phase = .resolving
        generation += 1
        let gen = generation
        let preference = settings.addressPreference
        let options = settings.trace.options
        resolveHostnames = settings.trace.resolveHostnames
        lookUpASNs = settings.trace.lookUpASNs
        activeOptions = options
        let resolve = self.resolve
        task = Task { [weak self] in
            do {
                let target = try await resolve(input, preference)
                try Task.checkCancellation()
                guard let self, !Task.isCancelled, self.generation == gen else { return }
                self.resolved = target
                self.phase = .tracing(currentTTL: 1)
                self.recents.record(input, tool: .traceroute)
                for try await event in self.service.trace(target, options: options) {
                    guard !Task.isCancelled, self.generation == gen, self.isBusy else { break }
                    self.handle(event, target: target, options: options)
                }
                guard !Task.isCancelled, self.generation == gen else { return }
                if self.isBusy { self.phase = .finished(.maxHopsExceeded) }
            } catch is CancellationError {
                // stop() already set the phase
            } catch {
                guard !Task.isCancelled, let self, self.generation == gen else { return }
                self.fail(ToolError.from(error))
            }
        }
    }

    public func stop(reason: String? = nil) {
        guard isBusy else { return }
        task?.cancel()
        task = nil
        phase = phase == .resolving && hops.isEmpty ? .idle : .stopped(reason)
    }

    public func stopForBackground() {
        stop(reason: String(localized: "app moved to background"))
    }

    public func retry() { start() }

    /// Picks up a request handed over by the router (cross-links auto-start, recents only pre-fill).
    public func consumePendingRequest() {
        guard let request = router.takeRequest(for: .traceroute) else { return }
        if request.autostart {
            if isBusy { stop() }
            targetText = request.target
            start()
        } else if !isBusy {
            targetText = request.target
        }
    }

    // MARK: - Cross-links

    public func pingHop(_ address: IPAddress) {
        router.open(.ping, target: address.description, autostart: true)
    }

    public func mapHop(_ address: IPAddress) {
        guard address.isPubliclyRoutable else { return }
        router.open(.bgp, target: address.description, autostart: true)
    }

    public func mapTarget() {
        if let address = resolved?.address { mapHop(address) }
    }

    /// Hops 1...ttl (all when nil), only for finished/stopped runs; nil while running or empty.
    public func snapshot(upTo ttl: Int? = nil) -> TraceSnapshot? { nil }

    public var canMapTarget: Bool { resolved?.address.isPubliclyRoutable ?? false }

    // MARK: - Export

    /// Plain-text export (DESIGN §5.6).
    public var exportText: String {
        guard !hops.isEmpty else { return "" }
        return TraceExport.text(target: resolved, options: activeOptions, hops: hops)
    }

    // MARK: - Event handling

    private func reset() {
        task?.cancel()
        nameTask?.cancel()
        nameTask = nil
        hops = []
        resolved = nil
        error = nil
        requested = []
        pendingNames = []
    }

    private func fail(_ toolError: ToolError) {
        error = toolError
        phase = .failed(toolError.title)
    }

    func handle(_ event: TraceEvent, target: ResolvedTarget, options: TraceOptions) {
        switch event {
        case let .probe(ttl, index, result):
            guard ttl >= 1 else { return }
            if case .tracing = phase { phase = .tracing(currentTTL: ttl) }
            while hops.count < ttl { hops.append(TraceHop(ttl: hops.count + 1)) }
            var hop = hops[ttl - 1]
            while hop.probes.count <= index { hop.probes.append(.timeout) }
            hop.probes[index] = result
            var newAddress: IPAddress?
            if let address = result.address, !hop.addresses.contains(address) {
                hop.addresses.append(address)
                if hop.addresses.count == 1 { newAddress = address }
            }
            if case .echoReply = result { hop.isDestination = true }
            if let newAddress {
                hop.hostname = hostnameCache[newAddress] ?? nil
                if hop.hostname == nil, newAddress == target.address { hop.hostname = target.hostname }
                hop.asn = asnCache[newAddress]
            }
            hops[ttl - 1] = hop
            if let newAddress { enrich(newAddress) }
        case let .hopFinished(ttl):
            if case .tracing = phase { phase = .tracing(currentTTL: min(ttl + 1, options.maxHops)) }
        case let .finished(completion):
            phase = .finished(completion)
        }
    }

    // MARK: - Enrichment (never blocks probing)

    private func enrich(_ address: IPAddress) {
        guard requested.insert(address).inserted else { return }
        let gen = generation
        if resolveHostnames, hostnameCache[address] == nil {
            let reverseDNS = self.reverseDNS
            let limiter = dnsLimiter
            Task { [weak self] in
                let result = await limiter.run { await reverseDNS(address) }
                self?.applyHostname(result, to: address, generation: gen)
            }
        }
        if lookUpASNs, address.isPubliclyRoutable, asnCache[address] == nil {
            let lookup = asnLookup
            Task { [weak self] in
                let asn = await lookup.lookup(address)
                self?.applyASN(asn, to: address, generation: gen)
            }
        }
    }

    private func applyHostname(_ result: ReverseLookupResult, to address: IPAddress, generation gen: Int) {
        let name: String?
        switch result {
        case let .name(value): name = value
        case .noName: name = nil
        case .timedOut:
            // Never cached: a later run (or a later sighting of this address) may retry.
            if gen == generation { requested.remove(address) }
            return
        }
        hostnameCache[address] = .some(name)
        guard gen == generation, let name else { return }
        for index in hops.indices where hops[index].addresses.first == address {
            hops[index].hostname = name
        }
    }

    private func applyASN(_ asn: HopASN?, to address: IPAddress, generation gen: Int) {
        guard let asn else { return }
        asnCache[address] = asn
        guard gen == generation else { return }
        for index in hops.indices where hops[index].addresses.first == address {
            hops[index].asn = asn
        }
        if asn.name == nil { scheduleNames(for: asn.asn) }
    }

    /// Names ASNs with one bulk `as-names` call, debounced by 500 ms as new ASNs appear.
    private func scheduleNames(for asn: UInt32) {
        pendingNames.insert(asn)
        guard nameTask == nil else { return }
        let gen = generation
        nameTask = Task { [weak self] in
            while let self, !Task.isCancelled, !self.pendingNames.isEmpty {
                try? await Task.sleep(for: .milliseconds(500))
                if Task.isCancelled { return }
                let batch = Array(self.pendingNames)
                self.pendingNames = []
                let names = await self.asnLookup.names(for: batch)
                guard self.generation == gen else { return }
                self.applyNames(names)
            }
            self?.nameTask = nil
        }
    }

    private func applyNames(_ names: [UInt32: String]) {
        guard !names.isEmpty else { return }
        for index in hops.indices {
            if let asn = hops[index].asn, asn.name == nil, let name = names[asn.asn] {
                let updated = HopASN(asn: asn.asn, name: name, prefix: asn.prefix)
                hops[index].asn = updated
                if let address = hops[index].addresses.first { asnCache[address] = updated }
            }
        }
    }
}
