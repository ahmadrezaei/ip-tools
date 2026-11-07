// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation

/// ICMP echo implementation of `PingService`.
///
/// Behaviour: probes go out on a fixed schedule (`t0 + n * interval`). One `PingSample` is emitted per
/// probe as soon as its outcome is known (reply, timeout, unreachable or send error), so samples can
/// complete out of order when `timeout > interval`. A late reply after the timeout is ignored.
/// A failure to send probe 0 (or to open the socket) finishes the stream by throwing `NetError`;
/// later send failures become `.error` samples. Cancelling the consuming task stops promptly and
/// closes the socket.
public struct Pinger: PingService {
    public init() {}

    public func ping(_ target: ResolvedTarget, options: PingOptions) -> AsyncThrowingStream<PingSample, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await Self.run(target, options, continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func run(_ target: ResolvedTarget, _ options: PingOptions,
                            _ continuation: AsyncThrowingStream<PingSample, Error>.Continuation) async throws {
        let socket = try ICMPSocket(family: target.address.family)
        let state = PingState(identifier: UInt16.random(in: 1...UInt16.max),
                              nonce: (0..<8).map { _ in UInt8.random(in: 0...255) },
                              continuation: continuation)
        let clock = ContinuousClock()
        let timeout = Duration.seconds(max(options.timeout, 0.05))
        let size = min(max(options.payloadSize, 8), 9000)

        try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await packet in socket.packets { state.handle(packet) }
                }
                group.addTask {   // timeout ticker
                    while !Task.isCancelled {
                        try? await clock.sleep(for: .milliseconds(20))
                        state.expire(now: clock.now)
                    }
                }
                group.addTask {   // sender
                    let t0 = clock.now
                    var n = 0
                    while options.count.map({ n < $0 }) ?? true {
                        try await clock.sleep(until: t0 + .seconds(options.interval * Double(n)))
                        try Task.checkCancellation()
                        let seq = UInt16(truncatingIfNeeded: n)
                        let payload = state.nonce + (0..<(size - 8)).map { UInt8(truncatingIfNeeded: $0 &+ 8) }
                        let packet = ICMPCodec.echoRequest(family: target.address.family,
                                                           identifier: state.identifier, sequence: seq, payload: payload)
                        let sentAt = Date()
                        do {
                            let sentInstant = try socket.send(packet, to: target.address)
                            state.sent(n, wire: seq, sentAt: sentAt, instant: sentInstant, deadline: sentInstant + timeout)
                        } catch let error as NetError {
                            if n == 0 { throw error }
                            continuation.yield(PingSample(sequence: n, sentAt: sentAt, outcome: .error(error)))
                        }
                        n += 1
                    }
                    while state.hasPending {
                        try await clock.sleep(for: .milliseconds(20))
                    }
                }
                defer { socket.close(); group.cancelAll() }
                _ = try await group.next()   // the receiver and ticker only end on cancellation, so this is the sender
                // a thrown error propagates; normal completion falls through to the defer
            }
        } onCancel: {
            socket.close()
        }
    }
}

private final class PingState: @unchecked Sendable {
    struct Pending {
        let sequence: Int
        let sentAt: Date
        let instant: ContinuousClock.Instant
        let deadline: ContinuousClock.Instant
    }

    let identifier: UInt16
    let nonce: [UInt8]
    private let continuation: AsyncThrowingStream<PingSample, Error>.Continuation
    private let lock = NSLock()
    private var pending: [UInt16: Pending] = [:]

    init(identifier: UInt16, nonce: [UInt8], continuation: AsyncThrowingStream<PingSample, Error>.Continuation) {
        self.identifier = identifier
        self.nonce = nonce
        self.continuation = continuation
    }

    var hasPending: Bool { lock.withLock { !pending.isEmpty } }

    func sent(_ n: Int, wire: UInt16, sentAt: Date, instant: ContinuousClock.Instant, deadline: ContinuousClock.Instant) {
        lock.withLock { pending[wire] = Pending(sequence: n, sentAt: sentAt, instant: instant, deadline: deadline) }
    }

    func handle(_ packet: ICMPPacket) {
        lock.withLock {
            switch packet.message {
            case let .echoReply(id, seq, payload):
                guard payload.count >= nonce.count, Array(payload.prefix(nonce.count)) == nonce,
                      let p = pending.removeValue(forKey: seq) else { return }
                _ = id
                let rtt = (packet.receivedAt - p.instant).seconds
                continuation.yield(PingSample(sequence: p.sequence, sentAt: p.sentAt,
                                              outcome: .reply(rtt: rtt, bytes: 8 + payload.count, ttl: packet.ttl, from: packet.from)))
            case let .destinationUnreachable(code, quoted?):
                guard quoted.identifier == identifier, let p = pending.removeValue(forKey: quoted.sequence) else { return }
                continuation.yield(PingSample(sequence: p.sequence, sentAt: p.sentAt,
                                              outcome: .unreachable(code: code, from: packet.from)))
            default:
                return
            }
        }
    }

    func expire(now: ContinuousClock.Instant) {
        lock.withLock {
            for (wire, p) in pending where p.deadline <= now {
                pending.removeValue(forKey: wire)
                continuation.yield(PingSample(sequence: p.sequence, sentAt: p.sentAt, outcome: .timeout))
            }
        }
    }
}

extension Duration {
    /// Seconds as a Double.
    var seconds: Double {
        let c = components
        return Double(c.seconds) + Double(c.attoseconds) / 1e18
    }
}
