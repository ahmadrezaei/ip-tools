// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import BGPGraph
import Foundation
import NetCore
import RIPEstat
import SharedUI
import Testing
@testable import BGPFeature

// MARK: Locator and math

@Suite struct MyNetworkLocatorTests {
    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var date = Date(timeIntervalSince1970: 1_000_000)
        func advance(_ seconds: TimeInterval) { lock.withLock { date.addTimeInterval(seconds) } }
        var now: Date { lock.withLock { date } }
    }

    @Test func locatesAndCachesPerGeneration() async {
        let api = BGPFakeAPI()
        let locator = MyNetworkLocator(api: api)
        let first = await locator.current(generation: 1)
        #expect(first?.ip == "91.107.240.242")
        #expect(first?.asn == 24940)
        #expect(first?.prefix == "91.107.128.0/17")
        _ = await locator.current(generation: 1)
        #expect(api.whatsMyIPCalls == 1)
        _ = await locator.current(generation: 2)
        #expect(api.whatsMyIPCalls == 2)
    }

    @Test func cacheExpiresAfterThirtyMinutes() async {
        let api = BGPFakeAPI()
        let clock = Clock()
        let locator = MyNetworkLocator(api: api, now: { clock.now })
        _ = await locator.current(generation: 0)
        clock.advance(29 * 60)
        _ = await locator.current(generation: 0)
        #expect(api.whatsMyIPCalls == 1)
        clock.advance(2 * 60)
        _ = await locator.current(generation: 0)
        #expect(api.whatsMyIPCalls == 2)
    }

    @Test func failuresAreNotCached() async {
        let api = BGPFakeAPI()
        api.myIP = nil
        let locator = MyNetworkLocator(api: api)
        #expect(await locator.current(generation: 0) == nil)
        api.myIP = "91.107.240.242"
        #expect(await locator.current(generation: 0)?.asn == 24940)
    }

    @Test func unannouncedAddressGivesNoASN() async {
        let api = BGPFakeAPI()
        api.myIP = "203.0.113.9"
        let mine = await MyNetworkLocator(api: api).current(generation: 0)
        #expect(mine?.ip == "203.0.113.9")
        #expect(mine?.asn == nil)
    }
}

@Suite struct PrefixMathTests {
    @Test(arguments: [
        ("8.8.8.0/24", "8.8.8.1"), ("10.1.2.3/30", "10.1.2.1"), ("8.8.8.8/24", "8.8.8.1"), ("1.2.3.4/31", "1.2.3.4"),
        ("1.2.3.4/32", "1.2.3.4"), ("2606:4700::/32", "2606:4700::1"), ("2001:db8::5/128", "2001:db8::5"),
    ])
    func probeAddress(_ prefix: String, _ expected: String) {
        #expect(PrefixMath.probeAddress(forPrefix: prefix)?.description == expected)
    }

    @Test func rejectsGarbage() {
        #expect(PrefixMath.probeAddress(forPrefix: "nonsense") == nil)
        #expect(PrefixMath.probeAddress(forPrefix: "1.2.3.0/40") == nil)
    }
}

// MARK: RouteMeasurer stop rules

@Suite struct RouteMeasurerTests {
    private func run(_ hops: [[ProbeResult]], target: String = "8.8.8.8", prefixTarget: Bool = false,
                     api: BGPFakeAPI = BGPFakeAPI()) async -> (hops: [ChainHop], reachedOrigin: Bool?, failed: Bool) {
        let measurer = RouteMeasurer(service: Probes.service(hops), api: api)
        var last: [ChainHop] = []
        var reached: Bool?
        var failed = false
        for await update in measurer.measure(resolvedTarget(target), origins: [15169], prefixTarget: prefixTarget) {
            switch update {
            case let .hops(list): last = list
            case let .finished(origin): reached = origin
            case .failed: failed = true
            }
        }
        return (last, reached, failed)
    }

    @Test func ruleA_echoReplyFromTarget() async {
        let result = await run(Probes.worked)
        #expect(result.reachedOrigin == true)
        #expect(result.hops.count == 11)
        #expect(result.hops.last?.reachedTarget == true)
        #expect(result.hops.last?.kind == .network(15169))
        #expect(result.hops[2].kind == .privateAddress)
        #expect(result.hops[3].kind == .network(13335))
        #expect(result.hops[9].kind == .silent)
    }

    @Test func ruleB_unreachableFromOriginIsDone() async {
        let result = await run(Probes.local + Probes.cloudflare + Probes.google + [Probes.unreachable("72.14.237.93")])
        #expect(result.reachedOrigin == true)
        #expect(result.hops.last?.ttl == 10)
    }

    @Test func ruleB_unreachableFromOtherNetworkIsPartial() async {
        let result = await run(Probes.local + Probes.cloudflare + [Probes.unreachable("141.101.67.57")])
        #expect(result.reachedOrigin == false)
        #expect(result.hops.last?.ttl == 8)
    }

    @Test func ruleC_prefixTargetStopsAtFirstOriginHop() async {
        let result = await run(Probes.worked, target: "8.8.8.1", prefixTarget: true)
        #expect(result.reachedOrigin == true)
        #expect(result.hops.last?.ttl == 8)
        #expect(result.hops.last?.kind == .network(15169))
    }

    @Test func ruleD_threeSilentHopsAfterOrigin() async {
        let script = Probes.local + Probes.cloudflare + [Probes.hop("108.170.255.223")] + [Probes.silent, Probes.silent, Probes.silent]
            + [Probes.hop("72.14.237.93"), Probes.reply("8.8.8.8")]
        let result = await run(script)
        #expect(result.reachedOrigin == true)
        #expect(result.hops.last?.ttl == 11)
        #expect(result.hops.last?.kind == .silent)
    }

    @Test func ruleE_fiveSilentHopsBeforeAnyOrigin() async {
        let script = Probes.local + Probes.cloudflare + Array(repeating: Probes.silent, count: 5) + [Probes.hop("108.170.255.223")]
        let result = await run(script)
        #expect(result.reachedOrigin == false)
        #expect(result.hops.last?.ttl == 12)
        #expect(result.hops.last?.kind == .silent)
    }

    @Test func fourSilentHopsDoNotStopTheTrace() async {
        let script = Probes.local + Probes.cloudflare + Array(repeating: Probes.silent, count: 4) + [Probes.hop("108.170.255.223"), Probes.reply("8.8.8.8")]
        let result = await run(script)
        #expect(result.hops.last?.reachedTarget == true)
    }

    @Test func ruleF_maxHopsReached() async {
        let script = Array(repeating: Probes.hop("104.28.0.0"), count: 35)
        let result = await run(script)
        #expect(result.hops.last?.ttl == 30)
        #expect(result.reachedOrigin == false)
    }

    @Test func failureIsReported() async {
        let measurer = RouteMeasurer(service: FailingTraceService(error: .networkUnreachable(family: .v6)), api: BGPFakeAPI())
        var failed = false
        for await update in measurer.measure(resolvedTarget("8.8.8.8"), origins: [15169], prefixTarget: false) {
            if case .failed = update { failed = true }
        }
        #expect(failed)
    }
}

// MARK: YourRouteModel through BGPMapModel

@Suite @MainActor struct YourRouteModelTests {
    private func load(_ model: BGPMapModel, _ target: String = "8.8.8.8") async {
        model.targetText = target
        model.map()
        _ = await waitUntil { model.phase == .loaded }
    }

    private func settled(_ model: BGPMapModel) async {
        _ = await waitUntil {
            switch model.route.phase {
            case .idle, .locating, .measuring: false
            default: true
            }
        }
    }

    @Test func yourRouteIsTheDefaultView() {
        let model = makeBGPModel(api: BGPFakeAPI(), service: nil)
        #expect(model.view == .yourRoute)
    }

    @Test func freshTracebuildsTheChain() async {
        let service = CountingTraceService(Probes.service(Probes.worked))
        let model = makeBGPModel(api: BGPFakeAPI(), service: service)
        await load(model)
        await settled(model)
        #expect(model.route.phase == .done)
        #expect(model.route.chain?.asnSequence == [24940, 13335, 15169])
        #expect(model.route.chain?.reachedTarget == true)
        #expect(model.route.myNetwork?.asn == 24940)
        #expect(service.count == 1)
        #expect(model.summary?.myASNRouteCount == 0)
    }

    @Test func exportAndAccessibilityDescribeTheChain() async {
        let model = makeBGPModel(api: BGPFakeAPI(), service: Probes.service(Probes.worked))
        await load(model)
        await settled(model)
        _ = await waitUntil { model.route.names[13335] != nil }
        let lines = model.route.exportText.split(separator: "\n").map(String.init)
        #expect(lines[0].hasPrefix("Your route to 8.8.8.8 (8.8.8.0/24, origin AS15169"))
        #expect(lines[1].hasPrefix("Measured by traceroute from this device, "))
        #expect(lines[1].hasSuffix(", 11 hops"))
        #expect(lines[2].hasPrefix("  You  AS24940"))
        #expect(lines[2].contains("hops 1–3"))
        #expect(lines[3].contains("   →   AS13335"))
        #expect(lines[4].contains("(reached 8.8.8.8)"))
        #expect(lines.last == "— IP Tools for iOS")
        #expect(model.exportText == model.route.exportText)
        let sentence = model.route.accessibilitySentence
        #expect(sentence.hasPrefix("Your route to 8.8.8.8, measured by traceroute: from your network, AS 24940"))
        #expect(sentence.contains("through AS 13335"))
        #expect(sentence.contains("to AS 15169"))
        #expect(sentence.hasSuffix("the destination. 11 hops."))
    }

    @Test func bgpChainIsUsedWhenMyASNIsInRIS() async {
        let api = BGPFakeAPI()
        api.myIP = "80.150.0.1"
        let service = CountingTraceService(Probes.service(Probes.worked))
        let model = makeBGPModel(api: api, service: service)
        await load(model)
        await settled(model)
        #expect(model.route.phase == .done)
        #expect(model.route.chain?.asnSequence == [3320, 15169])
        if case .bgp? = model.route.chain?.source {} else { Issue.record("expected a BGP chain") }
        #expect(service.count == 0)
        #expect(model.route.exportText.contains("Seen in BGP from your network"))
        #expect(model.route.accessibilitySentence.contains("seen in BGP"))
        #expect(model.route.accessibilitySentence.contains("directly to AS 15169"))
        #expect(model.summary?.myASNRouteCount == 2)
        // One tap measures for real and replaces the chain.
        model.route.measureAgain()
        await settled(model)
        #expect(service.count == 1)
        if case .traceroute? = model.route.chain?.source {} else { Issue.record("expected a measured chain") }
    }

    @Test func handedOverSnapshotWinsOverEverything() async {
        let api = BGPFakeAPI()
        api.myIP = "80.150.0.1"       // would also qualify for the BGP source
        let service = CountingTraceService(Probes.service(Probes.worked))
        let router = AppRouter(selectedTool: .bgp)
        let model = makeBGPModel(api: api, service: service, router: router)
        let snap = snapshot(of: "8.8.8.8", hops: [(1, "192.168.1.1", nil), (2, "104.28.0.0", 13335), (3, "8.8.8.8", 15169)],
                            finishedAt: Date().addingTimeInterval(-60))
        router.open(.bgp, target: "8.8.8.8", autostart: true, trace: snap)
        model.consumeRouterRequest()
        _ = await waitUntil { model.phase == .loaded }
        await settled(model)
        #expect(model.route.phase == .done)
        #expect(service.count == 0)
        if case let .traceroute(handedOver, _)? = model.route.chain?.source { #expect(handedOver) } else { Issue.record("expected a trace chain") }
        #expect(model.route.chain?.asnSequence == [3320, 13335, 15169])
    }

    @Test func snapshotExpiresAfterTenMinutes() async {
        let service = CountingTraceService(Probes.service(Probes.worked))
        let router = AppRouter(selectedTool: .bgp)
        let model = makeBGPModel(api: BGPFakeAPI(), service: service, router: router)
        let old = snapshot(of: "8.8.8.8", hops: [(1, "192.168.1.1", nil), (2, "8.8.8.8", 15169)], finishedAt: Date().addingTimeInterval(-11 * 60))
        router.open(.bgp, target: "8.8.8.8", autostart: true, trace: old)
        model.consumeRouterRequest()
        _ = await waitUntil { model.phase == .loaded }
        await settled(model)
        #expect(service.count == 1)
        if case let .traceroute(handedOver, _)? = model.route.chain?.source { #expect(!handedOver) } else { Issue.record("expected a trace chain") }
    }

    @Test func snapshotForAnotherAddressIsIgnored() async {
        let service = CountingTraceService(Probes.service(Probes.worked))
        let router = AppRouter(selectedTool: .bgp)
        let model = makeBGPModel(api: BGPFakeAPI(), service: service, router: router)
        let other = snapshot(of: "8.8.4.4", hops: [(1, "192.168.1.1", nil), (2, "8.8.4.4", 15169)], finishedAt: Date())
        router.open(.bgp, target: "8.8.8.8", autostart: true, trace: other)
        model.consumeRouterRequest()
        _ = await waitUntil { model.phase == .loaded }
        await settled(model)
        #expect(service.count == 1)
    }

    @Test func gapWhenLastNetworkIsNotInRIS() async {
        let script = Probes.local + Probes.cloudflare + Array(repeating: Probes.silent, count: 5)
        let model = makeBGPModel(api: BGPFakeAPI(), service: Probes.service(script))
        await load(model)
        await settled(model)
        #expect(model.route.phase == .partial("Traceroute couldn't see past hop 7"))
        #expect(model.route.chain?.completion == .gap)
        #expect(model.route.exportText.contains("   ?   unknown networks"), "\(model.route.exportText)")
        #expect(model.route.accessibilitySentence.contains("then unknown networks"))
    }

    @Test func stitchedWhenLastNetworkIsInRIS() async {
        let script = Probes.local + [Probes.hop("62.115.0.1")] + Array(repeating: Probes.silent, count: 5)
        let model = makeBGPModel(api: BGPFakeAPI(), service: Probes.service(script))
        await load(model)
        await settled(model)
        guard case let .partial(title) = model.route.phase else { Issue.record("expected partial, got \(model.route.phase)"); return }
        #expect(title.contains("Traceroute stopped in"))
        #expect(model.route.chain?.completion == .stitched)
        #expect(model.route.chain?.asnSequence == [24940, 1299, 15169])
        #expect(model.route.exportText.contains("(from BGP)"))
    }

    @Test func noPublicHopAnswered() async {
        let model = makeBGPModel(api: BGPFakeAPI(), service: Probes.service(Probes.local + Array(repeating: Probes.silent, count: 5)))
        await load(model)
        await settled(model)
        #expect(model.route.phase == .partial("No router on the way answered"))
        #expect(model.route.statusSubtitle == "Some networks block traceroute.")
    }

    @Test func stoppingKeepsTheKnownPart() async {
        let model = makeBGPModel(api: BGPFakeAPI(), service: Probes.service(Probes.worked, delay: .milliseconds(40)))
        await load(model)
        _ = await waitUntil { model.route.chain?.nodes.count ?? 0 >= 3 && model.route.isMeasuring }
        #expect(model.route.isMeasuring)
        model.route.stop()
        guard case let .stopped(title) = model.route.phase else { Issue.record("expected stopped"); return }
        #expect(title.hasPrefix("Stopped at hop"))
        #expect(model.route.chain != nil)
        try? await Task.sleep(for: .milliseconds(150))
        if case .stopped = model.route.phase {} else { Issue.record("a stopped route must stay stopped") }
    }

    @Test func backgroundStopsWithAReason() async {
        let model = makeBGPModel(api: BGPFakeAPI(), service: Probes.service(Probes.worked, delay: .milliseconds(40)))
        await load(model)
        _ = await waitUntil { model.route.isMeasuring }
        model.stopForBackground()
        #expect(model.route.phase == .stopped("Stopped: app moved to background"))
    }

    @Test func newMapCancelsTheMeasurement() async {
        let model = makeBGPModel(api: BGPFakeAPI(), service: Probes.service(Probes.worked, delay: .milliseconds(40)))
        await load(model)
        _ = await waitUntil { model.route.isMeasuring }
        model.targetText = "10.0.0.1"
        model.map()
        #expect(model.route.phase == .idle)
    }

    @Test func lookupsOffShowsTheStateAndTurnOnMeasures() async {
        let settings = makeSettings()
        settings.trace.lookUpASNs = false
        let service = CountingTraceService(Probes.service(Probes.worked))
        let model = makeBGPModel(api: BGPFakeAPI(), service: service, settings: settings)
        await load(model)
        await settled(model)
        #expect(model.route.phase == .lookupsOff)
        #expect(service.count == 0)
        model.route.turnOnLookups()
        #expect(settings.trace.lookUpASNs)
        await settled(model)
        #expect(model.route.phase == .done)
    }

    @Test func lookupsOffStillAllowsBGPChain() async {
        let settings = makeSettings()
        settings.trace.lookUpASNs = false
        let api = BGPFakeAPI()
        api.myIP = "80.150.0.1"
        let model = makeBGPModel(api: api, service: Probes.service(Probes.worked), settings: settings)
        await load(model)
        await settled(model)
        #expect(model.route.phase == .done)
        #expect(model.route.chain?.asnSequence == [3320, 15169])
    }

    @Test func unavailableWithoutTraceService() async {
        let model = makeBGPModel(api: BGPFakeAPI(), service: nil)
        await load(model)
        await settled(model)
        #expect(model.route.phase == .unavailable)
    }

    @Test func traceFailureIsShown() async {
        let model = makeBGPModel(api: BGPFakeAPI(), service: FailingTraceService(error: .networkUnreachable(family: .v6)))
        await load(model)
        await settled(model)
        guard case let .failed(message) = model.route.phase else { Issue.record("expected failed, got \(model.route.phase)"); return }
        #expect(message.contains("IPv6"))
    }

    @Test func unknownNetworkIsNotAnError() async {
        let api = BGPFakeAPI()
        api.myIP = nil
        let model = makeBGPModel(api: api, service: Probes.service(Probes.worked))
        await load(model)
        await settled(model)
        #expect(model.route.phase == .done)
        #expect(model.route.myNetwork == nil)
        #expect(model.route.chain?.nodes.first?.asn == nil)
    }

    @Test func ownNetworkIsASingleNode() async {
        let api = BGPFakeAPI()
        api.infoByIP["91.107.240.242"] = NetworkInfo(prefix: "8.8.8.0/24", originASNs: [15169])
        let model = makeBGPModel(api: api, service: nil)
        await load(model)
        await settled(model)
        #expect(model.route.chain?.nodes.map(\.role) == [.youAndDestination])
        #expect(model.route.statusTitle.contains("is on your own network"))
    }

    @Test func privateTargetsNeverStartARoute() {
        let model = makeBGPModel(api: BGPFakeAPI(), service: Probes.service(Probes.worked))
        model.targetText = "10.1.2.3"
        model.map()
        #expect(model.route.phase == .idle)
    }

    @Test func prefixInputProbesTheFirstUsableAddress() async {
        let service = RecordingTraceService(Probes.service(Probes.worked))
        let model = makeBGPModel(api: BGPFakeAPI(), service: service)
        await load(model, "8.8.8.0/24")
        await settled(model)
        #expect(service.targets == ["8.8.8.1"])
        // Rule c: stops as soon as Google's network answers.
        #expect(model.route.phase == .done)
        #expect(model.route.chain?.nodes.last?.ttls?.upperBound == 8)
    }
}

final class RecordingTraceService: TraceService, @unchecked Sendable {
    private let lock = NSLock()
    private var _targets: [String] = []
    private let inner: any TraceService
    init(_ inner: any TraceService) { self.inner = inner }
    var targets: [String] { lock.withLock { _targets } }
    func trace(_ target: ResolvedTarget, options: TraceOptions) -> AsyncThrowingStream<TraceEvent, Error> {
        lock.withLock { _targets.append(target.address.description) }
        return inner.trace(target, options: options)
    }
}
