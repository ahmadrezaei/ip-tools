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
}

public enum RIPEstatError: Error, Sendable, Equatable {
    case offline, timeout, rateLimited
    case http(status: Int)
    case api(messages: [String])          // status != "ok"
    case decoding(String)
}

/// Stub: the real client is owned by the data agent. Every call throws `.decoding("not implemented")`.
public final class RIPEstatClient: RIPEstatAPI, Sendable {
    private let session: URLSession
    private let baseURL: URL
    private let sourceApp: String
    private let maxConcurrent: Int

    public init(session: URLSession = .shared,
                baseURL: URL = URL(string: "https://stat.ripe.net/data/")!,
                sourceApp: String = "ahmadrezaei-iptools",
                maxConcurrent: Int = 4) {
        self.session = session
        self.baseURL = baseURL
        self.sourceApp = sourceApp
        self.maxConcurrent = maxConcurrent
    }

    private var notImplemented: RIPEstatError { .decoding("not implemented") }

    public func networkInfo(_ ip: String) async throws -> NetworkInfo { throw notImplemented }
    public func prefixOverview(_ prefix: String) async throws -> PrefixOverview { throw notImplemented }
    public func lookingGlass(_ resource: String) async throws -> LookingGlass { throw notImplemented }
    public func asOverview(_ asn: UInt32) async throws -> ASOverview { throw notImplemented }
    public func asNames(_ asns: [UInt32]) async throws -> [UInt32: String] { throw notImplemented }
    public func announcedPrefixes(_ asn: UInt32) async throws -> [String] { throw notImplemented }
    public func routingStatus(_ prefix: String) async throws -> RoutingStatus { throw notImplemented }
}
