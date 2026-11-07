// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import Testing
import NetCore
import RIPEstat
import SharedUI
@testable import TraceFeature

@Suite @MainActor struct TraceModelTests {
    let hop1 = IPAddress("192.168.1.1")!
    let hop2 = IPAddress("10.20.0.1")!
    let hop3 = IPAddress("141.101.65.1")!
    let dest = IPAddress("1.1.1.1")!

    private var script: [[ProbeResult]] {
        [
            [.timeExceeded(from: hop1, rtt: 0.002), .timeExceeded(from: hop1, rtt: 0.002), .timeExceeded(from: hop1, rtt: 0.003)],
            [.timeExceeded(from: hop2, rtt: 0.009), .timeout, .timeExceeded(from: hop2, rtt: 0.010)],
            [.timeExceeded(from: hop3, rtt: 0.021), .timeExceeded(from: hop3, rtt: 0.020), .timeExceeded(from: hop3, rtt: 0.022)],
            [.echoReply(from: dest, rtt: 0.024), .echoReply(from: dest, rtt: 0.023), .echoReply(from: dest, rtt: 0.025)],
        ]
    }

    private func makeModel(api: FakeRIPEstat = FakeRIPEstat(), router: AppRouter = AppRouter(),
                           configure: (SettingsStore) -> Void = { _ in }) -> (TraceModel, RecentsStore, SettingsStore) {
        let settings = makeSettings()
        configure(settings)
        let recents = makeRecents()
        let model = TraceModel(
            service: MockTraceService(hops: script, delay: .milliseconds(1)),
            asnLookup: ASNLookup(api: api), settings: settings, recents: recents, router: router,
            reverseDNS: { address in address == IPAddress("192.168.1.1") ? .name("router.lan") : .noName })
        return (model, recents, settings)
    }

    private func cloudflareAPI() -> FakeRIPEstat {
        let api = FakeRIPEstat()
        api.infoByIP["141.101.65.1"] = NetworkInfo(prefix: "141.101.64.0/18", originASNs: [13335])
        api.names[13335] = "CLOUDFLARENET - Cloudflare, Inc."
        return api
    }

    @Test func tracesToDestinationAndRecordsRecent() async {
        let (model, recents, _) = makeModel()
        model.targetText = "1.1.1.1"
        model.start()
        #expect(await waitUntil { if case .finished = model.phase { true } else { false } })
        #expect(model.phase == .finished(.reachedDestination(hops: 4)))
        #expect(model.hops.map(\.ttl) == [1, 2, 3, 4])
        #expect(model.hops[3].isDestination)
        #expect(!model.hops[2].isDestination)
        #expect(model.hops[1].probes.count == 3)
        #expect(model.hops[1].rtts.count == 2)
        #expect(model.hops[1].addresses == [hop2])
        #expect(recents.items.map(\.display) == ["1.1.1.1"])
        #expect(recents.items.first?.lastTool == .traceroute)
    }

    @Test func enrichesHostnamesAndASNsAsynchronously() async {
        let api = cloudflareAPI()
        let (model, _, _) = makeModel(api: api)
        model.targetText = "1.1.1.1"
        model.start()
        #expect(await waitUntil { model.hops.first?.hostname == "router.lan" })
        #expect(await waitUntil { model.hops.count > 2 && model.hops[2].asn?.name != nil })
        #expect(model.hops[2].asn?.asn == 13335)
        #expect(model.hops[0].asn == nil)               // private: never sent to RIPEstat
        #expect(model.hops[1].asn == nil)
        #expect(api.networkInfoCallCount == 2)          // hop 3 and the destination; private hops are skipped
        #expect(api.asNamesCallCount >= 1)
    }

    @Test func asnLookupCanBeDisabled() async {
        let api = cloudflareAPI()
        let (model, _, _) = makeModel(api: api) { $0.trace.lookUpASNs = false }
        model.targetText = "1.1.1.1"
        model.start()
        #expect(await waitUntil { if case .finished = model.phase { true } else { false } })
        try? await Task.sleep(for: .milliseconds(100))
        #expect(api.networkInfoCallCount == 0)
        #expect(api.asNamesCallCount == 0)
        #expect(model.hops.allSatisfy { $0.asn == nil })
    }

    @Test func hostnameResolutionCanBeDisabled() async {
        let (model, _, _) = makeModel { $0.trace.resolveHostnames = false; $0.trace.lookUpASNs = false }
        model.targetText = "1.1.1.1"
        model.start()
        #expect(await waitUntil { if case .finished = model.phase { true } else { false } })
        try? await Task.sleep(for: .milliseconds(50))
        #expect(model.hops[0].hostname == nil)
    }

    @Test func failedASNLookupLeavesBadgeBlank() async {
        let api = FakeRIPEstat()      // every call throws
        let (model, _, _) = makeModel(api: api)
        model.targetText = "1.1.1.1"
        model.start()
        #expect(await waitUntil { if case .finished = model.phase { true } else { false } })
        try? await Task.sleep(for: .milliseconds(100))
        #expect(model.hops.allSatisfy { $0.asn == nil })
        #expect(model.error == nil)
    }

    @Test func invalidTargetFails() {
        let (model, recents, _) = makeModel()
        model.targetText = "bad host!"
        model.start()
        if case .failed = model.phase {} else { Issue.record("expected failed") }
        #expect(recents.items.isEmpty)
        #expect(model.hops.isEmpty)
    }

    @Test func stopKeepsHopsFound() async {
        let settings = makeSettings()
        let model = TraceModel(
            service: MockTraceService(hops: script, delay: .milliseconds(40)),
            asnLookup: ASNLookup(api: FakeRIPEstat()), settings: settings, recents: makeRecents(), router: AppRouter(),
            reverseDNS: { _ in .noName })
        model.targetText = "1.1.1.1"
        model.start()
        #expect(await waitUntil { model.hops.count >= 2 })
        model.stop()
        #expect(model.phase == .stopped(nil))
        let count = model.hops.count
        try? await Task.sleep(for: .milliseconds(150))
        #expect(model.hops.count == count)
        #expect(count < 4)
    }

    @Test func routerRequestAutostarts() async {
        let router = AppRouter()
        let (model, _, _) = makeModel(router: router)
        router.open(.traceroute, target: "1.1.1.1", autostart: true)
        model.consumePendingRequest()
        #expect(model.targetText == "1.1.1.1")
        #expect(await waitUntil { if case .finished = model.phase { true } else { false } })
    }

    @Test func hopCrossLinks() {
        let router = AppRouter()
        let (model, _, _) = makeModel(router: router)
        model.mapHop(hop1)                                   // private: ignored
        #expect(router.selectedTool == .ping)
        model.mapHop(hop3)
        #expect(router.selectedTool == .bgp)
        #expect(router.takeRequest(for: .bgp) == ToolRequest(target: "141.101.65.1", autostart: true))
        model.pingHop(hop3)
        #expect(router.selectedTool == .ping)
        #expect(router.takeRequest(for: .ping) == ToolRequest(target: "141.101.65.1", autostart: true))
    }

    // MARK: Export & ASNLookup helpers

    @Test func exportMatchesSpecFormat() {
        let router = IPAddress("192.168.1.1")!, second = IPAddress("96.120.24.29")!, google = IPAddress("8.8.8.8")!
        let hops = [
            TraceHop(ttl: 1, probes: [.timeExceeded(from: router, rtt: 0.0018), .timeExceeded(from: router, rtt: 0.0020), .timeExceeded(from: router, rtt: 0.0017)],
                     addresses: [router], hostname: "router.lan"),
            TraceHop(ttl: 2, probes: [.timeExceeded(from: second, rtt: 0.0094), .timeout, .timeExceeded(from: second, rtt: 0.0102)],
                     addresses: [second], asn: HopASN(asn: 7922, name: "Comcast", prefix: nil)),
            TraceHop(ttl: 3, probes: [.timeout, .timeout, .timeout]),
            TraceHop(ttl: 10, probes: [.echoReply(from: google, rtt: 0.0129), .echoReply(from: google, rtt: 0.0126), .echoReply(from: google, rtt: 0.0131)],
                     addresses: [google], hostname: "dns.google", asn: HopASN(asn: 15169, name: "Google", prefix: nil), isDestination: true),
        ]
        var options = TraceOptions(); options.maxHops = 30; options.probesPerHop = 3
        let text = TraceExport.text(target: resolvedTarget("8.8.8.8"), options: options, hops: hops,
                                    date: utc("2026-11-07T12:34:00Z"))
        #expect(text == """
            traceroute to 8.8.8.8 (8.8.8.8), 30 hops max, 3 probes
             1  router.lan (192.168.1.1)  1.8 ms  2.0 ms  1.7 ms
             2  96.120.24.29 [AS7922]  9.4 ms  *  10.2 ms
             3  * * *
            10  dns.google (8.8.8.8) [AS15169]  12.9 ms  12.6 ms  13.1 ms
            — IP Tools for iOS, 2026-11-07 12:34 UTC
            """)
    }

    @Test func exportMarksEcmpAndUnreachable() {
        let a = IPAddress("203.0.113.1")!, b = IPAddress("203.0.113.2")!
        let ecmp = TraceHop(ttl: 5, probes: [.timeExceeded(from: a, rtt: 0.01), .timeExceeded(from: b, rtt: 0.011)], addresses: [a, b])
        #expect(TraceExport.line(for: ecmp, probes: 2) == " 5  203.0.113.1 +1 other  10.0 ms  11.0 ms")
        let blocked = TraceHop(ttl: 9, probes: [.unreachable(from: a, rtt: 0.01, code: 1)], addresses: [a])
        #expect(TraceExport.line(for: blocked, probes: 1) == " 9  203.0.113.1  10.0 ms  !H")
    }

    @Test func autostartRequestWhileRunningRestartsCleanly() async {
        let router = AppRouter()
        let (model, _, _) = makeModel(router: router)
        model.targetText = "1.1.1.1"
        model.start()
        #expect(await waitUntil { model.isBusy })
        router.open(.traceroute, target: "1.1.1.1", autostart: true)
        model.consumePendingRequest()
        #expect(await waitUntil { if case .finished = model.phase { true } else { false } })
        try? await Task.sleep(for: .milliseconds(150))
        #expect(model.phase == .finished(.reachedDestination(hops: 4)))
    }

    @Test func timedOutReverseLookupIsNotCachedAndRetries() async {
        let calls = CallCounter()
        let settings = makeSettings()
        settings.trace.lookUpASNs = false
        let model = TraceModel(
            service: MockTraceService(hops: script, delay: .milliseconds(1)),
            asnLookup: ASNLookup(api: FakeRIPEstat()), settings: settings, recents: makeRecents(), router: AppRouter(),
            reverseDNS: { address in
                guard address == IPAddress("192.168.1.1") else { return .noName }
                return calls.next() == 1 ? .timedOut : .name("router.lan")
            })
        model.targetText = "1.1.1.1"
        model.start()
        #expect(await waitUntil { if case .finished = model.phase { true } else { false } })
        #expect(model.hops[0].hostname == nil)
        model.start()
        #expect(await waitUntil { model.hops.first?.hostname == "router.lan" })
    }

    @Test func asnLookupNeverReusesCoveringPrefix() async {
        let api = FakeRIPEstat()
        api.infoByIP["8.0.0.1"] = NetworkInfo(prefix: "8.0.0.0/12", originASNs: [3356])
        api.infoByIP["8.8.8.8"] = NetworkInfo(prefix: "8.8.8.0/24", originASNs: [15169])
        let lookup = ASNLookup(api: api)
        let first = await lookup.lookup(IPAddress("8.0.0.1")!)
        let second = await lookup.lookup(IPAddress("8.8.8.8")!)
        let again = await lookup.lookup(IPAddress("8.8.8.8")!)
        #expect(first?.asn == 3356)
        #expect(second?.asn == 15169)
        #expect(again?.asn == 15169)
        #expect(api.networkInfoCallCount == 2)   // per IP, cached on repeat
    }
}
