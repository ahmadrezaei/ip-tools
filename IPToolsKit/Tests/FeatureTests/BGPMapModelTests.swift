// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import BGPGraph
import Foundation
import NetCore
import RIPEstat
import SharedUI
import Testing
@testable import BGPFeature

/// Fails the test on any call: used to prove that private ranges never reach the network.
private struct ForbiddenAPI: RIPEstatAPI {
    func networkInfo(_ ip: String) async throws -> NetworkInfo { Issue.record("networkInfo called"); throw RIPEstatError.offline }
    func prefixOverview(_ prefix: String) async throws -> PrefixOverview { Issue.record("prefixOverview called"); throw RIPEstatError.offline }
    func lookingGlass(_ resource: String) async throws -> LookingGlass { Issue.record("lookingGlass called"); throw RIPEstatError.offline }
    func asOverview(_ asn: UInt32) async throws -> ASOverview { Issue.record("asOverview called"); throw RIPEstatError.offline }
    func asNames(_ asns: [UInt32]) async throws -> [UInt32: String] { Issue.record("asNames called"); throw RIPEstatError.offline }
    func announcedPrefixes(_ asn: UInt32) async throws -> [String] { Issue.record("announcedPrefixes called"); throw RIPEstatError.offline }
    func routingStatus(_ prefix: String) async throws -> RoutingStatus { Issue.record("routingStatus called"); throw RIPEstatError.offline }
}

private struct FailingAPI: RIPEstatAPI {
    let error: RIPEstatError
    func networkInfo(_ ip: String) async throws -> NetworkInfo { throw error }
    func prefixOverview(_ prefix: String) async throws -> PrefixOverview { throw error }
    func lookingGlass(_ resource: String) async throws -> LookingGlass { throw error }
    func asOverview(_ asn: UInt32) async throws -> ASOverview { throw error }
    func asNames(_ asns: [UInt32]) async throws -> [UInt32: String] { throw error }
    func announcedPrefixes(_ asn: UInt32) async throws -> [String] { throw error }
    func routingStatus(_ prefix: String) async throws -> RoutingStatus { throw error }
}

@Suite @MainActor struct BGPMapModelTests {
    private func makeModel(api: any RIPEstatAPI = MockRIPEstat(fixtureBundle: .main, latency: .milliseconds(1))) -> BGPMapModel {
        let defaults = UserDefaults(suiteName: "com.ahmadrezaei.iptools.bgp-tests.\(UUID().uuidString)")!
        return BGPMapModel(api: api, recents: RecentsStore(defaults: defaults), router: AppRouter(selectedTool: .bgp))
    }

    private func wait(_ condition: @MainActor () -> Bool) async {
        _ = await bgpWait(condition)
    }

    @Test func classifiesInput() {
        #expect(BGPMapModel.classify("1.1.1.1") == .ip(IPAddress("1.1.1.1")!))
        #expect(BGPMapModel.classify("AS13335") == .asn(13335))
        #expect(BGPMapModel.classify("13335") == .asn(13335))
        #expect(BGPMapModel.classify("1.1.1.0/24") == .prefix(IPAddress("1.1.1.0")!, length: 24))
        #expect(BGPMapModel.classify("cloudflare.com") == .hostname("cloudflare.com"))
        #expect(BGPMapModel.classify("   ") == nil)
    }

    @Test(arguments: ["10.1.2.3", "192.168.0.0/16", "fd00::/8", "AS64512", "127.0.0.1", "4200000001"])
    func privateInputNeverHitsTheNetwork(_ input: String) {
        let model = makeModel(api: ForbiddenAPI())
        model.targetText = input
        model.map()
        #expect(model.failure?.kind == .notRouted)
        if case .failed = model.phase {} else { Issue.record("expected failed phase for \(input)") }
        #expect(model.result == nil)
    }

    @Test func invalidInputFails() {
        let model = makeModel(api: ForbiddenAPI())
        model.targetText = "not a host!"
        model.map()
        #expect(model.failure?.kind == .invalid)
    }

    @Test func asnInputOpensPrefixPicker() async {
        let model = makeModel()
        model.targetText = "AS13335"
        model.map()
        await wait { if case .pickingPrefix = model.phase { true } else { false } }
        guard case let .pickingPrefix(asn, holder, prefixes) = model.phase else {
            Issue.record("expected picker, got \(model.phase)")
            return
        }
        #expect(asn == 13335)
        #expect(holder?.contains("Cloudflare") == true)
        #expect(prefixes.first == "1.0.0.0/24" || prefixes.first == "1.1.1.0/24")
        #expect(prefixes.last == "2606:4700::/32")
        #expect(model.recents.items.first?.display == "AS13335")
    }

    @Test func prefixSortingIsV4ThenShortest() {
        let sorted = BGPMapModel.sortPrefixes(["2001:db8::/32", "10.0.0.0/24", "10.0.0.0/8", "2001:db8::/48", "10.1.0.0/16"])
        #expect(sorted == ["10.0.0.0/8", "10.1.0.0/16", "10.0.0.0/24", "2001:db8::/32", "2001:db8::/48"])
    }

    @Test func ipInputLoadsAGraph() async {
        let model = makeModel()
        model.targetText = "1.1.1.1"
        model.map()
        await wait { model.phase == .loaded }
        #expect(model.phase == .loaded)
        #expect(model.result?.prefix == "1.1.1.0/24")
        #expect(model.result?.collectors.count == 8)
        #expect(model.result?.visibility?.total == 319)
        #expect((model.result?.graph.totalPaths ?? 0) > 0)
        #expect(model.recents.items.first?.display == "1.1.1.1")
        await wait { model.result?.names[13335] != nil }
        #expect(model.result?.names[13335]?.contains("Cloudflare") == true)
    }

    @Test func prefixInputLoadsAGraph() async {
        let model = makeModel()
        model.targetText = "8.8.8.0/24"
        model.map()
        await wait { model.phase == .loaded }
        #expect(model.result?.prefix == "8.8.8.0/24")
        #expect(model.result?.originASNs.contains(15169) == true)
    }

    @Test func changingKRebuilds() async {
        let model = makeModel()
        model.targetText = "1.1.1.1"
        model.map()
        await wait { model.phase == .loaded }
        let before = model.layoutVersion
        model.maxNodesPerLayer = 12
        await wait { model.layoutVersion != before }
        #expect(model.layoutVersion != before)
    }

    @Test func errorsAreMapped() async {
        for (error, kind) in [(RIPEstatError.rateLimited, BGPFailure.Kind.busy), (.timeout, .timeout), (.offline, .offline),
                              (.http(status: 503), .busy), (.api(messages: ["bad"]), .other)] {
            let model = makeModel(api: FailingAPI(error: error))
            model.targetText = "1.1.1.1"
            model.map()
            await wait { if case .failed = model.phase { true } else { false } }
            #expect(model.failure?.kind == kind)
        }
    }

    @Test func cancelReturnsToIdle() async {
        let model = makeModel(api: MockRIPEstat(fixtureBundle: .main, latency: .seconds(60)))
        model.targetText = "1.1.1.1"
        model.map()
        #expect({ if case .loading = model.phase { true } else { false } }())
        model.cancel()
        #expect(model.phase == .idle)
    }

    @Test func routerHandOverAutostarts() async {
        let model = makeModel()
        model.router.open(.bgp, target: "AS13335", autostart: true)
        model.consumeRouterRequest()
        #expect(model.targetText == "AS13335")
        await wait { if case .pickingPrefix = model.phase { true } else { false } }
        if case .pickingPrefix = model.phase {} else { Issue.record("expected picker") }
    }

    // MARK: Stats, highlight, export (hand-made graph)

    @Test func statsDescribeNodes() {
        let (result, _) = BGPPreviewData.result()
        let stats = BGPStats(graph: result.graph)
        #expect(stats.total == BGPPreviewData.paths.count)
        #expect(stats.role(of: 13335) == .origin)
        #expect(stats.role(of: 3356) == .transit)
        #expect(stats.role(of: 6939) == .peer)
        #expect(stats.layer[3356] == 1)
        #expect(stats.layer[12389] == 2)
        let summary = stats.summary(for: .asn(3356), graph: result.graph)
        #expect(summary?.paths == 9)
    }

    @Test func highlightCoversPathsThroughSelection() {
        let model = BGPPreviewData.loadedModel(selection: .asn(3356))
        let highlight = model.highlight
        #expect(highlight?.nodes.contains(.asn(13335)) == true)
        #expect(highlight?.nodes.contains(.asn(20940)) == true)
        #expect(highlight?.nodes.contains(.asn(6939)) == false)
        #expect(highlight?.edges.contains(GraphEdge(from: .asn(3356), to: .asn(13335), pathCount: 0, kind: .forward).id) == true)
        model.selection = nil
        #expect(model.highlight == nil)
    }

    @Test func collapsedASNsAreReachableThroughBucket() {
        let model = BGPPreviewData.loadedModel()
        let stats = model.stats!
        let hidden = stats.layerMembers[2]!.last!
        guard case .more? = stats.nodeFor(hidden) else {
            Issue.record("expected a collapsed AS in layer 2")
            return
        }
        model.selection = .asn(hidden)
        #expect(model.selectedNodeID == stats.nodeFor(hidden))
        #expect(model.highlight?.nodes.contains(.asn(13335)) == true)
    }

    @Test func exportTextFollowsTheSpec() {
        let (result, _) = BGPPreviewData.result()
        let text = BGPExport.text(result: result)
        let lines = text.split(separator: "\n").map(String.init)
        #expect(lines[0] == "BGP paths for 1.1.1.0/24 (origin AS13335 Cloudflare, Inc.)")
        #expect(lines[1].hasPrefix("Source: RIPE RIS via RIPEstat looking-glass, 5 collectors, \(BGPPreviewData.paths.count) paths"))
        #expect(lines.contains { $0.hasPrefix("Upstreams (1 hop): AS") })
        #expect(lines.contains("Unique AS paths:"))
        #expect(lines.contains("  6939 13335   ×9"))
        #expect(BGPExport.text(result: nil).isEmpty)
    }

    // MARK: Zoom / pan

    @Test func zoomPanFitAndClamp() {
        let content = CGSize(width: 1000, height: 600), view = CGSize(width: 400, height: 800)
        let fitted = ZoomPanState.fitted(content: content, in: view)
        #expect(abs(fitted.scale - 0.4) < 0.0001)
        // The opening view ignores the width: scale from the height (0.7...1.0), origin centred and clamped.
        let initial = ZoomPanState.initial(content: content, in: view, originMidX: 500)
        #expect(initial.scale == 1)                                               // capped at 1.0
        #expect(abs(initial.offset.width - (200 - 500)) < 0.001)                  // origin centred, inside the clamp range
        #expect(initial.offset.height == 100)                                      // shorter than the view: centred
        let center = ZoomPanState.initial(content: CGSize(width: 1000, height: 600), in: CGSize(width: 400, height: 300), originMidX: 100)
        #expect(center.scale == 0.7 && center.offset.width == 0)                  // clamped to 0
        #expect(abs(center.offset.height - (300 - 420) / 2) < 0.0001 || center.offset.height == 300 - 420)
        // A tall graph is bottom-anchored.
        let tall = ZoomPanState.initial(content: CGSize(width: 400, height: 2000), in: view, originMidX: 200)
        #expect(tall.scale == 0.7 && tall.offset.height == 800 - 1400)
        // With an overlay: centre on the span of the path nodes plus the origin.
        let origin = CGRect(x: 800, y: 500, width: 100, height: 60)
        let near = ZoomPanState.PathFocus(origin: origin, overlay: [CGRect(x: 600, y: 0, width: 100, height: 60), origin])!
        let spanned = ZoomPanState.initial(content: content, in: view, originMidX: origin.midX, path: near)
        #expect(spanned.scale == 1 && abs(spanned.offset.width - (200 - 750)) < 0.001)     // span 600...900, midpoint 750
        // A span wider than the view favours YOU (left of the origin here) and keeps it fully visible.
        let youFrame = CGRect(x: 100, y: 0, width: 100, height: 60)
        let wide = ZoomPanState.PathFocus(origin: origin, overlay: [youFrame, origin])!
        let favoured = ZoomPanState.initial(content: content, in: view, originMidX: origin.midX, path: wide)
        #expect(wide.you == youFrame && abs(favoured.offset.width - (8 - 100)) < 0.001)
        #expect(favoured.offset.width + youFrame.minX >= 0 && favoured.offset.width + youFrame.maxX <= view.width)
        // No overlay frames: falls back to the origin.
        #expect(ZoomPanState.PathFocus(origin: origin, overlay: []) == nil)
        let fallback = ZoomPanState.initial(content: content, in: view, originMidX: 500, path: nil)
        #expect(abs(fallback.offset.width - (200 - 500)) < 0.001)
        let far = ZoomPanState(scale: 1, offset: CGSize(width: 5000, height: -5000)).clamped(content: content, in: view)
        #expect(far.offset.width == 320)
        #expect(abs(far.offset.height - (-520)) < 0.0001)
        let zoomed = ZoomPanState(scale: 1, offset: .zero).zoomed(by: 2, at: CGPoint(x: 100, y: 100), minScale: 0.3)
        #expect(zoomed.scale == 2 && zoomed.offset == CGSize(width: -100, height: -100))
        #expect(ZoomPanState().zoomed(by: 100, at: .zero, minScale: 0.3).scale == 3)
    }
}
