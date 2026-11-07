// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation

public struct TraceOptions: Codable, Hashable, Sendable {
    public var maxHops: Int = 30
    public var probesPerHop: Int = 3
    public var timeout: TimeInterval = 2.0
    public static let `default` = TraceOptions()
    public init() {}
}

public enum ProbeResult: Hashable, Sendable {
    case timeExceeded(from: IPAddress, rtt: TimeInterval)
    case echoReply(from: IPAddress, rtt: TimeInterval)          // reached the target
    case unreachable(from: IPAddress, rtt: TimeInterval, code: UInt8)
    case timeout

    public var address: IPAddress? {
        switch self {
        case let .timeExceeded(from, _), let .echoReply(from, _), let .unreachable(from, _, _): return from
        case .timeout: return nil
        }
    }

    public var rtt: TimeInterval? {
        switch self {
        case let .timeExceeded(_, rtt), let .echoReply(_, rtt), let .unreachable(_, rtt, _): return rtt
        case .timeout: return nil
        }
    }
}

public enum TraceCompletion: Hashable, Sendable {
    case reachedDestination(hops: Int)
    case unreachable(atHop: Int, code: UInt8)
    case maxHopsExceeded
}

public enum TraceEvent: Hashable, Sendable {
    case probe(ttl: Int, index: Int, result: ProbeResult)
    case hopFinished(ttl: Int)
    case finished(TraceCompletion)
}

public protocol TraceService: Sendable {
    func trace(_ target: ResolvedTarget, options: TraceOptions) -> AsyncThrowingStream<TraceEvent, Error>
}
