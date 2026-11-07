// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation

/// ICMP echo traceroute implementation of `TraceService`.
///
/// Behaviour: for each TTL, `probesPerHop` echo requests go out about 10 ms apart. `.probe` events are
/// emitted as each probe's result becomes known (so indices within a hop may arrive out of order and a
/// silent probe is reported as `.timeout` once its timeout elapses). `.hopFinished(ttl:)` follows when
/// every probe of that hop has a result. The trace ends with `.finished` when an Echo Reply arrives
/// (`reachedDestination`), when a Destination Unreachable arrives (`unreachable`), or after `maxHops`.
/// No DNS or ASN enrichment happens here. Cancelling the consuming task stops promptly.
public struct Tracer: TraceService {
    public init() {}

    public func trace(_ target: ResolvedTarget, options: TraceOptions) -> AsyncThrowingStream<TraceEvent, Error> {
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

    private static func run(_ target: ResolvedTarget, _ options: TraceOptions,
                            _ continuation: AsyncThrowingStream<TraceEvent, Error>.Continuation) async throws {
        let socket = try ICMPSocket(family: target.address.family)
        let state = TraceState(identifier: UInt16.random(in: 1...UInt16.max),
                               nonce: (0..<8).map { _ in UInt8.random(in: 0...255) },
                               continuation: continuation)
        let clock = ContinuousClock()
        let timeout = Duration.seconds(max(options.timeout, 0.05))
        let probes = max(options.probesPerHop, 1)
        let maxHops = min(max(options.maxHops, 1), 255)

        try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await packet in socket.packets { state.handle(packet) }
                }
                group.addTask {
                    while !Task.isCancelled {
                        try? await clock.sleep(for: .milliseconds(10))
                        state.expire(now: clock.now)
                    }
                }
                group.addTask {
                    var wireSeq: UInt16 = 0
                    for ttl in 1...maxHops {
                        for index in 0..<probes {
                            try Task.checkCancellation()
                            wireSeq &+= 1
                            let payload = state.nonce
                            let packet = ICMPCodec.echoRequest(family: target.address.family, identifier: state.identifier,
                                                               sequence: wireSeq, payload: payload)
                            state.prepare(wire: wireSeq, ttl: ttl, index: index)
                            let instant = try socket.send(packet, to: target.address, hopLimit: ttl)
                            state.armed(wire: wireSeq, instant: instant, deadline: instant + timeout)
                            if index < probes - 1 { try await clock.sleep(for: .milliseconds(10)) }
                        }
                        while state.hasPending {
                            try await clock.sleep(for: .milliseconds(10))
                        }
                        if let completion = state.finishHop(ttl: ttl) {
                            continuation.yield(.finished(completion))
                            return
                        }
                    }
                    continuation.yield(.finished(.maxHopsExceeded))
                }
                defer { socket.close(); group.cancelAll() }
                _ = try await group.next()
            }
        } onCancel: {
            socket.close()
        }
    }
}

private final class TraceState: @unchecked Sendable {
    struct Pending {
        let ttl: Int
        let index: Int
        var instant: ContinuousClock.Instant?
        var deadline: ContinuousClock.Instant?
    }

    let identifier: UInt16
    let nonce: [UInt8]
    private let continuation: AsyncThrowingStream<TraceEvent, Error>.Continuation
    private let lock = NSLock()
    private var pending: [UInt16: Pending] = [:]
    private var reached = false
    private var unreachableCode: UInt8?

    init(identifier: UInt16, nonce: [UInt8], continuation: AsyncThrowingStream<TraceEvent, Error>.Continuation) {
        self.identifier = identifier
        self.nonce = nonce
        self.continuation = continuation
    }

    var hasPending: Bool { lock.withLock { !pending.isEmpty } }

    func prepare(wire: UInt16, ttl: Int, index: Int) {
        lock.withLock { pending[wire] = Pending(ttl: ttl, index: index) }
    }

    func armed(wire: UInt16, instant: ContinuousClock.Instant, deadline: ContinuousClock.Instant) {
        lock.withLock {
            // The reply may already have been processed (loopback), in which case the entry is gone.
            pending[wire]?.instant = instant
            pending[wire]?.deadline = deadline
        }
    }

    /// Returns the completion if the trace ends at this hop.
    func finishHop(ttl: Int) -> TraceCompletion? {
        lock.withLock {
            continuation.yield(.hopFinished(ttl: ttl))
            if reached { return .reachedDestination(hops: ttl) }
            if let code = unreachableCode { return .unreachable(atHop: ttl, code: code) }
            return nil
        }
    }

    func handle(_ packet: ICMPPacket) {
        lock.withLock {
            let wire: UInt16
            switch packet.message {
            case let .echoReply(id, seq, payload):
                guard payload.starts(with: nonce) else { return }
                _ = id
                wire = seq
            case let .timeExceeded(quoted?), let .destinationUnreachable(_, quoted?):
                guard quoted.identifier == identifier else { return }
                wire = quoted.sequence
            default:
                return
            }
            guard let p = pending[wire], let instant = p.instant ?? Optional(packet.receivedAt) else { return }
            pending.removeValue(forKey: wire)
            let rtt = max((packet.receivedAt - instant).seconds, 0)
            let result: ProbeResult
            switch packet.message {
            case .echoReply:
                reached = true
                result = .echoReply(from: packet.from, rtt: rtt)
            case .timeExceeded:
                result = .timeExceeded(from: packet.from, rtt: rtt)
            case let .destinationUnreachable(code, _):
                if unreachableCode == nil { unreachableCode = code }
                result = .unreachable(from: packet.from, rtt: rtt, code: code)
            default:
                return
            }
            continuation.yield(.probe(ttl: p.ttl, index: p.index, result: result))
        }
    }

    func expire(now: ContinuousClock.Instant) {
        lock.withLock {
            for (wire, p) in pending {
                guard let deadline = p.deadline, deadline <= now else { continue }
                pending.removeValue(forKey: wire)
                continuation.yield(.probe(ttl: p.ttl, index: p.index, result: .timeout))
            }
        }
    }
}
