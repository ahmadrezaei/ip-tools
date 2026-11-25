// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore
import RIPEstat
import SharedUI
import Testing
@testable import WhoisFeature

@Suite @MainActor struct WhoisMyIPModelTests {
    private let v4 = "193.0.6.139"
    private let v6 = "2001:67c:2e8:22::c100:696"

    private func api(v4Result: Result<String, any Error>? = nil, v6Result: Result<String, any Error>? = nil) -> WhoisFakeAPI {
        let api = WhoisFakeAPI()
        api.publicIP = [.v4: v4Result ?? .success(v4), .v6: v6Result ?? .success(v6)]
        sampleNetwork(api, ip: v4, prefix: "193.0.0.0/21", origins: [])
        sampleNetwork(api, ip: v6, prefix: "2001:67c:2e8::/48", origins: [])
        return api
    }

    private func isLoaded(_ model: WhoisModel, _ version: IPVersion) -> Bool {
        if case .loaded? = model.myWhois[version] { true } else { false }
    }

    /// The snapshot is complete and the selected family's whois has loaded.
    private func settled(_ model: WhoisModel) async -> Bool {
        await waitUntil {
            guard let snapshot = model.myIP, !snapshot.isChecking else { return false }
            return snapshot.address(model.myFamily) == nil || isLoaded(model, model.myFamily)
        }
    }

    @Test func bothFamiliesFoundSelectsIPv4AndLoadsItsWhois() async {
        let api = api()
        let model = makeWhoisModel(api: api)
        model.appeared()
        #expect(await settled(model))
        #expect(model.myFamily == .v4)
        #expect(model.myIP?.address(.v4) == ip(v4))
        #expect(model.myIP?.address(.v6) == ip(v6))
        #expect(api.calls("whois:") == ["whois:\(v4)"])
        #expect(model.myWhois[.v6] == nil)
    }

    @Test func switchingFamilyLoadsTheOtherWhoisOnce() async {
        let api = api()
        let model = makeWhoisModel(api: api)
        model.appeared()
        #expect(await settled(model))
        model.myFamily = .v6
        #expect(await waitUntil { isLoaded(model, .v6) })
        model.myFamily = .v4
        model.myFamily = .v6
        #expect(api.calls("whois:") == ["whois:\(v4)", "whois:\(v6)"])
    }

    @Test func ipv4OnlyNetworkSkipsTheIPv6Request() async {
        let api = api()
        let box = NetworkBox()
        box.state.supportsIPv6 = false
        let model = makeWhoisModel(api: api, network: box)
        model.appeared()
        #expect(await settled(model))
        #expect(model.myIP?.v6 == .unavailable(.noRoute))
        #expect(api.calls("my-ip:") == ["my-ip:v4"])
    }

    @Test func ipv6OnlyNetworkSelectsIPv6() async {
        let api = api(v4Result: .failure(PublicIPError.noRoute(.v4)))
        let model = makeWhoisModel(api: api)
        model.appeared()
        #expect(await settled(model))
        #expect(model.myIP?.v4 == .unavailable(.ipv6OnlyNetwork))
        #expect(model.myFamily == .v6)
        #expect(api.calls("whois:") == ["whois:\(v6)"])
    }

    @Test func oneFailedRowKeepsTheOther() async {
        let api = api(v6Result: .failure(PublicIPError.timeout(.v6)))
        let model = makeWhoisModel(api: api)
        model.appeared()
        #expect(await settled(model))
        guard case .failed? = model.myIP?.v6 else { Issue.record("expected failed row"); return }
        #expect(model.myFamily == .v4)
    }

    @Test func bothFailedShowsNoWhoisAndNoLookup() async {
        let failure: Result<String, any Error> = .failure(PublicIPError.tls)
        let api = api(v4Result: failure, v6Result: failure)
        let model = makeWhoisModel(api: api)
        model.appeared()
        #expect(await waitUntil { model.myIP?.bothFailed == true })
        #expect(api.calls("whois:").isEmpty)
        #expect(model.myWhois.isEmpty)
    }

    @Test func offlineMakesNoRequest() {
        let api = api()
        let box = NetworkBox()
        box.state.online = false
        let model = makeWhoisModel(api: api, network: box)
        model.appeared()
        #expect(model.myIP?.v4 == .unavailable(.offline))
        #expect(model.myIP?.v6 == .unavailable(.offline))
        #expect(api.calls.isEmpty)
    }

    @Test func appearingAgainDoesNotRefetchUntilTheNetworkChanges() async {
        let api = api()
        let box = NetworkBox()
        let model = makeWhoisModel(api: api, network: box)
        model.appeared()
        #expect(await settled(model))
        let count = api.calls("my-ip:").count
        model.appeared()
        model.appeared()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(api.calls("my-ip:").count == count)

        box.state.generation = 1
        model.appeared()
        #expect(await waitUntil { api.calls("my-ip:").count == count * 2 })
    }

    @Test func refreshForcesANewCheck() async {
        let api = api()
        let model = makeWhoisModel(api: api)
        model.appeared()
        #expect(await settled(model))
        await model.refreshMyIPAndWait()
        #expect(api.calls("my-ip:").count == 4)
        #expect(await settled(model))
    }

    @Test func networkChangeIsDebouncedAndOnlyWhileVisible() async {
        let api = api()
        let box = NetworkBox()
        let model = makeWhoisModel(api: api, network: box)
        model.appeared()
        #expect(await settled(model))
        let count = api.calls("my-ip:").count

        model.disappeared()
        box.state.generation = 1
        model.pathGenerationChanged()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(api.calls("my-ip:").count == count)

        // Coming back notices the missed change by itself.
        model.appeared()
        #expect(await waitUntil { api.calls("my-ip:").count == count * 2 })
        #expect(await settled(model))

        box.state.generation = 2
        model.pathGenerationChanged()
        model.pathGenerationChanged()
        model.pathGenerationChanged()
        try? await Task.sleep(for: .milliseconds(250))
        #expect(api.calls("my-ip:").count == count * 3)
    }

    @Test func defaultFamilyResetsOnANewNetwork() async {
        let api = api()
        let box = NetworkBox()
        let model = makeWhoisModel(api: api, network: box)
        model.appeared()
        #expect(await settled(model))
        model.myFamily = .v6
        #expect(await settled(model))
        box.state.generation = 1
        model.appeared()
        #expect(await waitUntil { model.myIP?.generation == 1 && model.myIP?.isChecking == false })
        #expect(model.myFamily == .v4)
    }

    @Test func aChosenFamilySurvivesARefreshOnTheSameNetwork() async {
        let api = api()
        let model = makeWhoisModel(api: api)
        model.appeared()
        #expect(await settled(model))
        model.myFamily = .v6
        await model.refreshMyIPAndWait()
        #expect(model.myFamily == .v6)
    }

    @Test func retryReloadsAFailedOwnWhois() async {
        let api = api()
        api.failing = ["whois", "network-info"]
        let model = makeWhoisModel(api: api)
        model.appeared()
        #expect(await waitUntil { if case .failed? = model.myWhois[.v4] { true } else { false } })
        api.failing = []
        model.retryMyWhois()
        #expect(await waitUntil { isLoaded(model, .v4) })
    }

    @Test func myIPNeverRecords() async {
        let recents = makeRecents()
        let model = makeWhoisModel(api: api(), recents: recents)
        model.appeared()
        #expect(await settled(model))
        #expect(recents.items.isEmpty)
    }

    @Test func mapForOwnAddressOpensBGP() async {
        let router = AppRouter(selectedTool: .whois)
        let model = makeWhoisModel(api: api(), router: router)
        model.appeared()
        #expect(await settled(model))
        model.mapMyIP(.v6)
        #expect(router.takeRequest(for: .bgp)?.target == v6)
    }

    @Test func backgroundTurnsWaitingStatesIntoRetryableFailures() async {
        let api = api()
        api.delay = .seconds(5)
        let model = makeWhoisModel(api: api)
        model.appeared()
        #expect(await waitUntil { model.myIP != nil })
        model.stopForBackground()
        guard case .failed? = model.myIP?.v4, case .failed? = model.myIP?.v6 else { Issue.record("slots should fail"); return }
        try? await Task.sleep(for: .milliseconds(100))
        guard case .failed? = model.myIP?.v4 else { Issue.record("slots should stay failed"); return }
    }

    @Test func backgroundStopsAnOwnWhoisThatIsLoading() async {
        let api = api()
        let model = makeWhoisModel(api: api)
        model.appeared()
        #expect(await settled(model))
        api.delay = .seconds(5)
        model.myFamily = .v6
        #expect(await waitUntil { model.myWhois[.v6] == .loading })
        model.stopForBackground()
        #expect(model.myWhois[.v6] == .failed(.backgrounded))
    }

    @Test func myIPExportListsBothAddressesAndTheNetwork() async {
        let model = makeWhoisModel(api: api())
        model.appeared()
        #expect(await settled(model))
        let text = model.exportText
        #expect(text.hasPrefix("My public IP — "))
        #expect(text.contains("IPv4  \(v4)"))
        #expect(text.contains("IPv6  \(v6)"))
        #expect(text.hasSuffix("— IP Tools for iOS"))
    }

    @Test func returningFromBackgroundReloadsWhatWasStopped() async {
        let api = api()
        let model = makeWhoisModel(api: api)
        model.appeared()
        #expect(await settled(model))
        api.delay = .seconds(5)
        model.myFamily = .v6
        #expect(await waitUntil { model.myWhois[.v6] == .loading })
        model.stopForBackground()
        api.delay = nil
        model.resumeFromBackground()
        #expect(await waitUntil { isLoaded(model, .v6) })
    }

    @Test func returningFromBackgroundRechecksFailedRows() async {
        let api = api()
        api.delay = .seconds(5)
        let model = makeWhoisModel(api: api)
        model.appeared()
        #expect(await waitUntil { model.myIP != nil })
        model.stopForBackground()
        api.delay = nil
        model.resumeFromBackground()
        #expect(await waitUntil { model.myIP?.address(.v4) != nil && model.myIP?.address(.v6) != nil })
    }
}
