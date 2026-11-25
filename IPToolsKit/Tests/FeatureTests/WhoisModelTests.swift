// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore
import RIPEstat
import SharedUI
import Testing
@testable import WhoisFeature

@Suite @MainActor struct WhoisModelTests {
    private func loaded(_ model: WhoisModel) -> WhoisResult? {
        if case let .loaded(result) = model.phase { result } else { nil }
    }

    private func resolver(_ address: String, host: String, others: [String] = []) -> @Sendable (String, AddressPreference) async throws -> ResolvedTarget {
        { _, _ in
            let main = IPAddress(address)!
            return ResolvedTarget(input: host, address: main, hostname: host,
                                  allAddresses: [main] + others.map { IPAddress($0)! })
        }
    }

    // MARK: Classification

    @Test func classifiesEachKindOfInput() {
        let rules = WhoisRules.stub
        #expect(WhoisModel.classify("8.8.8.8", rules: rules) == .subject(.address(ip("8.8.8.8"), hostname: nil)))
        #expect(WhoisModel.classify(" as13335 ", rules: rules) == .subject(.asn(13335)))
        #expect(WhoisModel.classify("13335", rules: rules) == .subject(.asn(13335)))
        #expect(WhoisModel.classify("apple.com", rules: rules) == .hostname("apple.com"))
        #expect(WhoisModel.classify("1.1.1.7/24", rules: rules) == .subject(.prefix(ip("1.1.1.0"), length: 24)))
        #expect(WhoisModel.classify("", rules: rules) == nil)
        #expect(WhoisModel.classify("not a host!", rules: rules) == nil)
    }

    @Test func specialInputsBecomeLocalVerdicts() {
        let rules = WhoisRules.stub
        guard case let .local(privateVerdict)? = WhoisModel.classify("192.168.1.1", rules: rules) else {
            Issue.record("expected local"); return
        }
        #expect(privateVerdict.input == "192.168.1.1")
        #expect(privateVerdict.embeddedIPv4 == nil)
        guard case let .local(mapped)? = WhoisModel.classify("::ffff:8.8.8.8", rules: rules) else {
            Issue.record("expected local"); return
        }
        #expect(mapped.embeddedIPv4 == ip("8.8.8.8"))
        guard case .local? = WhoisModel.classify("AS64512", rules: rules) else { Issue.record("expected local"); return }
        guard case .local? = WhoisModel.classify("10.0.0.0/8", rules: rules) else { Issue.record("expected local"); return }
    }

    // MARK: Lookups

    @Test func addressLookupLoadsAndRecords() async {
        let api = WhoisFakeAPI()
        sampleNetwork(api)
        let recents = makeRecents()
        let model = makeWhoisModel(api: api, recents: recents)
        model.targetText = " 8.8.8.8 "
        model.lookUp()
        guard case .loading(.address) = model.phase else { Issue.record("expected loading, got \(model.phase)"); return }
        #expect(await waitUntil { loaded(model) != nil })
        #expect(loaded(model)?.reverseName == "rev.example")
        #expect(recents.items.map(\.display) == ["8.8.8.8"])
        #expect(recents.items.first?.lastTool == .whois)
    }

    @Test func invalidInputFailsWithoutRecordOrRequest() {
        let api = WhoisFakeAPI()
        let recents = makeRecents()
        let model = makeWhoisModel(api: api, recents: recents)
        model.targetText = "not a host!"
        model.lookUp()
        #expect(model.phase == .failed(.invalidInput))
        #expect(recents.items.isEmpty)
        #expect(api.calls.isEmpty)
    }

    @Test func localVerdictsMakeNoRequestAndAreRecorded() {
        let api = WhoisFakeAPI()
        let recents = makeRecents()
        let model = makeWhoisModel(api: api, recents: recents)
        for text in ["192.168.1.1", "10.0.0.0/8", "AS64512", "::ffff:8.8.8.8"] {
            model.lookUp(text)
            guard case .local = model.phase else { Issue.record("\(text) should be local"); continue }
        }
        #expect(api.calls.isEmpty)
        #expect(recents.items.count == 4)
    }

    @Test func prefixWithHostBitsReportsWhatIsShown() async {
        let api = WhoisFakeAPI()
        api.whoisByResource["1.1.1.0/24"] = objectResponse("1.1.1.0/24")
        api.overviewByPrefix["1.1.1.0/24"] = PrefixOverview(resource: "1.1.1.0/24", announced: true, origins: [])
        let model = makeWhoisModel(api: api)
        model.lookUp("1.1.1.7/24")
        #expect(model.shownAs == "1.1.1.0/24")
        #expect(await waitUntil { loaded(model) != nil })
    }

    @Test func hostNameResolvesThenLooksUpTheAddress() async {
        let api = WhoisFakeAPI()
        sampleNetwork(api, ip: "17.253.144.10", prefix: "17.253.0.0/16", origins: [714])
        let recents = makeRecents()
        let model = makeWhoisModel(api: api, recents: recents,
                                   resolve: resolver("17.253.144.10", host: "apple.com", others: ["17.253.144.11"]))
        model.lookUp("apple.com")
        guard case .resolving("apple.com") = model.phase else { Issue.record("expected resolving"); return }
        #expect(await waitUntil { loaded(model) != nil })
        #expect(loaded(model)?.subject == .address(ip("17.253.144.10"), hostname: "apple.com"))
        #expect(model.hostAddresses.count == 2)
        #expect(recents.items.map(\.display) == ["apple.com"])
    }

    @Test func hostNameResolvingToPrivateSpaceIsLocal() async {
        let api = WhoisFakeAPI()
        let model = makeWhoisModel(api: api, resolve: resolver("192.168.1.1", host: "router.lan"))
        model.lookUp("router.lan")
        #expect(await waitUntil { if case .local = model.phase { true } else { false } })
        #expect(api.calls.isEmpty)
    }

    @Test func resolveFailureIsShownAndNotRecorded() async {
        let recents = makeRecents()
        let model = makeWhoisModel(api: WhoisFakeAPI(), recents: recents)
        model.lookUp("apple.cmo")
        #expect(await waitUntil { if case .failed = model.phase { true } else { false } })
        guard case let .failed(failure) = model.phase else { return }
        #expect(failure.kind == .unresolved)
        #expect(recents.items.isEmpty)
    }

    @Test func failedLookupMapsTheError() async {
        let api = WhoisFakeAPI()
        api.failing = ["whois", "network-info"]
        let model = makeWhoisModel(api: api)
        model.lookUp("8.8.8.8")
        #expect(await waitUntil { if case .failed = model.phase { true } else { false } })
        #expect(model.phase == .failed(.busyFailure))
    }

    @Test func notFoundIsReported() async {
        let api = WhoisFakeAPI()
        api.whoisByResource["8.8.4.4"] = whoisResponse("8.8.4.4", records: [])
        api.networkByIP["8.8.4.4"] = NetworkInfo(prefix: nil, originASNs: [])
        api.abuseByResource["8.8.4.4"] = AbuseContacts(emails: [], authoritativeRIR: nil)
        let model = makeWhoisModel(api: api)
        model.lookUp("8.8.4.4")
        #expect(await waitUntil { if case .failed = model.phase { true } else { false } })
        if case let .failed(failure) = model.phase { #expect(failure.kind == .notFound) }
    }

    @Test func newLookupCancelsTheOldOne() async {
        let api = WhoisFakeAPI()
        sampleNetwork(api)
        sampleNetwork(api, ip: "8.8.4.4")
        api.delay = .milliseconds(150)
        let model = makeWhoisModel(api: api)
        model.lookUp("8.8.8.8")
        model.lookUp("8.8.4.4")
        #expect(await waitUntil { loaded(model) != nil })
        #expect(loaded(model)?.subject == .address(ip("8.8.4.4"), hostname: nil))
        try? await Task.sleep(for: .milliseconds(400))
        #expect(loaded(model)?.subject == .address(ip("8.8.4.4"), hostname: nil))
    }

    @Test func cancelStopsAndReturnsToMyIP() async {
        let api = WhoisFakeAPI()
        sampleNetwork(api)
        api.delay = .seconds(5)
        let model = makeWhoisModel(api: api)
        model.lookUp("8.8.8.8")
        model.cancel()
        #expect(model.phase == .myIP)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(model.phase == .myIP)
    }

    @Test func showMyIPClearsTheField() async {
        let api = WhoisFakeAPI()
        sampleNetwork(api)
        let model = makeWhoisModel(api: api)
        model.lookUp("8.8.8.8")
        #expect(await waitUntil { loaded(model) != nil })
        model.showMyIP()
        #expect(model.phase == .myIP)
        #expect(model.targetText.isEmpty)
    }

    // MARK: Router

    @Test func routerRequestPrefillsAndAutostarts() async {
        let api = WhoisFakeAPI()
        sampleNetwork(api)
        let router = AppRouter(selectedTool: .ping)
        let model = makeWhoisModel(api: api, router: router)
        router.open(.whois, target: "8.8.8.8", autostart: true)
        model.consumeRouterRequest()
        #expect(model.targetText == "8.8.8.8")
        #expect(await waitUntil { loaded(model) != nil })

        router.open(.whois, target: "AS13335", autostart: false)
        model.consumeRouterRequest()
        #expect(model.targetText == "AS13335")
        #expect(loaded(model)?.subject == .address(ip("8.8.8.8"), hostname: nil))
    }

    @Test func pingTraceAndMapOpenTheOtherTools() async {
        let api = WhoisFakeAPI()
        sampleNetwork(api, ip: "17.253.144.10", prefix: "17.253.0.0/16", origins: [714])
        let router = AppRouter(selectedTool: .whois)
        let model = makeWhoisModel(api: api, router: router, resolve: resolver("17.253.144.10", host: "apple.com"))
        model.lookUp("apple.com")
        #expect(await waitUntil { loaded(model) != nil })

        model.ping()
        #expect(router.selectedTool == .ping)
        #expect(router.takeRequest(for: .ping) == ToolRequest(target: "apple.com", autostart: true))
        model.trace()
        #expect(router.takeRequest(for: .traceroute) == ToolRequest(target: "apple.com", autostart: true))
        model.map()
        #expect(router.takeRequest(for: .bgp) == ToolRequest(target: "17.253.144.10", autostart: true))
    }

    @Test func mapForPrefixAndASUsesTheResource() async {
        let api = WhoisFakeAPI()
        api.whoisByResource["1.1.1.0/24"] = objectResponse("1.1.1.0/24")
        api.overviewByPrefix["1.1.1.0/24"] = PrefixOverview(resource: "1.1.1.0/24", announced: true, origins: [])
        let router = AppRouter(selectedTool: .whois)
        let model = makeWhoisModel(api: api, router: router)
        model.lookUp("1.1.1.0/24")
        #expect(await waitUntil { loaded(model) != nil })
        model.map()
        #expect(router.takeRequest(for: .bgp)?.target == "1.1.1.0/24")
        model.ping()
        #expect(router.takeRequest(for: .ping) == nil)
    }

    @Test func pingFromALocalCardUsesTheTypedInput() {
        let router = AppRouter(selectedTool: .whois)
        let model = makeWhoisModel(api: WhoisFakeAPI(), router: router)
        model.lookUp("192.168.1.1")
        model.ping()
        #expect(router.takeRequest(for: .ping)?.target == "192.168.1.1")
    }

    // MARK: Background

    @Test func backgroundStopsALoadingLookup() async {
        let api = WhoisFakeAPI()
        sampleNetwork(api)
        api.delay = .seconds(5)
        let model = makeWhoisModel(api: api)
        model.lookUp("8.8.8.8")
        model.stopForBackground()
        #expect(model.phase == .failed(.backgrounded))
    }

    @Test func backgroundStopsResolving() async {
        let model = makeWhoisModel(api: WhoisFakeAPI(), resolve: { host, _ in
            try await Task.sleep(for: .seconds(5))
            throw NetError.resolutionFailed(host: host, reason: "slow")
        })
        model.lookUp("apple.com")
        model.stopForBackground()
        #expect(model.phase == .failed(.backgrounded))
    }

    @Test func backgroundKeepsAShownResult() async {
        let api = WhoisFakeAPI()
        sampleNetwork(api)
        let model = makeWhoisModel(api: api)
        model.lookUp("8.8.8.8")
        #expect(await waitUntil { loaded(model) != nil })
        model.stopForBackground()
        #expect(loaded(model) != nil)
    }

    // MARK: Export

    @Test func exportsFollowThePhase() async {
        let api = WhoisFakeAPI()
        sampleNetwork(api, origins: [])
        let model = makeWhoisModel(api: api)
        #expect(model.exportText.isEmpty)
        model.lookUp("8.8.8.8")
        #expect(await waitUntil { loaded(model) != nil })
        #expect(model.exportText.hasPrefix("WHOIS 8.8.8.8 (rev.example)"))
        #expect(model.exportFullText.contains("NetRange:"))
    }
}
