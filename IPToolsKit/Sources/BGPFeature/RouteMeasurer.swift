// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import BGPGraph
import Foundation
import NetCore
import RIPEstat

/// Quick traceroute with hop -> ASN lookups and early-stop rules (DESIGN 6.11.5).
struct RouteMeasurer: Sendable {
    enum Update: Sendable { case hops([ChainHop]), finished(reachedOrigin: Bool, stop: Stop), failed(Error) }

    /// Why the trace ended: by itself, or by an early-stop rule (DESIGN 6.11.5).
    enum Stop: Sendable, Equatable { case traceEnded, originReached, originSilent, stalled }

    enum Lookup: Sendable, Equatable { case found(UInt32?), failed }

    static let options: TraceOptions = {
        var options = TraceOptions()
        options.maxHops = 30
        options.probesPerHop = 2
        options.timeout = 1.5
        return options
    }()

    /// Longest wait for outstanding ASN lookups once the trace has ended: 4 s + 1 s per 4 pending, at most 10 s.
    static func lookupGrace(pending: Int) -> Duration { .seconds(min(10, 4 + pending / 4)) }

    /// `networkInfo` for one hop address, retried once. `.found(nil)` means "not announced"; `.failed` means unknown.
    static func lookup(_ address: String, api: any RIPEstatAPI) async -> Lookup {
        for _ in 0..<2 {
            if Task.isCancelled { break }
            if let info = try? await api.networkInfo(address) { return .found(info.originASNs.first) }
        }
        return .failed
    }

    private let service: any TraceService
    private let api: any RIPEstatAPI

    init(service: any TraceService, api: any RIPEstatAPI) {
        self.service = service
        self.api = api
    }

    func measure(_ target: ResolvedTarget, origins: Set<UInt32>, prefixTarget: Bool) -> AsyncStream<Update> {
        let service = service, api = api
        return AsyncStream { continuation in
            let task = Task {
                let run = Run(target: target, origins: origins, prefixTarget: prefixTarget, service: service, api: api,
                              continuation: continuation)
                await run.drive()
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private final class Run {
    enum Event: Sendable {
        case trace(TraceEvent), traceEnded(Error?), asn(IPAddress, RouteMeasurer.Lookup), deadline
    }

    struct Hop {
        var address: IPAddress?
        var rtts: [TimeInterval] = []
        var finished = false
        var reached = false
    }

    let target: ResolvedTarget
    let origins: Set<UInt32>
    let prefixTarget: Bool
    let service: any TraceService
    let api: any RIPEstatAPI
    let continuation: AsyncStream<RouteMeasurer.Update>.Continuation

    var hops: [Int: Hop] = [:]
    var asns: [IPAddress: RouteMeasurer.Lookup] = [:]
    var pending: Set<IPAddress> = []
    var finalizing = false
    var done = false
    var lastEmitted: [ChainHop] = []
    var failure: Error?
    var stoppedEarly = false

    init(target: ResolvedTarget, origins: Set<UInt32>, prefixTarget: Bool, service: any TraceService, api: any RIPEstatAPI,
         continuation: AsyncStream<RouteMeasurer.Update>.Continuation) {
        self.target = target
        self.origins = origins
        self.prefixTarget = prefixTarget
        self.service = service
        self.api = api
        self.continuation = continuation
    }

    func drive() async {
        let (events, sink) = AsyncStream.makeStream(of: Event.self)
        let service = service, target = target
        let traceTask = Task {
            do {
                for try await event in service.trace(target, options: RouteMeasurer.options) { sink.yield(.trace(event)) }
                sink.yield(.traceEnded(nil))
            } catch {
                sink.yield(.traceEnded(error))
            }
        }
        var helpers: [Task<Void, Never>] = []
        defer {
            traceTask.cancel()
            for helper in helpers { helper.cancel() }
        }
        for await event in events {
            switch event {
            case let .trace(trace):
                guard !finalizing else { continue }
                handle(trace)
                for address in unresolvedAddresses() {
                    pending.insert(address)
                    let api = api
                    helpers.append(Task {
                        sink.yield(.asn(address, await RouteMeasurer.lookup(address.description, api: api)))
                    })
                }
                if !finalizing, earlyStop() {
                    stoppedEarly = true
                    traceTask.cancel()
                    beginFinalizing(sink: sink, helpers: &helpers)
                }
            case let .traceEnded(error):
                guard !finalizing else { continue }
                if let error, !(error is CancellationError) {
                    failure = error
                    done = true
                } else {
                    beginFinalizing(sink: sink, helpers: &helpers)
                }
            case let .asn(address, asn):
                pending.remove(address)
                asns[address] = asn
                if !finalizing, earlyStop() {
                    stoppedEarly = true
                    traceTask.cancel()
                    beginFinalizing(sink: sink, helpers: &helpers)
                }
            case .deadline:
                done = true
            }
            if finalizing, pending.isEmpty { done = true }
            emitHops()
            if done { break }
        }
        guard !Task.isCancelled else { return }
        emitHops()
        if let failure {
            continuation.yield(.failed(failure))
        } else {
            continuation.yield(.finished(reachedOrigin: lastNetworkASN.map(origins.contains) ?? false, stop: stopKind()))
        }
    }

    private func beginFinalizing(sink: AsyncStream<Event>.Continuation, helpers: inout [Task<Void, Never>]) {
        finalizing = true
        guard !pending.isEmpty else { done = true; return }
        let grace = RouteMeasurer.lookupGrace(pending: pending.count)
        helpers.append(Task {
            try? await Task.sleep(for: grace)
            sink.yield(.deadline)
        })
    }

    // MARK: State

    private func handle(_ event: TraceEvent) {
        switch event {
        case let .probe(ttl, _, result):
            var hop = hops[ttl] ?? Hop()
            switch result {
            case let .timeExceeded(from, rtt), let .unreachable(from, rtt, _):
                if hop.address == nil { hop.address = from }
                hop.rtts.append(rtt)
            case let .echoReply(from, rtt):
                if hop.address == nil { hop.address = from }
                hop.rtts.append(rtt)
                hop.reached = true
            case .timeout:
                break
            }
            hops[ttl] = hop
        case let .hopFinished(ttl):
            hops[ttl, default: Hop()].finished = true
        case .finished:
            break
        }
    }

    private func unresolvedAddresses() -> [IPAddress] {
        var result: [IPAddress] = []
        for ttl in hops.keys.sorted() {
            guard let address = hops[ttl]?.address, address.isPubliclyRoutable,
                  asns[address] == nil, !pending.contains(address), !result.contains(address) else { continue }
            result.append(address)
        }
        return result
    }

    private func asn(of hop: Hop) -> UInt32? {
        guard let address = hop.address, case let .found(value)? = asns[address] else { return nil }
        return value
    }

    private var lastNetworkASN: UInt32? {
        for ttl in hops.keys.sorted(by: >) { if let value = asn(of: hops[ttl]!) { return value } }
        return nil
    }

    private var originTTL: Int? {
        hops.filter { asn(of: $0.value).map(origins.contains) ?? false }.keys.min()
    }

    private func silentRun(after originTTL: Int?) -> Int {
        var silent = 0
        var ttl = (hops.filter { $0.value.finished }.keys.max()) ?? 0
        while ttl >= 1, let hop = hops[ttl], hop.finished, hop.address == nil {
            if let originTTL, ttl <= originTTL { break }
            silent += 1
            ttl -= 1
        }
        return silent
    }

    /// Rules c, d, e of DESIGN 6.11.5. (a, b and f are the trace ending by itself.)
    private func earlyStop() -> Bool {
        let origin = originTTL
        if prefixTarget, origin != nil { return true }
        let silent = silentRun(after: origin)
        return origin != nil ? silent >= 3 : silent >= 5
    }

    private func stopKind() -> RouteMeasurer.Stop {
        guard stoppedEarly else { return .traceEnded }
        if originTTL == nil { return .stalled }
        return prefixTarget ? .originReached : .originSilent
    }

    private func chainHops() -> [ChainHop] {
        hops.keys.sorted().compactMap { ttl -> ChainHop? in
            let hop = hops[ttl]!
            let hostname = hop.reached ? target.hostname : nil
            guard let address = hop.address else {
                return hop.finished ? ChainHop(ttl: ttl, kind: .silent) : nil
            }
            let kind: ChainHop.Kind
            if !address.isPubliclyRoutable {
                kind = .privateAddress
            } else if let value = asn(of: hop) {
                kind = .network(value)
            } else {
                kind = .unknownNetwork
            }
            return ChainHop(ttl: ttl, kind: kind, address: address.description, hostname: hostname,
                            rtts: hop.rtts, reachedTarget: hop.reached)
        }
    }

    private func emitHops() {
        let current = chainHops()
        guard current != lastEmitted else { return }
        lastEmitted = current
        continuation.yield(.hops(current))
    }
}
