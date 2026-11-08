// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import BGPGraph
import Foundation
import NetCore
import RIPEstat
import SharedUI
import Testing
@testable import BGPFeature

@Suite @MainActor struct BGPFixTests {
    private func load(_ model: BGPMapModel, _ target: String = "8.8.8.8") async {
        model.targetText = target
        model.map()
        _ = await bgpWait { model.phase == .loaded }
    }

    private func settled(_ model: BGPMapModel) async {
        _ = await bgpWait {
            switch model.route.phase {
            case .idle, .locating, .measuring: false
            default: true
            }
        }
    }

    // MARK: Locate timeout

    @Test func slowWhatsMyIPDoesNotHoldTheGraph() async {
        let api = BGPFakeAPI()
        api.whatsMyIPDelay = .seconds(3)
        let model = makeBGPModel(api: api, service: Probes.service(Probes.worked))
        let start = ContinuousClock.now
        await load(model)
        let elapsed = ContinuousClock.now - start
        #expect(model.phase == .loaded)
        #expect(elapsed < .seconds(2.5), "graph appeared after \(elapsed)")
        #expect(model.myNetwork == nil)
        model.cancel()
    }

    // MARK: Names

    private func chain(_ asns: [UInt32]) -> ASChain {
        var nodes = asns.dropLast().enumerated().map { index, asn in
            ASChain.Node(asn: asn, role: index == 0 ? .you : .transit, provenance: .measured)
        }
        nodes.append(ASChain.Node(asn: asns.last, role: .destination, provenance: .measured))
        return ASChain(nodes: nodes, source: .traceroute(handedOver: false, measuredAt: Date()), completion: .complete, reachedTarget: true)
    }

    private func context() -> RouteContext {
        RouteContext(label: "8.8.8.8", address: IPAddress("8.8.8.8"), hostname: nil, prefix: "8.8.8.0/24", origins: [15169],
                     paths: [], collectorLocations: [:], snapshot: nil)
    }

    @Test func namesRequestedWhileFetchingAreNotLost() async {
        let api = GatedNamesAPI()
        api.closeGate()
        let route = YourRouteModel()
        route.configure(api: api, service: nil, settings: nil)
        route.installPreview(phase: .done, chain: chain([24940, 15169]), context: context(), names: [:], myNetwork: nil)
        route.requestNames()
        _ = await bgpWait { api.calls.count == 1 }       // first fetch is in flight, blocked on the gate
        route.installPreview(phase: .done, chain: chain([24940, 1299, 15169]), context: context(), names: [:], myNetwork: nil)
        route.requestNames()                              // must not cancel the fetch in flight
        api.openGate()
        _ = await bgpWait { route.names[1299] != nil && route.names[15169] != nil && route.names[24940] != nil }
        #expect(route.names[15169] != nil)
        #expect(route.names[24940] != nil)
        #expect(route.names[1299] != nil)
    }

    @Test func failedNameFetchIsRetriedOnce() async {
        let api = GatedNamesAPI()
        api.failFirstCall()
        let route = YourRouteModel()
        route.configure(api: api, service: nil, settings: nil)
        route.installPreview(phase: .done, chain: chain([24940, 15169]), context: context(), names: [:], myNetwork: nil)
        route.requestNames()
        _ = await bgpWait { route.names[15169] != nil }
        #expect(route.names[15169] != nil)
        #expect(api.calls.count == 2)
    }

    // MARK: Handed-over trace

    @Test func handedOverTraceLooksUpMissingNetworks() async {
        let api = BGPFakeAPI()
        let router = AppRouter(selectedTool: .bgp)
        let model = makeBGPModel(api: api, service: CountingTraceService(Probes.service(Probes.worked)), router: router)
        let snap = snapshot(of: "8.8.8.8", hops: [(1, "192.168.1.1", nil), (2, "104.28.0.0", nil), (3, "8.8.8.8", nil)],
                            finishedAt: Date().addingTimeInterval(-30))
        router.open(.bgp, target: "8.8.8.8", autostart: true, trace: snap)
        model.consumeRouterRequest()
        _ = await bgpWait { model.phase == .loaded }
        await settled(model)
        #expect(model.route.phase == .done)
        #expect(model.route.chain?.asnSequence == [24940, 13335, 15169])
        #expect(api.networkInfoCalls.contains("104.28.0.0"))
    }

    @Test func handedOverTraceWithLookupsOffAndNoBGPIsLookupsOff() async {
        let settings = makeSettings()
        settings.trace.lookUpASNs = false
        let service = CountingTraceService(Probes.service(Probes.worked))
        let router = AppRouter(selectedTool: .bgp)
        let model = makeBGPModel(api: BGPFakeAPI(), service: service, settings: settings, router: router)
        let snap = snapshot(of: "8.8.8.8", hops: [(1, "192.168.1.1", nil), (2, "104.28.0.0", nil), (3, "8.8.8.8", nil)],
                            finishedAt: Date())
        router.open(.bgp, target: "8.8.8.8", autostart: true, trace: snap)
        model.consumeRouterRequest()
        _ = await bgpWait { model.phase == .loaded }
        await settled(model)
        #expect(model.route.phase == .lookupsOff)
        #expect(service.count == 0)
    }

    // MARK: Background

    @Test func noMeasurementStartsWhileBackgrounded() async {
        let service = CountingTraceService(Probes.service(Probes.worked))
        let model = makeBGPModel(api: BGPFakeAPI(), service: service)
        model.stopForBackground()
        await load(model)
        await settled(model)
        #expect(model.route.phase == .stopped("Stopped: app moved to background"))
        #expect(service.count == 0)
        model.resumeFromBackground()
        model.route.measureAgain()
        await settled(model)
        #expect(service.count == 1)
        #expect(model.route.phase == .done)
    }

    // MARK: Hop lookups

    @Test func lookupGraceScalesAndIsCapped() {
        #expect(RouteMeasurer.lookupGrace(pending: 0) == .seconds(4))
        #expect(RouteMeasurer.lookupGrace(pending: 3) == .seconds(4))
        #expect(RouteMeasurer.lookupGrace(pending: 8) == .seconds(6))
        #expect(RouteMeasurer.lookupGrace(pending: 100) == .seconds(10))
    }

    @Test func failedLookupIsFailedNotUnannounced() async {
        let api = BGPFakeAPI()
        api.failNetworkInfo = ["104.28.0.0"]
        #expect(await RouteMeasurer.lookup("104.28.0.0", api: api) == .failed)
        #expect(api.networkInfoCalls.filter { $0 == "104.28.0.0" }.count == 2)      // retried once
        #expect(await RouteMeasurer.lookup("203.0.113.9", api: api) == .found(nil))
        #expect(await RouteMeasurer.lookup("8.8.8.8", api: api) == .found(15169))
    }

    // MARK: Text

    @Test func routersAnsweredButLookupsFailed() async {
        let api = BGPFakeAPI()
        api.failNetworkInfo = ["104.28.0.0", "172.71.133.1", "141.101.67.186", "141.101.67.57"]
        let script = Probes.local + Probes.cloudflare + Array(repeating: Probes.silent, count: 5)
        let model = makeBGPModel(api: api, service: Probes.service(script))
        await load(model)
        await settled(model)
        #expect(model.route.phase == .partial("Couldn't look up the networks on the way."))
    }

    @Test func inProgressVoiceOverNeverSaysStopped() {
        let route = YourRouteModel()
        let live = ASChain(nodes: [ASChain.Node(asn: nil, role: .you, provenance: .measured),
                                   ASChain.Node(asn: 15169, role: .destination, provenance: .expected, gapBefore: true)],
                           source: .traceroute(handedOver: false, measuredAt: Date()), completion: .inProgress, reachedTarget: false)
        route.installPreview(phase: .measuring(ttl: 4), chain: live, context: context(), names: [:], myNetwork: nil)
        #expect(route.accessibilitySentence.hasSuffix("Measuring, hop 4."))
        route.installPreview(phase: .measuring(ttl: 0), chain: live, context: context(), names: [:], myNetwork: nil)
        #expect(!route.accessibilitySentence.contains("stopped"))
        #expect(!route.accessibilitySentence.contains("Measuring, hop"))
    }

    // MARK: Privacy and shared state

    @Test func rejectedHostnameNeverAsksWhatsMyIP() async {
        let api = BGPFakeAPI()
        let model = makeBGPModel(api: api, service: nil)
        model.targetText = "localhost"
        model.map()
        _ = await bgpWait { if case .failed = model.phase { true } else { false } }
        #expect(model.failure?.kind == .notRouted)
        #expect(api.whatsMyIPCalls == 0)
    }

    @Test func myNetworkHasOneSource() async {
        let api = BGPFakeAPI()
        let model = makeBGPModel(api: api, service: Probes.service(Probes.worked))
        await load(model)
        await settled(model)
        _ = await bgpWait { model.route.myNetwork?.name != nil }
        #expect(model.myNetwork == model.route.myNetwork)
        #expect(model.myNetwork?.name != nil)
    }
}

@Suite struct BGPLocalHopsTests {
    private func node(_ kinds: [ChainHop.Kind], role: ASChain.Node.Role = .you) -> ASChain.Node {
        let hops = kinds.enumerated().map { ChainHop(ttl: $0.offset + 1, kind: $0.element) }
        return ASChain.Node(asn: 24940, role: role, provenance: .measured, ttls: 1...kinds.count,
                            answeredHops: kinds.count, hops: hops)
    }

    @Test func allPrivateSaysLocal() {
        let n = node([.privateAddress, .silent, .privateAddress])
        #expect(RouteText.localHops(n) == .all)
    }

    @Test func mixedCountsLocalHops() {
        let n = node([.privateAddress, .privateAddress, .privateAddress, .privateAddress, .network(24940),
                      .silent, .silent, .silent, .network(24940), .network(24940)])
        #expect(RouteText.localHops(n) == .mixed(4))
    }

    @Test func noPrivateHopsAddsNothing() {
        let n = node([.network(24940), .silent])
        #expect(RouteText.localHops(n) == .none)
    }
}
