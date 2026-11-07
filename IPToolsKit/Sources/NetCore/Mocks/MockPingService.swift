// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation

/// Replays `script` (cycling when `options.count` exceeds its length, or forever when count is nil).
public struct MockPingService: PingService {
    private let script: [PingSample.Outcome]
    private let interval: Duration

    public init(script: [PingSample.Outcome], interval: Duration = .milliseconds(300)) {
        self.script = script
        self.interval = interval
    }

    public func ping(_ target: ResolvedTarget, options: PingOptions) -> AsyncThrowingStream<PingSample, Error> {
        let script = script
        let interval = interval
        return AsyncThrowingStream { continuation in
            let task = Task {
                guard !script.isEmpty else { continuation.finish(); return }
                var sequence = 0
                while !Task.isCancelled, options.count.map({ sequence < $0 }) ?? true {
                    do { try await Task.sleep(for: interval) } catch { break }
                    let outcome = script[sequence % script.count]
                    continuation.yield(PingSample(sequence: sequence, sentAt: Date(), outcome: outcome))
                    if case let .error(error) = outcome, case .socketUnavailable = error {
                        continuation.finish(throwing: error)
                        return
                    }
                    sequence += 1
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
