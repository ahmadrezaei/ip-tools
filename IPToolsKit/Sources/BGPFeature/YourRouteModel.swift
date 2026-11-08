// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import BGPGraph
import Foundation
import NetCore
import Observation
import RIPEstat
import SharedUI

/// What the route needs to know about the map that was just loaded.
struct RouteContext {
    var label: String                       // what the user typed ("8.8.8.8", "cloudflare.com", "8.8.8.0/24")
    var address: IPAddress?                 // IP / hostname input: the address being mapped
    var hostname: String?
    var prefix: String
    var origins: [UInt32]
    var paths: [ObservedPath]               // cleaned RIS paths
    var collectorLocations: [String: String]
    var snapshot: TraceSnapshot?

    var isPrefixTarget: Bool { address == nil }
}

@MainActor @Observable public final class YourRouteModel {
    public enum Phase: Equatable {
        case idle, locating, measuring(ttl: Int), done, partial(String), stopped(String),
             lookupsOff, unavailable, failed(String)
    }
    public private(set) var phase: Phase = .idle { didSet { changed() } }
    public private(set) var chain: ASChain? { didSet { changed() } }
    public private(set) var myNetwork: MyNetwork?

    private(set) var context: RouteContext?
    private(set) var names: [UInt32: String] = [:]

    @ObservationIgnored private var api: (any RIPEstatAPI)?
    @ObservationIgnored private var service: (any TraceService)?
    @ObservationIgnored private var settings: SettingsStore?
    @ObservationIgnored var now: @Sendable () -> Date = { Date() }
    @ObservationIgnored private var task: Task<Void, Never>?
    var measurementTask: Task<Void, Never>? { task }
    @ObservationIgnored private var namesDebounce: Task<Void, Never>?
    @ObservationIgnored private var namesFetches: [Task<Void, Never>] = []
    @ObservationIgnored private var requestedNames: Set<UInt32> = []
    @ObservationIgnored private var failedNames: Set<UInt32> = []
    @ObservationIgnored private(set) var hops: [ChainHop] = []
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var runID = 0
    /// True while the app is in the background: no new measurement may start.
    @ObservationIgnored var isSuspended = false

    /// Called whenever the phase or the chain changes (the map redraws the your-path overlay).
    @ObservationIgnored var onChange: (() -> Void)?
    private func changed() { onChange?() }

    static let snapshotMaxAge: TimeInterval = 10 * 60

    public init() {}

    func configure(api: any RIPEstatAPI, service: (any TraceService)?, settings: SettingsStore?) {
        self.api = api
        self.service = service
        self.settings = settings
    }

    // MARK: Lifecycle

    var isMeasuring: Bool { if case .measuring = phase { true } else { false } }
    var myASN: UInt32? { myNetwork?.asn }
    var lookupsEnabled: Bool { settings?.trace.lookUpASNs ?? true }

    /// Clears everything and cancels a running measurement.
    func reset() {
        runID += 1
        task?.cancel()
        namesDebounce?.cancel()
        for fetch in namesFetches { fetch.cancel() }
        namesFetches = []
        requestedNames = []
        failedNames = []
        task = nil
        phase = .idle
        chain = nil
        context = nil
        hops = []
    }

    func beginLocating() {
        reset()
        phase = .locating
    }

    func setMyNetwork(_ network: MyNetwork?) {
        myNetwork = network.map { net in
            var net = net
            if let asn = net.asn { net.name = BGPText.shortName(names[asn]) }
            return net
        }
    }

    /// Picks the chain source (DESIGN 6.11.2): handed-over trace, then BGP, then a fresh traceroute.
    func begin(_ context: RouteContext, myNetwork: MyNetwork?) {
        reset()
        self.context = context
        setMyNetwork(myNetwork)
        var snapshotNeedsLookups = false
        if let snapshot = context.snapshot, let address = context.address, snapshot.target.address == address,
           now().timeIntervalSince(snapshot.finishedAt) <= Self.snapshotMaxAge {
            let snapshotHops = Self.hops(from: snapshot)
            snapshotNeedsLookups = snapshotHops.contains { $0.kind == .unknownNetwork }
            if !snapshotNeedsLookups {
                hops = snapshotHops
                finish(source: .traceroute(handedOver: true, measuredAt: snapshot.finishedAt), stitch: true)
                return
            }
            if lookupsEnabled, let api {
                resolveSnapshot(snapshot, hops: snapshotHops, api: api)
                return
            }
        }
        if let asn = myASN,
           let bgp = ASChainBuilder.fromBGP(context.paths, myASN: asn, origins: context.origins) {
            chain = bgp
            phase = .done
            requestNames()
            return
        }
        if snapshotNeedsLookups {
            // Lookups are off and the handed-over trace has no networks: nothing to build from.
            phase = .lookupsOff
            chain = nil
            return
        }
        startMeasuring()
    }

    /// "Measure again" / "Measure with traceroute": always a fresh traceroute (rule 3).
    public func measureAgain() {
        guard context != nil else { return }
        runID += 1
        task?.cancel()
        startMeasuring()
    }

    public func stop(reason: String? = nil) {
        guard case let .measuring(ttl) = phase else { return }
        runID += 1
        task?.cancel()
        let title = reason.map { String(localized: "Stopped: \($0)") } ?? String(localized: "Stopped at hop \(ttl)")
        if let context, !hops.isEmpty {
            chain = ASChainBuilder.fromTrace(hops, myASN: myASN, origins: context.origins, finished: true,
                                             source: .traceroute(handedOver: false, measuredAt: now()))
        } else {
            chain = nil
        }
        phase = .stopped(title)
    }

    // MARK: Sources

    private static func hops(from snapshot: TraceSnapshot) -> [ChainHop] {
        snapshot.hops.map { hop in
            let kind: ChainHop.Kind
            if let address = hop.address {
                if !address.isPubliclyRoutable { kind = .privateAddress }
                else if let asn = hop.asn { kind = .network(asn) }
                else { kind = .unknownNetwork }
            } else {
                kind = .silent
            }
            return ChainHop(ttl: hop.ttl, kind: kind, address: hop.address?.description, hostname: hop.hostname,
                            rtts: hop.rtts, reachedTarget: hop.reachedTarget)
        }
    }

    /// A handed-over trace without networks: look up each public hop, then finish like a measured one.
    private func resolveSnapshot(_ snapshot: TraceSnapshot, hops snapshotHops: [ChainHop], api: any RIPEstatAPI) {
        hops = snapshotHops
        startedAt = now()
        chain = placeholderChain()
        phase = .measuring(ttl: 0)
        let id = runID
        let addresses = Array(Set(snapshotHops.filter { $0.kind == .unknownNetwork }.compactMap(\.address))).sorted()
        task = Task { [weak self] in
            let found = await withTaskGroup(of: (String, UInt32?).self) { group in
                for address in addresses {
                    group.addTask {
                        if case let .found(asn) = await RouteMeasurer.lookup(address, api: api) { return (address, asn) }
                        return (address, nil)
                    }
                }
                var result: [String: UInt32] = [:]
                for await (address, asn) in group { if let asn { result[address] = asn } }
                return result
            }
            guard let self, !Task.isCancelled, id == self.runID else { return }
            self.hops = self.hops.map { hop in
                guard hop.kind == .unknownNetwork, let address = hop.address, let asn = found[address] else { return hop }
                return ChainHop(ttl: hop.ttl, kind: .network(asn), address: hop.address, hostname: hop.hostname,
                                rtts: hop.rtts, reachedTarget: hop.reachedTarget)
            }
            self.finish(source: .traceroute(handedOver: true, measuredAt: snapshot.finishedAt), stitch: true)
        }
    }

    private func startMeasuring() {
        guard let context else { return }
        if isSuspended {
            let title = String(localized: "Stopped: app moved to background")
            chain = nil
            phase = .stopped(title)
            return
        }
        guard let service, let api else { phase = .unavailable; chain = nil; return }
        guard lookupsEnabled else { phase = .lookupsOff; chain = nil; return }
        guard let probe = probeTarget(context) else {
            phase = .failed(String(localized: "This target can't be traced."))
            return
        }
        hops = []
        startedAt = now()
        chain = placeholderChain()
        phase = .measuring(ttl: 0)
        let id = runID
        let stream = RouteMeasurer(service: service, api: api)
            .measure(probe, origins: Set(context.origins), prefixTarget: context.isPrefixTarget)
        task = Task { [weak self] in
            for await update in stream {
                guard let self, id == self.runID else { return }
                self.apply(update)
            }
        }
    }

    private func probeTarget(_ context: RouteContext) -> ResolvedTarget? {
        let address = context.address ?? PrefixMath.probeAddress(forPrefix: context.prefix)
        guard let address else { return nil }
        return ResolvedTarget(input: context.label, address: address, hostname: context.hostname, allAddresses: [address])
    }

    private func apply(_ update: RouteMeasurer.Update) {
        switch update {
        case let .hops(list):
            hops = list
            guard let context, !list.isEmpty else { return }
            let built = ASChainBuilder.fromTrace(list, myASN: myASN, origins: context.origins, finished: false,
                                                 source: .traceroute(handedOver: false, measuredAt: startedAt))
            chain = built
            let ttl = built.lastTTL ?? list.last?.ttl ?? 0
            phase = .measuring(ttl: ttl)
            requestNames()
        case .finished:
            finish(source: .traceroute(handedOver: false, measuredAt: now()), stitch: true)
        case let .failed(error):
            phase = .failed(BGPFailure.from(error).message(for: error))
        }
    }

    private func finish(source: ASChain.Source, stitch: Bool) {
        guard let context else { return }
        var built = ASChainBuilder.fromTrace(hops, myASN: myASN, origins: context.origins, finished: true, source: source)
        if stitch { built = ASChainBuilder.stitch(built, cleanedPaths: context.paths, origins: context.origins) }
        chain = built
        requestNames()
        phase = finalPhase(for: built)
    }

    private func finalPhase(for chain: ASChain) -> Phase {
        switch chain.completion {
        case .complete, .inProgress:
            return .done
        case .stitched, .gap:
            if !publicHopAnswered { return .partial(String(localized: "No router on the way answered")) }
            if !hasNetworkHop { return .partial(String(localized: "Couldn't look up the networks on the way.")) }
            let hop = chain.lastTTL ?? 0
            if chain.completion == .stitched {
                let last = chain.nodes.last { $0.provenance == .measured }
                let name = last?.asn.flatMap { shortName($0) ?? "AS\($0)" } ?? String(localized: "your network")
                return .partial(String(localized: "Traceroute stopped in \(name) at hop \(hop)"))
            }
            return .partial(String(localized: "Traceroute couldn't see past hop \(hop)"))
        }
    }

    /// A router with a public address answered (whether or not its network is known).
    var publicHopAnswered: Bool {
        hops.contains { if case .network = $0.kind { true } else if case .unknownNetwork = $0.kind { true } else { false } }
    }

    var hasNetworkHop: Bool { hops.contains { if case .network = $0.kind { true } else { false } } }

    private func placeholderChain() -> ASChain? {
        guard let context, let origin = context.origins.first else { return nil }
        let you = ASChain.Node(asn: myASN, role: .you, provenance: .measured)
        let destination = ASChain.Node(asn: origin, role: .destination, provenance: .expected, gapBefore: true)
        return ASChain(nodes: myASN == origin ? [ASChain.Node(asn: origin, role: .youAndDestination, provenance: .measured)]
                                              : [you, destination],
                       source: .traceroute(handedOver: false, measuredAt: startedAt), completion: .inProgress, reachedTarget: false)
    }

    // MARK: Names

    func shortName(_ asn: UInt32?) -> String? {
        asn.flatMap { BGPText.shortName(names[$0]) }
    }

    func fullName(_ asn: UInt32?) -> String? {
        asn.flatMap { BGPText.fullName(names[$0]) }
    }

    func ingestNames(_ raw: [UInt32: String]) {
        let before = names.count
        names.merge(raw.filter { !$0.value.isEmpty }) { _, new in new }
        guard names.count != before || myNetwork?.name == nil else { return }
        if var network = myNetwork, let asn = network.asn, network.name == nil {
            network.name = BGPText.shortName(names[asn])
            myNetwork = network
        }
    }

    /// Debounced (500 ms) bulk `as-names` for the networks on the chain.
    /// A new request only restarts the debounce; a fetch already in flight is never cancelled.
    func requestNames() {
        guard api != nil, !missingNames().isEmpty else { return }
        namesDebounce?.cancel()
        namesDebounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            self.fetchNames()
        }
    }

    private func missingNames() -> [UInt32] {
        var wanted = Set(chain?.asnSequence ?? [])
        if let asn = myASN { wanted.insert(asn) }
        wanted.formUnion(context?.origins ?? [])
        return wanted.subtracting(names.keys).subtracting(requestedNames).sorted()
    }

    private func fetchNames() {
        guard let api else { return }
        let list = missingNames()
        guard !list.isEmpty else { return }
        requestedNames.formUnion(list)
        let id = runID
        let fetch = Task { [weak self] in
            let fetched = try? await api.asNames(list)
            guard let self, id == self.runID else { return }
            if let fetched {
                self.ingestNames(fetched)
            } else {
                // One retry per name: forget it so the next request asks again.
                let retry = list.filter { !self.failedNames.contains($0) }
                self.failedNames.formUnion(list)
                self.requestedNames.subtract(retry)
                if !retry.isEmpty { self.requestNames() }
            }
        }
        namesFetches.removeAll { $0.isCancelled }
        namesFetches.append(fetch)
    }
}

private extension BGPFailure {
    func message(for error: Error) -> String {
        if let net = error as? NetError {
            switch net {
            case .networkUnreachable(let family):
                return family == .v6 ? String(localized: "No IPv6 route — this network doesn't support IPv6.")
                                     : String(localized: "No route — this network can't reach that address.")
            case .localNetworkDenied: return String(localized: "Local network access is turned off for IP Tools.")
            case .socketUnavailable: return String(localized: "Couldn't open a network socket.")
            default: break
            }
        }
        return message
    }
}

#if DEBUG
extension YourRouteModel {
    /// Puts the model into a given state for previews and tests, without measuring.
    func installPreview(phase: Phase, chain: ASChain?, context: RouteContext?, names: [UInt32: String], myNetwork: MyNetwork?,
                        hops: [ChainHop] = []) {
        self.phase = phase
        self.chain = chain
        self.context = context
        self.names = names
        self.myNetwork = myNetwork
        self.hops = hops
    }
}
#endif
