// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import Testing
@testable import NetCore

private let networkTestsEnabled = ProcessInfo.processInfo.environment["IPTOOLS_NET_TESTS"] == "1"

private func collect(_ stream: AsyncThrowingStream<PingSample, Error>) async throws -> [PingSample] {
    var out: [PingSample] = []
    for try await s in stream { out.append(s) }
    return out.sorted { $0.sequence < $1.sequence }
}

private func target(_ s: String) -> ResolvedTarget {
    let ip = IPAddress(s)!
    return ResolvedTarget(input: s, address: ip, hostname: nil, allAddresses: [ip])
}

@Suite struct LoopbackTests {
    @Test func pingLoopbackV4() async throws {
        var options = PingOptions()
        options.count = 3
        options.interval = 0.1
        options.timeout = 1
        let samples = try await collect(Pinger().ping(target("127.0.0.1"), options: options))
        #expect(samples.map(\.sequence) == [0, 1, 2])
        for s in samples {
            guard case let .reply(rtt, bytes, ttl, from) = s.outcome else { Issue.record("not a reply: \(s)"); continue }
            #expect(rtt >= 0 && rtt < 1)
            #expect(bytes == 64)
            #expect(ttl != nil)
            #expect(from.description == "127.0.0.1")
        }
        let stats = PingStatistics(samples: samples)
        #expect(stats.received == 3 && stats.lossFraction == 0)
    }

    @Test func pingLoopbackV6() async throws {
        var options = PingOptions()
        options.count = 3
        options.interval = 0.1
        options.timeout = 1
        let samples = try await collect(Pinger().ping(target("::1"), options: options))
        #expect(samples.count == 3)
        for s in samples {
            guard case let .reply(_, bytes, _, from) = s.outcome else { Issue.record("not a reply: \(s)"); continue }
            #expect(bytes == 64)
            #expect(from.description == "::1")
        }
    }

    @Test func cancellationStopsPromptly() async throws {
        var options = PingOptions()
        options.count = nil
        options.interval = 0.2
        let task = Task {
            var n = 0
            for try await _ in Pinger().ping(target("127.0.0.1"), options: options) { n += 1 }
            return n
        }
        try await Task.sleep(for: .milliseconds(500))
        let start = ContinuousClock.now
        task.cancel()
        let n = try await task.value
        #expect(ContinuousClock.now - start < .milliseconds(500))
        #expect(n >= 1)
    }

    @Test func traceLoopbackReachesInOneHop() async throws {
        var options = TraceOptions()
        options.timeout = 1
        var events: [TraceEvent] = []
        for try await e in Tracer().trace(target("127.0.0.1"), options: options) { events.append(e) }
        #expect(events.last == .finished(.reachedDestination(hops: 1)))
        #expect(events.contains(.hopFinished(ttl: 1)))
    }
}

@Suite(.enabled(if: networkTestsEnabled)) struct InternetTests {
    @Test func pingCloudflare() async throws {
        var options = PingOptions()
        options.count = 4
        options.interval = 0.3
        let samples = try await collect(Pinger().ping(target("1.1.1.1"), options: options))
        print("PING 1.1.1.1:", samples.map(\.outcome))
        #expect(samples.contains { if case .reply = $0.outcome { true } else { false } })
    }

    @Test(arguments: ["1.1.1.1", "8.8.8.8"]) func traceIPv4(host: String) async throws {
        var options = TraceOptions()
        options.timeout = 2
        var hops: [Int: [Int: ProbeResult]] = [:]
        var completion: TraceCompletion?
        for try await e in Tracer().trace(target(host), options: options) {
            switch e {
            case let .probe(ttl, index, result): hops[ttl, default: [:]][index] = result
            case .hopFinished: break
            case let .finished(c): completion = c
            }
        }
        var lines = ["TRACE \(host) -> \(String(describing: completion))"]
        for ttl in hops.keys.sorted() {
            let cols = hops[ttl]!.keys.sorted().map { i -> String in
                switch hops[ttl]![i]! {
                case let .timeExceeded(from, rtt): return "\(from) \(String(format: "%.1f", rtt * 1000))ms [TE]"
                case let .echoReply(from, rtt): return "\(from) \(String(format: "%.1f", rtt * 1000))ms [ECHO]"
                case let .unreachable(from, rtt, code): return "\(from) \(String(format: "%.1f", rtt * 1000))ms [UNREACH \(code)]"
                case .timeout: return "*"
                }
            }
            lines.append(String(format: "%2d  ", ttl) + cols.joined(separator: "  "))
        }
        print(lines.joined(separator: "\n"))
        let teCount = hops.values.flatMap(\.values).filter { if case .timeExceeded = $0 { true } else { false } }.count
        #expect(teCount >= 1, "expected at least one Time Exceeded from an intermediate router")
        if let c = completion, case .reachedDestination = c {} else { Issue.record("did not reach destination: \(String(describing: completion))") }
    }

    @Test func traceIPv6() async throws {
        let ip = IPAddress("2606:4700:4700::1111")!
        var options = TraceOptions()
        options.timeout = 2
        var lines: [String] = []
        var te = 0
        do {
            for try await e in Tracer().trace(ResolvedTarget(input: "v6", address: ip, hostname: nil, allAddresses: [ip]), options: options) {
                lines.append("\(e)")
                if case let .probe(_, _, r) = e, case .timeExceeded = r { te += 1 }
            }
            print("TRACE6:\n" + lines.joined(separator: "\n"))
        } catch {
            print("TRACE6 unavailable: \(error)")
        }
    }
}

@Suite struct ReverseLookupTests {
    @Test(.enabled(if: networkTestsEnabled)) func googleDNSHasName() async {
        let result = await Resolver.reverseLookup(for: IPAddress("8.8.8.8")!, timeout: .seconds(5))
        #expect(result == .name("dns.google"))
    }

    @Test(.enabled(if: networkTestsEnabled)) func loopbackIsNotATimeout() async {
        let result = await Resolver.reverseLookup(for: IPAddress("127.0.0.1")!, timeout: .seconds(5))
        #expect(result != .timedOut)
    }
}
