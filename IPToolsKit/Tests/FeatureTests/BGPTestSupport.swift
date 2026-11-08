// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import BGPGraph
import Foundation
import NetCore
import RIPEstat
import SharedUI
@testable import BGPFeature

/// RIPEstat stand-in for the BGP tests: a tiny world around 8.8.8.0/24 (origin AS15169) with fixed RIS paths.
final class BGPFakeAPI: RIPEstatAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var _whatsMyIPCalls = 0
    private var _networkInfoCalls: [String] = []

    var myIP: String? = "91.107.240.242"
    var whatsMyIPDelay: Duration?
    var failNetworkInfo: Set<String> = []
    var risPaths: [[UInt32]] = [[3320, 15169], [3320, 15169], [1299, 15169], [1299, 15169], [1299, 15169],
                                [174, 3356, 15169], [6939, 1299, 15169]]
    var infoByIP: [String: NetworkInfo] = [
        "8.8.8.8": NetworkInfo(prefix: "8.8.8.0/24", originASNs: [15169]),
        "108.170.255.223": NetworkInfo(prefix: "108.170.254.0/23", originASNs: [15169]),
        "72.14.237.93": NetworkInfo(prefix: "72.14.236.0/22", originASNs: [15169]),
        "104.28.0.0": NetworkInfo(prefix: "104.28.0.0/16", originASNs: [13335]),
        "172.71.133.1": NetworkInfo(prefix: "172.71.128.0/20", originASNs: [13335]),
        "141.101.67.186": NetworkInfo(prefix: "141.101.64.0/18", originASNs: [13335]),
        "141.101.67.57": NetworkInfo(prefix: "141.101.64.0/18", originASNs: [13335]),
        "62.115.0.1": NetworkInfo(prefix: "62.115.0.0/16", originASNs: [1299]),
        "91.107.240.242": NetworkInfo(prefix: "91.107.128.0/17", originASNs: [24940]),
        "80.150.0.1": NetworkInfo(prefix: "80.150.0.0/16", originASNs: [3320]),
    ]
    var names: [UInt32: String] = [
        15169: "GOOGLE - Google LLC", 13335: "CLOUDFLARENET - Cloudflare, Inc.", 1299: "TWELVE99 Arelion Sweden AB",
        24940: "HETZNER-AS Hetzner Online GmbH", 3320: "DTAG Deutsche Telekom AG", 174: "COGENT-174 - Cogent", 3356: "LEVEL3 - Level 3",
        6939: "HURRICANE - Hurricane Electric",
    ]

    var whatsMyIPCalls: Int { lock.withLock { _whatsMyIPCalls } }
    var networkInfoCalls: [String] { lock.withLock { _networkInfoCalls } }

    func whatsMyIP() async throws -> WhatsMyIP {
        lock.withLock { _whatsMyIPCalls += 1 }
        if let delay = whatsMyIPDelay { try await Task.sleep(for: delay) }
        guard let myIP else { throw RIPEstatError.offline }
        return WhatsMyIP(ip: myIP)
    }

    func networkInfo(_ ip: String) async throws -> NetworkInfo {
        lock.withLock { _networkInfoCalls.append(ip) }
        if failNetworkInfo.contains(ip) { throw RIPEstatError.offline }
        guard let info = infoByIP[ip] else { return NetworkInfo(prefix: nil, originASNs: []) }
        return info
    }

    func lookingGlass(_ resource: String) async throws -> LookingGlass {
        let routes = risPaths.enumerated().map { index, path in
            LookingGlass.Route(collector: String(format: "RRC%02d", index % 3 + 1), peerIP: "192.0.2.\(index + 1)",
                               prefix: "8.8.8.0/24", asPath: path, hadASSet: false,
                               rawASPath: path.map(String.init).joined(separator: " "), lastUpdated: nil)
        }
        let collectors = (1...3).map { LookingGlass.Collector(id: String(format: "RRC%02d", $0), location: "City \($0), XX") }
        return LookingGlass(collectors: collectors, routes: routes, latestTime: Date())
    }

    func prefixOverview(_ prefix: String) async throws -> PrefixOverview {
        PrefixOverview(resource: prefix, announced: true, origins: [ASHolder(asn: 15169, holder: names[15169] ?? "")])
    }

    func asNames(_ asns: [UInt32]) async throws -> [UInt32: String] { names.filter { asns.contains($0.key) } }
    func asOverview(_ asn: UInt32) async throws -> ASOverview { throw RIPEstatError.offline }
    func announcedPrefixes(_ asn: UInt32) async throws -> [String] { throw RIPEstatError.offline }
    func routingStatus(_ prefix: String) async throws -> RoutingStatus { throw RIPEstatError.offline }
}

/// Counts how many traces were started, then delegates.
final class CountingTraceService: TraceService, @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    private let inner: any TraceService
    init(_ inner: any TraceService) { self.inner = inner }
    var count: Int { lock.withLock { _count } }
    func trace(_ target: ResolvedTarget, options: TraceOptions) -> AsyncThrowingStream<TraceEvent, Error> {
        lock.withLock { _count += 1 }
        return inner.trace(target, options: options)
    }
}

struct FailingTraceService: TraceService {
    let error: NetError
    func trace(_ target: ResolvedTarget, options: TraceOptions) -> AsyncThrowingStream<TraceEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: error) }
    }
}

enum Probes {
    static func hop(_ ip: String, ms: Double = 10) -> [ProbeResult] {
        [.timeExceeded(from: IPAddress(ip)!, rtt: ms / 1000), .timeExceeded(from: IPAddress(ip)!, rtt: (ms + 1) / 1000)]
    }
    static var silent: [ProbeResult] { [.timeout, .timeout] }
    static func reply(_ ip: String, ms: Double = 10) -> [ProbeResult] {
        [.echoReply(from: IPAddress(ip)!, rtt: ms / 1000), .echoReply(from: IPAddress(ip)!, rtt: (ms + 1) / 1000)]
    }
    static func unreachable(_ ip: String) -> [ProbeResult] {
        [.unreachable(from: IPAddress(ip)!, rtt: 0.02, code: 1), .unreachable(from: IPAddress(ip)!, rtt: 0.02, code: 1)]
    }

    static let local: [[ProbeResult]] = [hop("192.168.70.1", ms: 3), hop("172.16.21.1", ms: 100), hop("10.99.7.1", ms: 120)]
    static let cloudflare: [[ProbeResult]] = [hop("104.28.0.0", ms: 136), hop("172.71.133.1", ms: 136), hop("141.101.67.186", ms: 136),
                                              hop("141.101.67.57", ms: 144)]
    static let google: [[ProbeResult]] = [hop("108.170.255.223", ms: 146), hop("72.14.237.93", ms: 145)]

    /// The worked example of DESIGN 6.11.6: 8.8.8.8 from AS24940.
    static var worked: [[ProbeResult]] { local + cloudflare + google + [silent, reply("8.8.8.8", ms: 144)] }

    static func service(_ hops: [[ProbeResult]], delay: Duration = .milliseconds(1)) -> MockTraceService {
        MockTraceService(hops: hops, delay: delay)
    }
}

@MainActor func makeBGPModel(api: any RIPEstatAPI, service: (any TraceService)?, settings: SettingsStore? = nil,
                             router: AppRouter = AppRouter(selectedTool: .bgp)) -> BGPMapModel {
    BGPMapModel(api: api, recents: makeRecents(), router: router, traceService: service, settings: settings ?? makeSettings())
}

func snapshot(of target: String, hops: [(Int, String?, UInt32?)], finishedAt: Date, reached: Bool = true) -> TraceSnapshot {
    let list = hops.map { ttl, address, asn in
        TraceSnapshot.Hop(ttl: ttl, address: address.flatMap(IPAddress.init), hostname: nil, asn: asn, rtts: address == nil ? [] : [0.01],
                          reachedTarget: reached && ttl == hops.last?.0)
    }
    return TraceSnapshot(target: resolvedTarget(target), hops: list, completion: reached ? .reachedDestination(hops: hops.count) : nil,
                         finishedAt: finishedAt)
}

/// Yields (no fixed sleeps) until `condition` holds or `timeout` passes.
@MainActor func bgpWait(timeout: Duration = .seconds(10), _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition(), ContinuousClock.now < deadline { await Task.yield() }
    return condition()
}

/// Forwards to `BGPFakeAPI`, but `asNames` waits on a gate and can fail on demand.
final class GatedNamesAPI: RIPEstatAPI, @unchecked Sendable {
    let inner = BGPFakeAPI()
    private let lock = NSLock()
    private var _calls: [[UInt32]] = []
    private var _failFirst = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var _open = true
    var calls: [[UInt32]] { lock.withLock { _calls } }
    func closeGate() { lock.withLock { _open = false } }
    func openGate() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            _open = true
            defer { waiters = [] }
            return waiters
        }
        for waiter in pending { waiter.resume() }
    }
    func failFirstCall() { lock.withLock { _failFirst = true } }

    func asNames(_ asns: [UInt32]) async throws -> [UInt32: String] {
        let fail = lock.withLock { () -> Bool in
            _calls.append(asns)
            defer { _failFirst = false }
            return _failFirst
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumeNow = lock.withLock { () -> Bool in
                if _open { return true }
                waiters.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
        try Task.checkCancellation()     // an in-flight fetch must not be cancelled by a newer request
        if fail { throw RIPEstatError.offline }
        return try await inner.asNames(asns)
    }
    func whatsMyIP() async throws -> WhatsMyIP { try await inner.whatsMyIP() }
    func networkInfo(_ ip: String) async throws -> NetworkInfo { try await inner.networkInfo(ip) }
    func lookingGlass(_ resource: String) async throws -> LookingGlass { try await inner.lookingGlass(resource) }
    func prefixOverview(_ prefix: String) async throws -> PrefixOverview { try await inner.prefixOverview(prefix) }
    func asOverview(_ asn: UInt32) async throws -> ASOverview { try await inner.asOverview(asn) }
    func announcedPrefixes(_ asn: UInt32) async throws -> [String] { try await inner.announcedPrefixes(asn) }
    func routingStatus(_ prefix: String) async throws -> RoutingStatus { try await inner.routingStatus(prefix) }
}
