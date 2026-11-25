// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore
import RIPEstat
import SharedUI
import Testing
@testable import WhoisFeature

/// Runs against the real NetCore tables and the real summarizer. Skip these while those are still stubs
/// (`swift test --skip WhoisIntegrationTests`); they are for the merged tree.
@Suite @MainActor struct WhoisIntegrationTests {
    private func model(_ api: WhoisFakeAPI, router: AppRouter = AppRouter(selectedTool: .whois)) -> WhoisModel {
        WhoisModel(api: api, recents: makeRecents(), router: router, settings: makeSettings(),
                   reverseName: { _ in "rev.example" }, localAddresses: { [] })
    }

    @Test func realClassificationOfSpecialInputs() {
        for text in ["10.0.0.1", "192.168.1.1", "100.64.0.1", "127.0.0.1", "169.254.1.1", "192.0.2.1", "224.0.0.1",
                     "fe80::1", "fc00::1", "2001:db8::1", "10.0.0.0/8", "AS64512", "AS23456", "AS0"] {
            guard case .local? = WhoisModel.classify(text) else { Issue.record("\(text) should be answered locally"); continue }
        }
        for text in ["8.8.8.8", "2606:4700::1111", "1.1.1.0/24", "AS13335", "apple.com"] {
            if case .local? = WhoisModel.classify(text) { Issue.record("\(text) should not be local") }
        }
    }

    @Test func mappedAddressesOfferTheEmbeddedIPv4() {
        for text in ["::ffff:8.8.8.8", "64:ff9b::808:808", "2002:808:808::1"] {
            guard case let .local(verdict)? = WhoisModel.classify(text) else { Issue.record("\(text) should be local"); continue }
            #expect(verdict.embeddedIPv4 == ip("8.8.8.8"), "\(text)")
        }
    }

    @Test func hostBitsAreClearedInPrefixes() {
        #expect(WhoisModel.classify("1.1.1.7/24") == .subject(.prefix(ip("1.1.1.0"), length: 24)))
    }

    @Test func localInputMakesNoRequest() {
        let api = WhoisFakeAPI()
        let model = model(api)
        for text in ["192.168.1.1", "AS64512", "::ffff:8.8.8.8"] { model.lookUp(text) }
        #expect(api.calls.isEmpty)
    }

    @Test func arinIPv6RetryWithTheRealNoMatchRule() async throws {
        let api = WhoisFakeAPI()
        let address = "2001:4860:4860::8888"
        api.whoisByResource[address] = noMatchResponse(address)
        api.whoisByResource["2001:4860::/32"] = objectResponse("2001:4860::/32")
        api.networkByIP[address] = NetworkInfo(prefix: "2001:4860::/32", originASNs: [15169])
        api.holders[15169] = "GOOGLE - Google LLC"
        let loader = WhoisLoader(api: api, reverseName: { _ in nil }, includeLocation: false)
        let result = try await loader.load(.address(ip(address), hostname: nil))
        #expect(result.retriedWith == "2001:4860::/32")
    }

    @Test func noMatchMarkersAreLeftOutOfTheFullRecord() {
        let result = WhoisPreviewData.result(
            .address(ip("8.8.8.8"), hostname: nil), WhoisSummary(subject: .network, query: "8.8.8.8"),
            raw: whoisResponse("8.8.8.8", records: [whoisRecord([("NetRange", "8.8.8.0 - 8.8.8.255")]),
                                                    whoisRecord([("No match found for + ! 2001", "x")], id: 1)]))
        let text = WhoisExport.full(result, now: Date())
        #expect(text.contains("NetRange:"))
        #expect(!text.contains("No match found"))
    }

    @Test func fullLookupThroughTheRealSummarizer() async {
        let api = WhoisFakeAPI()
        sampleNetwork(api)
        let model = model(api)
        model.lookUp("8.8.8.8")
        #expect(await waitUntil { if case .loaded = model.phase { true } else { false } })
        #expect(model.exportText.contains("WHOIS 8.8.8.8"))
    }
}
