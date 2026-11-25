// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore
import RIPEstat
import Testing
@testable import WhoisFeature

@Suite struct MyIPLocatorTests {
    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var date = Date(timeIntervalSince1970: 1_000_000)
        var now: Date { lock.withLock { date } }
        func advance(_ seconds: TimeInterval) { lock.withLock { date.addTimeInterval(seconds) } }
    }

    private func locator(_ api: WhoisFakeAPI, clock: Clock = Clock()) -> MyIPLocator {
        MyIPLocator(api: api, reverseName: { _ in "rev.example" }, now: { clock.now })
    }

    private func last(_ stream: AsyncStream<MyIPSnapshot>) async -> (snapshots: [MyIPSnapshot], last: MyIPSnapshot?) {
        var all: [MyIPSnapshot] = []
        for await snapshot in stream { all.append(snapshot) }
        return (all, all.last)
    }

    private func run(_ locator: MyIPLocator, generation: Int = 1, v6: Bool = true, force: Bool = false) async -> MyIPSnapshot? {
        await last(await locator.snapshot(generation: generation, supportsV6: v6, viaVPN: false, force: force)).last
    }

    @Test func bothFamiliesAreFoundAndProgressiveSnapshotsStartChecking() async {
        let api = WhoisFakeAPI()
        api.publicIP = [.v4: .success("193.0.6.139"), .v6: .success("2001:67c:2e8:22::c100:696")]
        let result = await last(await locator(api).snapshot(generation: 1, supportsV6: true, viaVPN: true, force: false))
        #expect(result.snapshots.first?.v4 == .checking)
        #expect(result.snapshots.first?.v6 == .checking)
        #expect(result.last?.v4 == .found(ip("193.0.6.139"), reverseName: "rev.example"))
        #expect(result.last?.v6 == .found(ip("2001:67c:2e8:22::c100:696"), reverseName: "rev.example"))
        #expect(result.last?.viaVPN == true)
        #expect(Set(api.calls) == ["my-ip:v4", "my-ip:v6"])
    }

    @Test func noIPv6SupportSkipsTheRequest() async {
        let api = WhoisFakeAPI()
        api.publicIP = [.v4: .success("193.0.6.139")]
        let snapshot = await run(locator(api), v6: false)
        #expect(snapshot?.v6 == .unavailable(.noRoute))
        #expect(api.calls == ["my-ip:v4"])
    }

    @Test func noRouteMapsPerFamily() async {
        let api = WhoisFakeAPI()
        api.publicIP = [.v4: .failure(PublicIPError.noRoute(.v4)), .v6: .success("2001:67c:2e8:22::c100:696")]
        let v6Only = await run(locator(api))
        #expect(v6Only?.v4 == .unavailable(.ipv6OnlyNetwork))
        #expect(v6Only?.address(.v6) != nil)

        let none = WhoisFakeAPI()
        none.publicIP = [.v4: .failure(PublicIPError.noRoute(.v4)), .v6: .failure(PublicIPError.noRoute(.v6))]
        let neither = await run(locator(none))
        #expect(neither?.v4 == .unavailable(.noRoute))
        #expect(neither?.v6 == .unavailable(.noRoute))
        #expect(none.calls("my-ip:plain").isEmpty)
    }

    @Test func familyMismatchOnIPv6IsReported() async {
        let api = WhoisFakeAPI()
        api.publicIP = [.v4: .success("193.0.6.139"), .v6: .success("193.0.6.139")]
        let snapshot = await run(locator(api))
        #expect(snapshot?.v6 == .unavailable(.mismatch))
        #expect(snapshot?.address(.v4) != nil)
    }

    @Test func oneFailureLeavesTheOtherRow() async {
        let api = WhoisFakeAPI()
        api.publicIP = [.v4: .success("193.0.6.139"), .v6: .failure(PublicIPError.timeout(.v6))]
        api.plainPublicIP = nil
        let snapshot = await run(locator(api))
        guard case .failed? = snapshot?.v6 else { Issue.record("expected failed"); return }
        #expect(snapshot?.address(.v4) != nil)
        #expect(api.calls("my-ip:plain").isEmpty)
    }

    @Test func bothFailingFallsBackToThePlainRequest() async {
        let api = WhoisFakeAPI()
        api.publicIP = [.v4: .failure(PublicIPError.tls), .v6: .failure(PublicIPError.tls)]
        api.plainPublicIP = "2001:67c:2e8:22::c100:696"
        let snapshot = await run(locator(api))
        #expect(api.calls("my-ip:plain") == ["my-ip:plain"])
        #expect(snapshot?.address(.v6) == ip("2001:67c:2e8:22::c100:696"))
        guard case .failed? = snapshot?.v4 else { Issue.record("v4 should stay failed"); return }
    }

    @Test func fallbackAlsoRunsWhenOnlyOneFamilyWasAttempted() async {
        let api = WhoisFakeAPI()
        api.publicIP = [.v4: .failure(PublicIPError.badResponse(status: 503))]
        api.plainPublicIP = "193.0.6.139"
        let snapshot = await run(locator(api), v6: false)
        #expect(snapshot?.address(.v4) == ip("193.0.6.139"))
    }

    @Test func bothFailingEverywhereLeavesBothFailed() async {
        let api = WhoisFakeAPI()
        api.publicIP = [.v4: .failure(RIPEstatError.rateLimited), .v6: .failure(RIPEstatError.rateLimited)]
        let snapshot = await run(locator(api))
        #expect(snapshot?.bothFailed == true)
        if case let .failed(message)? = snapshot?.v4 { #expect(message.contains("busy")) }
    }

    @Test func cacheServesTheSameGenerationAndForceBypassesIt() async {
        let api = WhoisFakeAPI()
        api.publicIP = [.v4: .success("193.0.6.139"), .v6: .success("2001:67c:2e8:22::c100:696")]
        let locator = locator(api)
        _ = await run(locator)
        #expect(api.calls.count == 2)
        _ = await run(locator)
        #expect(api.calls.count == 2)
        _ = await run(locator, force: true)
        #expect(api.calls.count == 4)
        _ = await run(locator, generation: 2)
        #expect(api.calls.count == 6)
    }

    @Test func cacheExpiresAfterThirtyMinutes() async {
        let api = WhoisFakeAPI()
        api.publicIP = [.v4: .success("193.0.6.139"), .v6: .success("2001:67c:2e8:22::c100:696")]
        let clock = Clock()
        let locator = locator(api, clock: clock)
        _ = await run(locator)
        clock.advance(29 * 60)
        _ = await run(locator)
        #expect(api.calls.count == 2)
        clock.advance(2 * 60)
        _ = await run(locator)
        #expect(api.calls.count == 4)
    }

    @Test func failuresAreNotCached() async {
        let api = WhoisFakeAPI()
        api.publicIP = [.v4: .success("193.0.6.139"), .v6: .failure(PublicIPError.timeout(.v6))]
        let locator = locator(api)
        _ = await run(locator)
        _ = await run(locator)
        #expect(api.calls("my-ip:v4").count == 2)
    }
}
