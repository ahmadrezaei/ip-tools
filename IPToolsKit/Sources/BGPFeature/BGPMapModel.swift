// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import BGPGraph
import Foundation
import NetCore
import Observation
import RIPEstat
import SharedUI

@MainActor @Observable public final class BGPMapModel {
    public enum Phase: Equatable { case idle, loading(String), pickingPrefix(asn: UInt32, holder: String?, prefixes: [String]), loaded, failed(String) }
    public enum DisplayMode: Sendable { case graph, list }

    public var targetText: String = ""
    public var maxNodesPerLayer: Int = 6 {        // 6 / 12 / 30 -> rebuilds graph + layout off-main
        didSet { if oldValue != maxNodesPerLayer { rebuild() } }
    }
    public var selection: NodeID? { didSet { updateHighlight() } }
    public var displayMode: DisplayMode = .graph
    public var view: BGPView = .yourRoute
    public let route: YourRouteModel
    public private(set) var summary: RoutesSummary?
    public internal(set) var phase: Phase = .idle
    public private(set) var result: BGPResult?
    public private(set) var layout: GraphLayout?
    /// Set whenever `phase` is `.failed`.
    public internal(set) var failure: BGPFailure?
    /// "cloudflare.com → 104.16.132.229" when the input was a hostname.
    public private(set) var hostLine: String?
    /// Your network, once whats-my-ip and network-info have answered.
    public var myNetwork: MyNetwork? { route.myNetwork }
    var myASN: UInt32? { myNetwork?.asn }

    /// Holder of an AS: from the graph's names, else from the names Your route fetched.
    func holder(of asn: UInt32) -> String? {
        result?.holder(of: asn) ?? route.names[asn].flatMap { $0.isEmpty ? nil : $0 }
    }

    private(set) var stats: BGPStats?
    private(set) var highlight: BGPHighlight?
    /// Bumped whenever a new layout is installed, so the canvas can refit.
    private(set) var layoutVersion = 0
    /// Bumped when the user asks for the details of the current selection.
    private(set) var detailsToken = 0
    /// Bumped when the legend's Fit button is pressed; the canvas refits.
    private(set) var fitToken = 0
    func requestFit() { fitToken += 1 }

    @ObservationIgnored let api: any RIPEstatAPI
    @ObservationIgnored let recents: RecentsStore
    @ObservationIgnored let router: AppRouter
    public var recentsStore: RecentsStore { recents }

    @ObservationIgnored private var rawPaths: [ObservedPath] = []
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var namesTask: Task<Void, Never>?
    @ObservationIgnored private var rebuildTask: Task<Void, Never>?
    @ObservationIgnored private var runID = 0
    @ObservationIgnored private var pendingSelection: NodeID?
    @ObservationIgnored private let locator: MyNetworkLocator
    @ObservationIgnored private let network: NetworkMonitor?
    @ObservationIgnored private var locateTask: Task<MyNetwork?, Never>?
    @ObservationIgnored private var lateTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSnapshot: TraceSnapshot?
    @ObservationIgnored private var routeSnapshot: TraceSnapshot?
    @ObservationIgnored private var routeInput: RouteInput?
    @ObservationIgnored private var prefixCache: [UInt32: (holder: String?, prefixes: [String])] = [:]

    public init(api: any RIPEstatAPI, recents: RecentsStore, router: AppRouter,
                traceService: (any TraceService)? = nil,      // nil: Your route shows "unavailable"
                settings: SettingsStore? = nil, network: NetworkMonitor? = nil) {
        self.api = api
        self.recents = recents
        self.router = router
        self.network = network
        self.locator = MyNetworkLocator(api: api)
        self.route = YourRouteModel()
        route.configure(api: api, service: traceService, settings: settings)
    }

    /// Stops a running measurement and keeps new ones from starting until `resumeFromBackground()`.
    public func stopForBackground() {
        route.isSuspended = true
        route.stop(reason: String(localized: "app moved to background"))
    }

    /// The app is active again: measurements may start (the user re-measures a stopped route).
    public func resumeFromBackground() {
        route.isSuspended = false
    }

    /// What the typed input says about the probe target.
    struct RouteInput {
        var label: String
        var address: IPAddress?
        var hostname: String?
    }

    // MARK: - Input

    enum Parsed: Equatable {
        case ip(IPAddress), prefix(IPAddress, length: Int), asn(UInt32), hostname(String)
    }

    static func classify(_ raw: String) -> Parsed? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.count <= 10, text.allSatisfy({ $0.isASCII && $0.isNumber }), let number = UInt32(text) { return .asn(number) }
        switch TargetParser.parse(text, mode: .bgp) {
        case let .ip(ip): return .ip(ip)
        case let .prefix(ip, length): return .prefix(ip, length: length)
        case let .asn(asn): return .asn(asn)
        case let .hostname(host): return .hostname(host)
        case nil: return nil
        }
    }

    static func isReservedASN(_ asn: UInt32) -> Bool {
        asn == 0 || asn == 23456 || (64496...65535).contains(asn) || (4_200_000_000...4_294_967_295).contains(asn)
    }

    /// Local rejection of private / reserved space; nil when the request may go out.
    static func rejection(for parsed: Parsed, text: String) -> BGPFailure? {
        func message(_ ip: IPAddress) -> String? {
            guard !ip.isPubliclyRoutable else { return nil }
            switch ip.scopeLabel {
            case "Private"?: return String(localized: "\(text) is a private range and isn't routed on the public Internet.")
            case let label?:
                return String(localized: "\(text) is a reserved \(label.lowercased()) range and isn't routed on the public Internet.")
            case nil: return String(localized: "\(text) is a reserved range and isn't routed on the public Internet.")
            }
        }
        switch parsed {
        case let .ip(ip), let .prefix(ip, _):
            return message(ip).map { BGPFailure(kind: .notRouted, message: $0) }
        case let .asn(asn):
            guard isReservedASN(asn) else { return nil }
            return BGPFailure(kind: .notRouted, message: String(localized: "AS\(String(asn)) is a private or reserved AS number and isn't routed on the public Internet."))
        case .hostname:
            return nil
        }
    }

    // MARK: - Public actions

    public func map() {
        let text = targetText.trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshot = pendingSnapshot
        pendingSnapshot = nil
        guard let parsed = Self.classify(text) else {
            reset()
            fail(BGPFailure(kind: .invalid, message: String(localized: "Enter an IP address, prefix, AS number or hostname.")))
            return
        }
        start(parsed, text: text, snapshot: snapshot)
    }

    public func choosePrefix(_ prefix: String) {
        guard let parsed = Self.classify(prefix) else { return }
        targetText = prefix
        start(parsed, text: prefix, record: false)
    }

    public func cancel() {
        runID += 1
        runTask?.cancel()
        namesTask?.cancel()
        runTask = nil
        locateTask?.cancel()
        lateTask?.cancel()
        route.reset()
        if case .loading = phase { phase = .idle }
    }

    public func dismissPicker() {
        if case .pickingPrefix = phase { phase = .idle }
    }

    /// "Map prefixes of ASxxxx" from the AS details.
    public func mapASN(_ asn: UInt32) {
        targetText = "AS\(asn)"
        map()
    }

    public func select(_ id: NodeID?) {
        selection = (id == selection) ? nil : id
    }

    /// Selects `id` and asks the view to show its details (sheet on iPhone).
    func requestDetails(for id: NodeID) {
        selection = id
        detailsToken += 1
    }

    /// Picks up a hand-over from `AppRouter` (cross-links pre-fill and auto-start).
    public func consumeRouterRequest() {
        guard let request = router.takeRequest(for: .bgp) else { return }
        targetText = request.target
        pendingSnapshot = request.trace
        if request.autostart { map() }
    }

    /// Grows K just enough to show `asn` and selects it. Used by the "+more" list.
    func promote(_ asn: UInt32) {
        guard let stats else { return }
        if case .asn? = stats.nodeFor(asn) { selection = .asn(asn); return }
        guard let layer = stats.layer[asn], let rank = stats.layerMembers[layer]?.firstIndex(of: asn) else { return }
        pendingSelection = .asn(asn)
        selection = nil
        let needed = rank + 1
        if needed > maxNodesPerLayer { maxNodesPerLayer = needed } else { rebuild() }
    }

    /// Text of the visible view: the route in Your route, the paths in All routes.
    public var exportText: String {
        view == .yourRoute ? route.exportText : BGPExport.text(result: result)
    }

    // MARK: - Run

    private func reset() {
        runID += 1
        runTask?.cancel()
        namesTask?.cancel()
        rebuildTask?.cancel()
        result = nil
        layout = nil
        stats = nil
        highlight = nil
        selection = nil
        failure = nil
        hostLine = nil
        rawPaths = []
        locateTask?.cancel()
        lateTask?.cancel()
        route.reset()
        summary = nil
        route.setMyNetwork(nil)
        routeInput = nil
    }

    private func fail(_ failure: BGPFailure) {
        self.failure = failure
        phase = .failed(failure.message)
    }

    private func start(_ parsed: Parsed, text: String, record: Bool = true, snapshot: TraceSnapshot? = nil) {
        reset()
        if let rejection = Self.rejection(for: parsed, text: text) {
            fail(rejection)
            return
        }
        let id = runID
        routeSnapshot = snapshot
        // Hostnames are located after they resolve to a public address (see `run`).
        switch parsed {
        case .ip, .prefix: startLocating()
        case .asn, .hostname: break
        }
        phase = .loading(String(localized: "Fetching routes from RIPEstat…"))
        runTask = Task { [weak self] in await self?.run(parsed, text: text, id: id, record: record) }
    }

    private func run(_ parsed: Parsed, text: String, id: Int, record: Bool) async {
        do {
            switch parsed {
            case let .asn(asn):
                try await loadASN(asn, text: text, id: id, record: record)
            case let .ip(ip):
                routeInput = RouteInput(label: text, address: ip, hostname: nil)
                try await loadAddress(ip, text: text, id: id, record: record)
            case let .prefix(ip, length):
                routeInput = RouteInput(label: text, address: nil, hostname: nil)
                try await loadPrefix("\(ip)/\(length)", text: text, id: id, record: record)
            case let .hostname(host):
                phase = .loading(String(localized: "Resolving \(host)…"))
                let resolved = try await Resolver.resolve(host, preference: .automatic)
                guard id == runID else { return }
                if let rejection = Self.rejection(for: .ip(resolved.address), text: "\(host) (\(resolved.address))") {
                    fail(rejection)
                    return
                }
                startLocating()
                hostLine = "\(host) → \(resolved.address)"
                routeInput = RouteInput(label: host, address: resolved.address, hostname: host)
                phase = .loading(String(localized: "Fetching routes from RIPEstat…"))
                try await loadAddress(resolved.address, text: text, id: id, record: record)
            }
        } catch is CancellationError {
            return
        } catch {
            if let url = error as? URLError, url.code == .cancelled { return }
            guard id == runID else { return }
            fail(.from(error))
        }
    }

    private func notAnnounced(_ what: String) -> BGPFailure {
        BGPFailure(kind: .notAnnounced, message: String(localized: "\(what) isn't announced in BGP right now."))
    }

    private func loadAddress(_ ip: IPAddress, text: String, id: Int, record: Bool) async throws {
        let address = ip.description
        let api = api
        async let looking = api.lookingGlass(address)
        async let info = api.networkInfo(address)
        let network = try await info
        guard let prefix = network.prefix, !prefix.isEmpty else {
            guard id == runID else { return }
            fail(notAnnounced(address))
            return
        }
        async let status: RoutingStatus? = try? await api.routingStatus(prefix)
        let glass = try await looking
        let routing = await status
        let origins = network.originASNs.map { ASHolder(asn: $0, holder: "") }
        try await finish(prefix: prefix, origins: origins, glass: glass, routing: routing, name: address, text: text, id: id, record: record)
    }

    private func loadPrefix(_ prefix: String, text: String, id: Int, record: Bool) async throws {
        let api = api
        async let looking = api.lookingGlass(prefix)
        async let overview = api.prefixOverview(prefix)
        async let status: RoutingStatus? = try? await api.routingStatus(prefix)
        let info = try await overview
        let glass = try await looking
        let routing = await status
        guard info.announced else {
            guard id == runID else { return }
            fail(notAnnounced(prefix))
            return
        }
        try await finish(prefix: prefix, origins: info.origins, glass: glass, routing: routing, name: prefix, text: text, id: id, record: record)
    }

    private func finish(prefix: String, origins: [ASHolder], glass: LookingGlass, routing: RoutingStatus?, name: String,
                        text: String, id: Int, record: Bool) async throws {
        guard id == runID else { return }
        let paths = glass.routes.filter { !$0.asPath.isEmpty }
            .map { ObservedPath(asns: $0.asPath, collector: $0.collector, peerIP: $0.peerIP) }
        guard !paths.isEmpty else {
            fail(notAnnounced(name))
            return
        }
        let k = maxNodesPerLayer
        let located = await awaitLocate(timeout: .milliseconds(1500))
        guard id == runID else { return }
        if located.done { route.setMyNetwork(located.network) }
        let (graph, layout) = await Self.compute(paths: paths, k: k, pinned: pinned(located.network?.asn))
        guard id == runID else { return }
        var names: [UInt32: String] = [:]
        for origin in origins where !origin.holder.isEmpty { names[origin.asn] = origin.holder }
        let visibility = prefix.contains(":") ? routing?.v6 : routing?.v4
        let result = BGPResult(prefix: prefix, origins: origins, graph: graph, collectors: glass.collectors,
                               visibility: visibility, latestTime: glass.latestTime, names: names)
        rawPaths = paths
        install(result: result, layout: layout)
        updateSummary()
        phase = .loaded
        startRoute(result: result, locateDone: located.done, collectors: glass.collectors)
        if record { recents.record(text, tool: .bgp) }
        fetchMissingNames(id: id)
    }

    private func loadASN(_ asn: UInt32, text: String, id: Int, record: Bool) async throws {
        let holder: String?
        let prefixes: [String]
        if let cached = prefixCache[asn] {
            (holder, prefixes) = (cached.holder, cached.prefixes)
        } else {
            let api = api
            async let overview = api.asOverview(asn)
            async let announced = api.announcedPrefixes(asn)
            let info = try await overview
            let all = try await announced
            holder = info.holder
            prefixes = Self.sortPrefixes(all)
            prefixCache[asn] = (holder, prefixes)
        }
        guard id == runID else { return }
        guard !prefixes.isEmpty else {
            fail(BGPFailure(kind: .notAnnounced, message: String(localized: "AS\(String(asn)) doesn't announce any prefixes right now.")))
            return
        }
        if record { recents.record(text, tool: .bgp) }
        phase = .pickingPrefix(asn: asn, holder: holder, prefixes: prefixes)
    }

    /// IPv4 first, then shortest prefix first, then by address.
    static func sortPrefixes(_ prefixes: [String]) -> [String] {
        func key(_ prefix: String) -> (Int, Int, String) {
            let length = prefix.split(separator: "/").last.flatMap { Int($0) } ?? 0
            return (prefix.contains(":") ? 1 : 0, length, prefix)
        }
        return Array(Set(prefixes)).sorted { a, b in
            let (ka, kb) = (key(a), key(b))
            if ka.0 != kb.0 { return ka.0 < kb.0 }
            if ka.1 != kb.1 { return ka.1 < kb.1 }
            return ka.2.localizedStandardCompare(kb.2) == .orderedAscending
        }
    }

    // MARK: - Graph

    private func pinned(_ asn: UInt32?) -> Set<UInt32> { asn.map { [$0] } ?? [] }

    nonisolated private static func compute(paths: [ObservedPath], k: Int, pinned: Set<UInt32> = []) async -> (ASGraph, GraphLayout) {
        await Task.detached(priority: .userInitiated) {
            let graph = GraphBuilder.build(from: paths, options: GraphBuildOptions(maxNodesPerLayer: k, pinned: pinned))
            return (graph, LayeredLayout.layout(graph))
        }.value
    }

    func install(result: BGPResult, layout: GraphLayout) {
        self.result = result
        self.layout = layout
        stats = BGPStats(graph: result.graph)
        layoutVersion += 1
        updateHighlight()
    }

    private func rebuild() {
        guard result != nil, !rawPaths.isEmpty else { return }
        rebuildTask?.cancel()
        let paths = rawPaths, k = maxNodesPerLayer, id = runID, pins = pinned(myASN)
        rebuildTask = Task { [weak self] in
            let (graph, layout) = await Self.compute(paths: paths, k: k, pinned: pins)
            guard let self, !Task.isCancelled, id == self.runID, let current = self.result else { return }
            let updated = BGPResult(prefix: current.prefix, origins: current.origins, graph: graph, collectors: current.collectors,
                                    visibility: current.visibility, latestTime: current.latestTime, names: current.names)
            self.install(result: updated, layout: layout)
            self.updateSummary()
            if let pending = self.pendingSelection {
                self.pendingSelection = nil
                self.selection = pending
                self.detailsToken += 1
            } else if let selection = self.selection, self.stats?.summary(for: selection, graph: graph) == nil {
                self.selection = nil
            }
            self.fetchMissingNames(id: id)
        }
    }

    private func updateHighlight() {
        guard let selection, let result, let stats else {
            highlight = nil
            return
        }
        switch selection {
        case let .asn(asn):
            highlight = stats.highlight(through: [asn])
        case .more:
            guard let node = result.graph.node(selection) else {
                highlight = nil
                return
            }
            highlight = stats.highlight(through: Set(node.collapsed))
        }
    }

    /// The displayed node that stands for the selection (the bucket when the AS is collapsed).
    var selectedNodeID: NodeID? {
        guard let selection else { return nil }
        if case let .asn(asn) = selection { return stats?.nodeFor(asn) ?? selection }
        return selection
    }

    private func fetchMissingNames(id: Int) {
        guard let result else { return }
        var wanted = Set(result.originASNs)
        if let myASN { wanted.insert(myASN) }
        for node in result.graph.nodes {
            if case let .asn(asn) = node.id { wanted.insert(asn) }
            wanted.formUnion(node.collapsed)
        }
        let missing = wanted.subtracting(result.names.keys).sorted()
        guard !missing.isEmpty else { return }
        namesTask?.cancel()
        let api = api
        namesTask = Task { [weak self] in
            guard let names = try? await api.asNames(missing), !Task.isCancelled else { return }
            guard let self, id == self.runID else { return }
            self.result?.names.merge(names) { _, new in new }
            self.route.ingestNames(self.result?.names ?? names)
        }
    }

    // MARK: - Your route

    private func startLocating() {
        route.beginLocating()
        let locator = locator
        let generation = network?.pathGeneration ?? 0
        locateTask = Task { await locator.current(generation: generation) }
    }

    /// Races the locate task against a timeout. Both outcomes resume exactly once; the locate task itself
    /// is never cancelled, so the late path can still use its answer.
    private func awaitLocate(timeout: Duration) async -> (done: Bool, network: MyNetwork?) {
        guard let task = locateTask else { return (true, nil) }
        return await withCheckedContinuation { continuation in
            let gate = LocateRace(continuation)
            gate.tasks = [
                Task { gate.finish((true, await task.value)) },
                Task {
                    try? await Task.sleep(for: timeout)
                    gate.finish((false, nil))
                },
            ]
        }
    }

    func updateSummary() {
        guard let result else { summary = nil; return }
        summary = RoutesSummary(graph: result.graph, collectorCount: result.collectors.count, myASN: myASN)
    }

    private func routeContext(_ result: BGPResult, collectors: [LookingGlass.Collector]) -> RouteContext {
        let input = routeInput
        var locations: [String: String] = [:]
        for collector in collectors { locations[collector.id] = collector.location }
        return RouteContext(label: input?.label ?? result.prefix, address: input?.address, hostname: input?.hostname,
                            prefix: result.prefix, origins: result.originASNs, paths: result.graph.cleanedPaths,
                            collectorLocations: locations, snapshot: routeSnapshot)
    }

    private func startRoute(result: BGPResult, locateDone: Bool, collectors: [LookingGlass.Collector]) {
        let context = routeContext(result, collectors: collectors)
        route.ingestNames(result.names)
        if locateDone {
            route.begin(context, myNetwork: route.myNetwork)
            return
        }
        // whats-my-ip is slow: show the graph now and finish the route (and the pinned node) when it answers.
        guard let task = locateTask else { return }
        let id = runID
        lateTask = Task { [weak self] in
            let found = await task.value
            guard let self, !Task.isCancelled, id == self.runID else { return }
            self.route.setMyNetwork(found)
            if found?.asn != nil { self.rebuild() }
            self.updateSummary()
            self.route.begin(context, myNetwork: found)
        }
    }
}

/// Resumes its continuation exactly once and cancels the other racer.
@MainActor private final class LocateRace {
    private var continuation: CheckedContinuation<(done: Bool, network: MyNetwork?), Never>?
    var tasks: [Task<Void, Never>] = []

    init(_ continuation: CheckedContinuation<(done: Bool, network: MyNetwork?), Never>) { self.continuation = continuation }

    func finish(_ result: (done: Bool, network: MyNetwork?)) {
        guard let continuation else { return }
        self.continuation = nil
        for task in tasks { task.cancel() }
        continuation.resume(returning: result)
    }
}
