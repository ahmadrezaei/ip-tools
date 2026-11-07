// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation

/// Replays `hops` (index 0 = TTL 1), one `.probe` per entry, then `.hopFinished` per hop and `.finished`.
public struct MockTraceService: TraceService {
    private let hops: [[ProbeResult]]
    private let delay: Duration

    public init(hops: [[ProbeResult]], delay: Duration = .milliseconds(250)) {
        self.hops = hops
        self.delay = delay
    }

    public func trace(_ target: ResolvedTarget, options: TraceOptions) -> AsyncThrowingStream<TraceEvent, Error> {
        let hops = hops
        let delay = delay
        return AsyncThrowingStream { continuation in
            let task = Task {
                var completion: TraceCompletion = .maxHopsExceeded
                for (offset, probes) in hops.prefix(options.maxHops).enumerated() {
                    let ttl = offset + 1
                    for (index, result) in probes.enumerated() {
                        do { try await Task.sleep(for: delay) } catch { continuation.finish(); return }
                        continuation.yield(.probe(ttl: ttl, index: index, result: result))
                    }
                    continuation.yield(.hopFinished(ttl: ttl))
                    if probes.contains(where: { if case .echoReply = $0 { true } else { false } }) {
                        completion = .reachedDestination(hops: ttl)
                        break
                    }
                    if let code = probes.compactMap({ r -> UInt8? in
                        if case let .unreachable(_, _, code) = r { code } else { nil }
                    }).first {
                        completion = .unreachable(atHop: ttl, code: code)
                        break
                    }
                }
                continuation.yield(.finished(completion))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
