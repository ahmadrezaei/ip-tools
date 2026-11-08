// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import Testing
@testable import BGPGraph

private let measured = ASChain.Source.traceroute(handedOver: false, measuredAt: Date(timeIntervalSince1970: 0))

private func hop(_ ttl: Int, _ kind: ChainHop.Kind, _ address: String? = nil, rtts: [TimeInterval] = [],
                 reached: Bool = false) -> ChainHop {
    ChainHop(ttl: ttl, kind: kind, address: address, rtts: rtts, reachedTarget: reached)
}

/// The worked example of DESIGN 6.11.6 (8.8.8.8 from AS24940, hop 10 silent).
private let workedHops: [ChainHop] = [
    hop(1, .privateAddress, "192.168.70.1", rtts: [0.003, 0.004]),
    hop(2, .privateAddress, "172.16.21.1", rtts: [0.010]),
    hop(3, .privateAddress, "10.99.7.1", rtts: [0.133]),
    hop(4, .network(13335), "104.28.0.0", rtts: [0.128, 0.130]),
    hop(5, .network(13335), "172.71.133.1", rtts: [0.135]),
    hop(6, .network(13335), "141.101.67.186", rtts: [0.140]),
    hop(7, .network(13335), "141.101.67.57", rtts: [0.151]),
    hop(8, .network(15169), "108.170.255.223", rtts: [0.139]),
    hop(9, .network(15169), "72.14.237.93", rtts: [0.145]),
    hop(10, .silent),
    hop(11, .network(15169), "8.8.8.8", rtts: [0.152], reached: true),
]

private func build(_ hops: [ChainHop], my: UInt32? = 24940, origins: [UInt32] = [15169], finished: Bool = true) -> ASChain {
    ASChainBuilder.fromTrace(hops, myASN: my, origins: origins, finished: finished, source: measured)
}

@Suite struct ASChainFromTraceTests {
    @Test func workedExample() {
        let chain = build(workedHops)
        #expect(chain.asnSequence == [24940, 13335, 15169])
        #expect(chain.nodes.map(\.role) == [.you, .transit, .destination])
        #expect(chain.completion == .complete)
        #expect(chain.reachedTarget)
        #expect(chain.lastTTL == 11)
        #expect(chain.skippedHops == 0)
        let (you, cf, google) = (chain.nodes[0], chain.nodes[1], chain.nodes[2])
        #expect(you.ttls == 1...3 && you.answeredHops == 3)
        #expect(you.rttRange == 0.003...0.133)
        #expect(you.hops.count == 3 && you.provenance == .measured)
        #expect(cf.ttls == 4...7 && cf.answeredHops == 4)
        #expect(cf.rttRange == 0.128...0.151)
        #expect(google.ttls == 8...11)
        #expect(google.answeredHops == 3)                    // hop 10 is silent
        #expect(google.hops.count == 4)                      // ... but absorbed into the node
        #expect(google.rttRange == 0.139...0.152)
        #expect(chain.nodes.allSatisfy { !$0.gapBefore })
        #expect(chain.nodes.map(\.id) == ["AS24940", "AS13335", "AS15169"])
    }

    @Test func classification() {
        // Leading block of every kind of non-network hop belongs to You.
        let hops = [hop(1, .silent), hop(2, .privateAddress, "10.0.0.1"), hop(3, .unknownNetwork, "193.0.0.1"),
                    hop(4, .network(15169), "8.8.8.8", reached: true)]
        let chain = build(hops, my: nil)
        #expect(chain.asnSequence == [15169])
        #expect(chain.nodes.count == 2)
        #expect(chain.nodes[0].asn == nil && chain.nodes[0].id == "you")
        #expect(chain.nodes[0].ttls == 1...3 && chain.nodes[0].answeredHops == 2)
        #expect(chain.nodes[1].role == .destination)
    }

    @Test func youNodeAbsorbsFirstSegmentWhenAddressMatches() {
        let hops = [hop(1, .privateAddress, "192.168.1.1", rtts: [0.002]),
                    hop(2, .network(24940), "91.107.0.1", rtts: [0.004]),
                    hop(3, .network(15169), "8.8.8.8", rtts: [0.010], reached: true)]
        let chain = build(hops)
        #expect(chain.asnSequence == [24940, 15169])
        #expect(chain.nodes[0].role == .you)
        #expect(chain.nodes[0].ttls == 1...2)
        #expect(chain.nodes[0].hops.count == 2)
        #expect(chain.nodes[0].rttRange == 0.002...0.004)
    }

    @Test func differentFirstASShowsBothAndInventsNothing() {
        let hops = [hop(1, .network(13335), "104.28.0.0", rtts: [0.01]),
                    hop(2, .network(15169), "8.8.8.8", rtts: [0.02], reached: true)]
        let chain = build(hops)                              // myASN 24940, no hops seen inside it
        #expect(chain.asnSequence == [24940, 13335, 15169])
        let you = chain.nodes[0]
        #expect(you.asn == 24940 && you.role == .you)
        #expect(you.ttls == nil && you.answeredHops == 0 && you.rttRange == nil && you.hops.isEmpty)
        #expect(chain.nodes.count == 3)
    }

    @Test func absorbedSilentAndUnknownHopsBetweenSameAS() {
        let hops = [hop(1, .network(13335), "1.0.0.1", rtts: [0.010]),
                    hop(2, .silent), hop(3, .unknownNetwork, "80.81.192.1", rtts: [0.5]),
                    hop(4, .network(13335), "1.0.0.2", rtts: [0.020]),
                    hop(5, .network(15169), "8.8.8.8", rtts: [0.030], reached: true)]
        let chain = build(hops, my: nil)
        #expect(chain.asnSequence == [13335, 15169])
        let cf = chain.nodes[1]
        #expect(cf.ttls == 1...4)
        #expect(cf.answeredHops == 3)
        #expect(cf.hops.count == 4)
        #expect(cf.rttRange == 0.010...0.020)                // absorbed hops add no RTT
        #expect(chain.skippedHops == 0)
    }

    @Test func nonNetworkHopsBetweenDifferentASesAreDroppedAndCounted() {
        let hops = [hop(1, .network(13335), "1.0.0.1", rtts: [0.01]),
                    hop(2, .silent), hop(3, .unknownNetwork, "80.81.192.1", rtts: [0.02]),
                    hop(4, .network(15169), "8.8.8.8", rtts: [0.03], reached: true)]
        let chain = build(hops, my: nil)
        #expect(chain.asnSequence == [13335, 15169])
        #expect(chain.skippedHops == 2)
        #expect(chain.nodes[1].hops.count == 1)
    }

    @Test func abaLoopFoldsIntoTheEarlierSegment() {
        let hops = [hop(1, .network(100), rtts: [0.01]),
                    hop(2, .network(200), rtts: [0.02]),
                    hop(3, .network(300), rtts: [0.03]),
                    hop(4, .network(100), rtts: [0.04]),
                    hop(5, .network(15169), "8.8.8.8", rtts: [0.05], reached: true)]
        let chain = build(hops, my: nil)
        #expect(chain.asnSequence == [100, 15169])
        let a = chain.nodes[1]
        #expect(a.asn == 100 && a.ttls == 1...4 && a.hops.count == 4)
        #expect(a.rttRange == 0.01...0.04)
        #expect(Set(chain.nodes.map(\.id)).count == chain.nodes.count)
    }

    @Test func loopFoldDoesNotCountFoldedDroppedHops() {
        let hops = [hop(1, .network(100)), hop(2, .silent), hop(3, .network(200)),
                    hop(4, .silent), hop(5, .network(100)), hop(6, .network(15169), reached: true)]
        let chain = build(hops, my: nil)
        #expect(chain.asnSequence == [100, 15169])
        #expect(chain.skippedHops == 0)
    }

    @Test func myASNReappearingFoldsIntoYou() {
        let hops = [hop(1, .network(13335)), hop(2, .network(24940)), hop(3, .network(15169), reached: true)]
        let chain = build(hops)
        #expect(chain.asnSequence == [24940, 15169])
        #expect(chain.nodes[0].ttls == 1...2)
    }

    @Test func destinationIsReachedWhenLastSegmentIsAnOrigin() {
        let chain = build(workedHops)
        #expect(chain.nodes.last?.role == .destination)
        #expect(chain.nodes.last?.provenance == .measured)
    }

    @Test func gapAppendsAnExpectedDestination() {
        let hops = Array(workedHops[0..<7])               // stalled inside Cloudflare
        let chain = build(hops)
        #expect(chain.completion == .gap)
        #expect(chain.asnSequence == [24940, 13335, 15169])
        let expected = chain.nodes[2]
        #expect(expected.provenance == .expected && expected.role == .destination && expected.gapBefore)
        #expect(expected.ttls == nil && expected.hops.isEmpty && expected.routeCount == nil)
        #expect(chain.nodes[1].role == .transit)
        #expect(!chain.reachedTarget)
        #expect(chain.lastTTL == 7)
    }

    @Test func inProgressWhileMeasuring() {
        let chain = build(Array(workedHops[0..<5]), finished: false)
        #expect(chain.completion == .inProgress)
        #expect(chain.nodes.last?.provenance == .expected)
        // Reaching the origin completes the chain even before the trace is finished.
        #expect(build(workedHops, finished: false).completion == .complete)
    }

    @Test func noPublicHopAnsweredShowsYouThenExpected() {
        let chain = build([hop(1, .privateAddress, "192.168.1.1", rtts: [0.001]), hop(2, .silent), hop(3, .silent)])
        #expect(chain.nodes.count == 2)
        #expect(chain.nodes[0].role == .you && chain.nodes[1].provenance == .expected)
        #expect(chain.completion == .gap)
        #expect(chain.lastTTL == 1)
        let empty = build([], my: nil, finished: false)
        #expect(empty.nodes.count == 2 && empty.completion == .inProgress && empty.lastTTL == nil)
        #expect(empty.nodes[0].asn == nil)
    }

    @Test func ownNetworkIsASingleNode() {
        let hops = [hop(1, .privateAddress, "192.168.1.1", rtts: [0.001]),
                    hop(2, .network(15169), "8.8.8.8", rtts: [0.002], reached: true)]
        let chain = build(hops, my: 15169)
        #expect(chain.nodes.count == 1)
        #expect(chain.nodes[0].role == .youAndDestination)
        #expect(chain.nodes[0].asn == 15169)
        #expect(chain.completion == .complete)
        #expect(chain.nodes[0].ttls == 1...2)
    }

    @Test func rolesFirstYouLastDestinationRestTransit() {
        let hops = [hop(1, .network(1)), hop(2, .network(2)), hop(3, .network(3)), hop(4, .network(9), reached: true)]
        let chain = build(hops, my: 1, origins: [9])
        #expect(chain.nodes.map(\.role) == [.you, .transit, .transit, .destination])
    }

    @Test func hopsOutOfOrderAreSortedByTTL() {
        let chain = build(workedHops.reversed())
        #expect(chain.asnSequence == [24940, 13335, 15169])
        #expect(chain == build(workedHops))
    }

    @Test func deterministic() {
        #expect(build(workedHops) == build(workedHops))
    }
}

@Suite struct ASChainBGPTests {
    @Test func fromBGPOnTheRealFixtureForAS3320() async throws {
        let graph = GraphBuilder.build(from: try await fixturePaths("8.8.8.0/24"))
        let chain = try #require(ASChainBuilder.fromBGP(graph.cleanedPaths, myASN: 3320, origins: graph.origins))
        #expect(chain.asnSequence == [3320, 15169])
        #expect(chain.nodes.map(\.role) == [.you, .destination])
        #expect(chain.nodes.allSatisfy { $0.provenance == .bgp && $0.routeCount == 2 })
        #expect(chain.completion == .complete)
        #expect(chain.source == .bgp(collectors: ["RRC01", "RRC03"]))
    }

    @Test func nilWhenMyASNIsInNoPath() async throws {
        let graph = GraphBuilder.build(from: try await fixturePaths("8.8.8.0/24"))
        #expect(ASChainBuilder.fromBGP(graph.cleanedPaths, myASN: 24940, origins: graph.origins) == nil)
        #expect(ASChainBuilder.fromBGP(graph.cleanedPaths, myASN: 13335, origins: graph.origins) == nil)
    }

    @Test func mostCommonSuffixWinsTiesGoShorterThenSmaller() {
        let paths = repeated(3, [7, 10, 20]) + repeated(5, [8, 7, 30, 20]) + repeated(5, [9, 7, 40, 20])
        // Suffixes from 7: [7,10,20]x3, [7,30,20]x5, [7,40,20]x5 -> tie on count and length -> smaller ASN list.
        let chain = ASChainBuilder.fromBGP(paths, myASN: 7, origins: [20])
        #expect(chain?.asnSequence == [7, 30, 20])
        // Tie on count: shorter suffix first.
        let tie = repeated(2, [1, 5, 9]) + repeated(2, [1, 9])
        #expect(ASChainBuilder.fromBGP(tie, myASN: 1, origins: [9])?.asnSequence == [1, 9])
    }

    @Test func myASNIsTheOrigin() {
        let chain = ASChainBuilder.fromBGP(repeated(3, [1, 2, 9]), myASN: 9, origins: [9])
        #expect(chain?.nodes.count == 1)
        #expect(chain?.nodes.first?.role == .youAndDestination)
        #expect(chain?.nodes.first?.routeCount == 3)
    }

    @Test func middleASNsAreTransit() {
        let chain = ASChainBuilder.fromBGP(repeated(4, [3, 1, 2, 9]), myASN: 1, origins: [9])
        #expect(chain?.asnSequence == [1, 2, 9])
        #expect(chain?.nodes.map(\.role) == [.you, .transit, .destination])
    }
}

@Suite struct ASChainStitchTests {
    private func stalledIn(_ asn: UInt32) -> ASChain {
        let hops = [hop(1, .privateAddress, "10.0.0.1", rtts: [0.001]),
                    hop(2, .network(asn), "1.2.3.4", rtts: [0.01]),
                    hop(3, .network(asn), "1.2.3.5", rtts: [0.02]),
                    hop(4, .silent), hop(5, .silent)]
        return build(hops, my: 24940)
    }

    @Test func stitchesThroughAS1299OnTheRealFixture() async throws {
        let graph = GraphBuilder.build(from: try await fixturePaths("8.8.8.0/24"))
        let chain = stalledIn(1299)
        #expect(chain.completion == .gap)
        let stitched = ASChainBuilder.stitch(chain, cleanedPaths: graph.cleanedPaths, origins: graph.origins)
        #expect(stitched.completion == .stitched)
        #expect(stitched.asnSequence == [24940, 1299, 15169])
        #expect(stitched.nodes[2].provenance == .bgp)
        #expect(stitched.nodes[2].role == .destination)
        #expect(stitched.nodes[2].routeCount == 6)
        #expect(!stitched.nodes[2].gapBefore)
        #expect(stitched.nodes[1].provenance == .measured && stitched.nodes[1].role == .transit)
        #expect(stitched.nodes[1] == chain.nodes[1])          // measured part untouched
        #expect(stitched.lastTTL == chain.lastTTL && stitched.source == chain.source)
    }

    @Test func noStitchThroughAS13335OnTheRealFixture() async throws {
        let graph = GraphBuilder.build(from: try await fixturePaths("8.8.8.0/24"))
        let chain = stalledIn(13335)
        let result = ASChainBuilder.stitch(chain, cleanedPaths: graph.cleanedPaths, origins: graph.origins)
        #expect(result == chain)
        #expect(result.completion == .gap)
        #expect(result.nodes.last?.gapBefore == true && result.nodes.last?.provenance == .expected)
    }

    @Test func multiHopSuffixIsAppendedInOrder() {
        let chain = stalledIn(100)
        let paths = repeated(3, [5, 100, 200, 300, 15169]) + repeated(1, [6, 100, 400, 15169])
        let stitched = ASChainBuilder.stitch(chain, cleanedPaths: paths, origins: [15169])
        #expect(stitched.asnSequence == [24940, 100, 200, 300, 15169])
        #expect(stitched.nodes.map(\.role) == [.you, .transit, .transit, .transit, .destination])
        #expect(stitched.nodes.suffix(3).allSatisfy { $0.provenance == .bgp && $0.routeCount == 3 })
    }

    @Test func unchangedWhenNotAGap() {
        let paths = repeated(3, [5, 100, 15169])
        let complete = build(workedHops)
        #expect(ASChainBuilder.stitch(complete, cleanedPaths: paths, origins: [15169]) == complete)
        let inProgress = build(Array(workedHops[0..<5]), finished: false)
        #expect(ASChainBuilder.stitch(inProgress, cleanedPaths: paths, origins: [15169]) == inProgress)
    }

    @Test func neverStitchesFromAYouNodeWithoutASN() {
        let chain = build([hop(1, .privateAddress, "10.0.0.1"), hop(2, .silent)], my: nil)
        let paths = repeated(3, [5, 100, 15169])
        #expect(chain.completion == .gap)
        #expect(ASChainBuilder.stitch(chain, cleanedPaths: paths, origins: [15169]) == chain)
    }

    @Test func suffixesThatLoopBackIntoTheMeasuredChainAreSkipped() {
        let chain = stalledIn(100)                            // chain: AS24940, AS100
        let paths = repeated(5, [100, 24940, 15169]) + repeated(1, [100, 15169])
        let stitched = ASChainBuilder.stitch(chain, cleanedPaths: paths, origins: [15169])
        #expect(stitched.asnSequence == [24940, 100, 15169])
    }

    @Test func stitchedChainIsNotStitchedAgain() {
        let paths = repeated(3, [5, 100, 15169])
        let once = ASChainBuilder.stitch(stalledIn(100), cleanedPaths: paths, origins: [15169])
        #expect(ASChainBuilder.stitch(once, cleanedPaths: paths, origins: [15169]) == once)
    }
}
