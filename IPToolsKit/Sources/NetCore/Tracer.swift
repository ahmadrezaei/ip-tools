// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

/// Stub: real traceroute implementation is owned by the NetCore agent.
public struct Tracer: TraceService {
    public init() {}

    public func trace(_ target: ResolvedTarget, options: TraceOptions) -> AsyncThrowingStream<TraceEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: NetError.socketUnavailable(errno: 78)) }   // ENOSYS
    }
}
