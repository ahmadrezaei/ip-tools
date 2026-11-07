// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

/// Stub: real ICMP echo implementation is owned by the NetCore agent.
public struct Pinger: PingService {
    public init() {}

    public func ping(_ target: ResolvedTarget, options: PingOptions) -> AsyncThrowingStream<PingSample, Error> {
        AsyncThrowingStream { $0.finish(throwing: NetError.socketUnavailable(errno: 78)) }   // ENOSYS
    }
}
