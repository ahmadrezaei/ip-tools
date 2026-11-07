// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation

public struct ICMPPacket: Sendable {
    public let message: ICMPMessage
    public let from: IPAddress
    public let ttl: Int?
    public let byteCount: Int
    public let receivedAt: ContinuousClock.Instant

    public init(message: ICMPMessage, from: IPAddress, ttl: Int?, byteCount: Int, receivedAt: ContinuousClock.Instant) {
        self.message = message
        self.from = from
        self.ttl = ttl
        self.byteCount = byteCount
        self.receivedAt = receivedAt
    }
}

/// Stub: the real socket implementation is owned by the NetCore agent.
public final class ICMPSocket: @unchecked Sendable {
    public init(family: IPAddress.Family) throws {
        throw NetError.socketUnavailable(errno: ENOSYS)
    }

    public func send(_ bytes: [UInt8], to: IPAddress, hopLimit: Int? = nil) throws -> ContinuousClock.Instant {
        throw NetError.sendFailed(errno: ENOSYS)
    }

    public var packets: AsyncStream<ICMPPacket> {
        AsyncStream { $0.finish() }
    }

    public func close() {}
}
