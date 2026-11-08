// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation

public protocol RIPEstatAPI: Sendable {
    func networkInfo(_ ip: String) async throws -> NetworkInfo
    func prefixOverview(_ prefix: String) async throws -> PrefixOverview
    func lookingGlass(_ resource: String) async throws -> LookingGlass        // ip or prefix
    func asOverview(_ asn: UInt32) async throws -> ASOverview
    func asNames(_ asns: [UInt32]) async throws -> [UInt32: String]          // chunks of 200 internally
    func announcedPrefixes(_ asn: UInt32) async throws -> [String]
    func routingStatus(_ prefix: String) async throws -> RoutingStatus
    func whatsMyIP() async throws -> WhatsMyIP        // GET whats-my-ip/data.json, never cached, 10 s timeout
}

public extension RIPEstatAPI {
    /// Keeps existing test fakes compiling.
    func whatsMyIP() async throws -> WhatsMyIP { throw RIPEstatError.api(messages: ["whats-my-ip not supported"]) }
}

public enum RIPEstatError: Error, Sendable, Equatable {
    case offline, timeout, rateLimited
    case http(status: Int)
    case api(messages: [String])          // status != "ok"
    case decoding(String)
}

/// Live RIPEstat Data API client.
///
/// `lookingGlass(_:)` is the graph's route source. It asks the `looking-glass` call first and falls back to
/// `bgp-state` (same RIS data, lighter, no AS_SETs, no collector locations) when `looking-glass` is empty or
/// fails. After a successful fallback, `looking-glass` is skipped for a while so a broken endpoint does not
/// cost an extra round trip on every map.
public final class RIPEstatClient: RIPEstatAPI, Sendable {
    private let session: URLSession
    private let baseURL: URL
    private let sourceApp: String
    private let gate: ConcurrencyGate
    private let cache = ResponseCache()
    private let names = NameCache()
    private let health = EndpointHealth()

    static let userAgent = "IPTools/1.0 (iOS; github.com/ahmadrezaei/ip-tools)"
    static let requestTimeout: TimeInterval = 30
    static let whatsMyIPTimeout: TimeInterval = 10
    static let namesChunkSize = 200

    public init(session: URLSession = .shared,
                baseURL: URL = URL(string: "https://stat.ripe.net/data/")!,
                sourceApp: String = "ahmadrezaei-iptools",
                maxConcurrent: Int = 4) {
        self.session = session
        self.baseURL = baseURL
        self.sourceApp = sourceApp
        self.gate = ConcurrencyGate(limit: max(1, maxConcurrent))
    }

    // MARK: RIPEstatAPI

    public func networkInfo(_ ip: String) async throws -> NetworkInfo {
        try RIPEstatParsing.networkInfo(try await fetch("network-info", resource: ip))
    }

    public func prefixOverview(_ prefix: String) async throws -> PrefixOverview {
        try RIPEstatParsing.prefixOverview(try await fetch("prefix-overview", resource: prefix), resource: prefix)
    }

    public func lookingGlass(_ resource: String) async throws -> LookingGlass {
        var firstError: Error?
        if await !health.shouldSkipLookingGlass() {
            do {
                let result = try RIPEstatParsing.lookingGlass(try await fetch("looking-glass", resource: resource))
                if !result.routes.isEmpty { return result }
                firstError = nil
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as RIPEstatError {
                switch error {
                case .offline, .api: throw error           // the fallback would fail the same way
                default: firstError = error
                }
            }
            let emptied = firstError == nil
            do {
                let fallback = try await bgpState(resource)
                if !fallback.routes.isEmpty { await health.lookingGlassFailed(empty: emptied) }
                return fallback
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if let firstError { throw firstError }
                throw error
            }
        }
        return try await bgpState(resource)
    }

    public func asOverview(_ asn: UInt32) async throws -> ASOverview {
        try RIPEstatParsing.asOverview(try await fetch("as-overview", resource: "AS\(asn)"), asn: asn)
    }

    public func asNames(_ asns: [UInt32]) async throws -> [UInt32: String] {
        var result: [UInt32: String] = [:]
        var missing: [UInt32] = []
        for asn in Set(asns).sorted() {
            if let name = await names.name(for: asn) { result[asn] = name } else { missing.append(asn) }
        }
        guard !missing.isEmpty else { return result }
        let chunks = stride(from: 0, to: missing.count, by: Self.namesChunkSize).map {
            Array(missing[$0..<min($0 + Self.namesChunkSize, missing.count)])
        }
        let fetched = try await withThrowingTaskGroup(of: [UInt32: String].self) { group in
            for chunk in chunks {
                group.addTask {
                    let resource = chunk.map(String.init).joined(separator: ",")
                    return try RIPEstatParsing.asNames(try await self.fetch("as-names", resource: resource))
                }
            }
            var merged: [UInt32: String] = [:]
            for try await part in group { merged.merge(part) { a, _ in a } }
            return merged
        }
        await names.store(fetched)
        for (asn, name) in fetched where Set(asns).contains(asn) { result[asn] = name }
        return result
    }

    public func announcedPrefixes(_ asn: UInt32) async throws -> [String] {
        try RIPEstatParsing.announcedPrefixes(try await fetch("announced-prefixes", resource: "AS\(asn)"))
    }

    public func routingStatus(_ prefix: String) async throws -> RoutingStatus {
        try RIPEstatParsing.routingStatus(try await fetch("routing-status", resource: prefix))
    }

    public func whatsMyIP() async throws -> WhatsMyIP {
        try RIPEstatParsing.whatsMyIP(try await fetch("whats-my-ip", resource: nil, cached: false,
                                                       timeout: Self.whatsMyIPTimeout))
    }

    // MARK: Internals

    func bgpState(_ resource: String) async throws -> LookingGlass {
        try RIPEstatParsing.bgpState(try await fetch("bgp-state", resource: resource))
    }

    func url(call: String, resource: String?) -> URL {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~/:,")
        let encoded = resource.flatMap { $0.addingPercentEncoding(withAllowedCharacters: allowed) } ?? ""
        let source = sourceApp.addingPercentEncoding(withAllowedCharacters: allowed) ?? sourceApp
        var components = URLComponents(url: baseURL.appendingPathComponent(call).appendingPathComponent("data.json"),
                                       resolvingAgainstBaseURL: false)!
        components.percentEncodedQuery = resource == nil
            ? "sourceapp=\(source)" : "resource=\(encoded)&sourceapp=\(source)"
        return components.url!
    }

    /// GET with caching, concurrency limit, and HTTP/URL error mapping. Returns the body of a 2xx response, or of
    /// a 4xx response that carries a RIPEstat envelope (so the parser can raise `.api(messages:)`).
    func fetch(_ call: String, resource: String?, cached useCache: Bool = true,
               timeout: TimeInterval = RIPEstatClient.requestTimeout) async throws -> Data {
        let url = url(call: call, resource: resource)
        if useCache, let cached = await cache.data(for: url) { return cached }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        if !useCache { request.cachePolicy = .reloadIgnoringLocalCacheData }
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        try await gate.acquire()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
            await gate.release()
        } catch {
            await gate.release()
            throw Self.map(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        switch status {
        case 200..<300:
            // Cache only envelopes that report success.
            if useCache, let probe = try? JSONDecoder().decode(EnvelopeProbe.self, from: data), probe.status == "ok" {
                await cache.store(data, for: url)
            }
            return data
        case 429:
            throw RIPEstatError.rateLimited
        case 500...:
            throw RIPEstatError.http(status: status)
        default:
            if (try? JSONDecoder().decode(EnvelopeProbe.self, from: data)) != nil { return data }
            throw RIPEstatError.http(status: status)
        }
    }

    static func map(_ error: Error) -> Error {
        if error is CancellationError { return error }
        guard let urlError = error as? URLError else { return error }
        switch urlError.code {
        case .cancelled: return CancellationError()
        case .timedOut: return RIPEstatError.timeout
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff,
             .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return RIPEstatError.offline
        default: return RIPEstatError.http(status: 0)
        }
    }
}

// MARK: - Support actors

/// Limits in-flight requests (etiquette: at most 4).
actor ConcurrencyGate {
    private var available: Int
    private var waiters: [(id: UInt64, continuation: CheckedContinuation<Void, any Error>)] = []
    private var nextID: UInt64 = 0

    init(limit: Int) { available = limit }

    func acquire() async throws {
        try Task.checkCancellation()
        if available > 0 {
            available -= 1
            return
        }
        let id = nextID
        nextID += 1
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    c.resume(throwing: CancellationError())
                } else {
                    waiters.append((id, c))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UInt64) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    func release() {
        if waiters.isEmpty { available += 1 } else { waiters.removeFirst().continuation.resume() }
    }

    var waitingCount: Int { waiters.count }
}

/// In-memory response cache: keyed by URL, 5 minute TTL, bounded.
actor ResponseCache {
    private var entries: [URL: (data: Data, stored: Date)] = [:]
    private let ttl: TimeInterval = 300
    private let maxEntries = 40

    func data(for url: URL) -> Data? {
        guard let entry = entries[url] else { return nil }
        if Date().timeIntervalSince(entry.stored) > ttl {
            entries[url] = nil
            return nil
        }
        return entry.data
    }

    func store(_ data: Data, for url: URL) {
        if entries.count >= maxEntries, let oldest = entries.min(by: { $0.value.stored < $1.value.stored })?.key {
            entries[oldest] = nil
        }
        entries[url] = (data, Date())
    }
}

/// AS names are stable for the session.
actor NameCache {
    private var names: [UInt32: String] = [:]
    func name(for asn: UInt32) -> String? { names[asn] }
    func store(_ new: [UInt32: String]) { names.merge(new) { _, b in b } }
}

/// Remembers that `looking-glass` is not delivering, so `bgp-state` is used directly for a while.
actor EndpointHealth {
    private var skipUntil: Date?

    func shouldSkipLookingGlass() -> Bool {
        guard let skipUntil else { return false }
        if Date() >= skipUntil {
            self.skipUntil = nil
            return false
        }
        return true
    }

    /// An empty answer that `bgp-state` contradicted is a sticky condition (10 min); an error is retried soon.
    func lookingGlassFailed(empty: Bool) {
        skipUntil = Date().addingTimeInterval(empty ? 600 : 60)
    }
}
