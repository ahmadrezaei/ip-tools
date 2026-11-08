// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import Testing
import NetCore
import SharedUI
@testable import PingFeature

@Suite @MainActor struct PingModelTests {
    let cloudflare = IPAddress("1.1.1.1")!

    private func makeModel(script: [PingSample.Outcome], count: Int? = 3, router: AppRouter? = nil,
                           resolve: PingModel.ResolveFunction? = nil) -> (PingModel, RecentsStore, SettingsStore) {
        let settings = makeSettings()
        settings.ping.count = count
        let recents = makeRecents()
        let service = MockPingService(script: script, interval: .milliseconds(2))
        let model: PingModel
        if let resolve {
            model = PingModel(service: service, settings: settings, recents: recents, router: router, resolve: resolve)
        } else {
            model = PingModel(service: service, settings: settings, recents: recents, router: router)
        }
        return (model, recents, settings)
    }

    @Test func runFinishesWithStatsAndRecordsRecent() async {
        let ip = cloudflare
        let (model, recents, _) = makeModel(script: [
            .reply(rtt: 0.0132, bytes: 64, ttl: 58, from: ip), .timeout, .reply(rtt: 0.0142, bytes: 64, ttl: 58, from: ip),
        ])
        model.targetText = " 1.1.1.1 "
        model.start()
        #expect(model.phase == .resolving || model.phase == .running)
        #expect(await waitUntil { model.phase == .finished })
        #expect(model.samples.map(\.sequence) == [0, 1, 2])
        #expect(model.stats.sent == 3)
        #expect(model.stats.received == 2)
        #expect(recents.items.map(\.display) == ["1.1.1.1"])
        #expect(recents.items.first?.lastTool == .ping)
        #expect(model.resolved?.address == ip)
    }

    @Test func invalidInputFailsWithoutResolvingOrRecording() async {
        let (model, recents, _) = makeModel(script: [.timeout], resolve: { _, _ in
            Issue.record("resolver must not be called")
            throw NetError.invalidTarget("x")
        })
        model.targetText = "not a host!"
        model.start()
        #expect(model.phase != .running)
        if case .failed = model.phase {} else { Issue.record("expected failed, got \(model.phase)") }
        #expect(model.error != nil)
        #expect(recents.items.isEmpty)
    }

    @Test func resolveFailureShowsErrorAndDoesNotRecord() async {
        let (model, recents, _) = makeModel(script: [.timeout], resolve: { input, _ in
            throw NetError.resolutionFailed(host: input, reason: "nope")
        })
        model.targetText = "apple.cmo"
        model.start()
        #expect(await waitUntil { if case .failed = model.phase { true } else { false } })
        #expect(model.error?.title.contains("apple.cmo") == true)
        #expect(model.samples.isEmpty)
        #expect(recents.items.isEmpty)
    }

    @Test func noAddressForFamilyMessage() async {
        let (model, _, _) = makeModel(script: [.timeout], resolve: { input, _ in
            throw NetError.noAddress(host: input, family: .v6)
        })
        model.targetText = "example.com"
        model.start()
        #expect(await waitUntil { model.error != nil })
        #expect(model.error?.title == "example.com has no IPv6 address")
    }

    @Test func stopKeepsResultsAndSetsReason() async {
        let ip = cloudflare
        let (model, _, _) = makeModel(script: [.reply(rtt: 0.01, bytes: 64, ttl: 58, from: ip)], count: nil)
        model.targetText = "1.1.1.1"
        model.start()
        #expect(await waitUntil { model.samples.count >= 2 })
        model.stop(reason: "because")
        #expect(model.phase == .stopped(reason: "because"))
        let count = model.samples.count
        try? await Task.sleep(for: .milliseconds(50))
        #expect(model.samples.count == count)
    }

    @Test func backgroundStopsRun() async {
        let ip = cloudflare
        let (model, _, _) = makeModel(script: [.reply(rtt: 0.01, bytes: 64, ttl: 58, from: ip)], count: nil)
        model.targetText = "1.1.1.1"
        model.start()
        #expect(await waitUntil { model.phase == .running })
        model.stopForBackground()
        #expect(model.phase == .stopped(reason: "app moved to background"))
    }

    @Test func stopWhileResolvingReturnsToIdle() async {
        let (model, recents, _) = makeModel(script: [.timeout], resolve: { input, _ in
            try await Task.sleep(for: .seconds(30))
            throw NetError.resolutionFailed(host: input, reason: "")
        })
        model.targetText = "slow.example"
        model.start()
        #expect(model.phase == .resolving)
        model.stop()
        #expect(model.phase == .idle)
        #expect(recents.items.isEmpty)
    }

    @Test func staleResolveFailureDoesNotAffectNewerRun() async {
        let ip = cloudflare
        let fastCalls = CallCounter()
        // Keyed on the input, not call order: the two run tasks may start in either order.
        let (model, _, _) = makeModel(script: [.reply(rtt: 0.01, bytes: 64, ttl: 58, from: ip)], count: nil, resolve: { input, _ in
            if input == "slow.example" {
                try? await Task.sleep(for: .milliseconds(150))   // ignores cancellation, then fails late
                throw NetError.resolutionFailed(host: input, reason: "late")
            }
            _ = fastCalls.next()
            return ResolvedTarget(input: input, address: ip, hostname: nil, allAddresses: [ip])
        })
        model.targetText = "slow.example"
        model.start()
        model.stop()
        model.targetText = "1.1.1.1"
        model.start()
        try? await Task.sleep(for: .milliseconds(300))
        #expect(model.error == nil)
        if case .failed = model.phase { Issue.record("stale failure leaked: \(model.phase)") }
        #expect(fastCalls.next() >= 2)   // newer run's resolver was invoked
        #expect(model.runTarget == "1.1.1.1")
        model.stop()
    }

    @Test func pendingRecentOnlyPrefillsWhileBusy() async {
        let ip = cloudflare
        let router = AppRouter()
        let (model, _, _) = makeModel(script: [.reply(rtt: 0.01, bytes: 64, ttl: 58, from: ip)], count: nil, router: router)
        model.targetText = "1.1.1.1"
        model.start()
        #expect(await waitUntil { model.phase == .running })
        router.open(.ping, target: "8.8.8.8", autostart: false)
        model.consumePendingRequest()
        #expect(model.phase == .running)
        #expect(model.targetText == "1.1.1.1")
        model.stop()
    }

    @Test func startIsIgnoredWhileRunning() async {
        let ip = cloudflare
        let (model, _, _) = makeModel(script: [.reply(rtt: 0.01, bytes: 64, ttl: 58, from: ip)], count: nil)
        model.targetText = "1.1.1.1"
        model.start()
        #expect(await waitUntil { model.phase == .running })
        model.targetText = "8.8.8.8"
        model.start()
        #expect(model.resolved?.address == ip)
        model.stop()
    }

    @Test func ipv6PayloadIsClamped() async {
        let v6 = IPAddress("2606:4700:4700::1111")!
        let (model, _, settings) = makeModel(script: [.timeout], count: 1, resolve: { input, _ in
            ResolvedTarget(input: input, address: v6, hostname: input, allAddresses: [v6])
        })
        settings.ping.payloadSize = 1472
        model.targetText = "one.one.one.one"
        model.start()
        #expect(await waitUntil { model.phase == .finished })
        #expect(model.payloadSize == 1452)
    }

    @Test func routerRequestPrefillsOrAutostarts() async {
        let router = AppRouter()
        let ip = cloudflare
        let (model, _, _) = makeModel(script: [.reply(rtt: 0.01, bytes: 64, ttl: 58, from: ip)], count: 1, router: router)
        router.open(.ping, target: "8.8.8.8", autostart: false)
        model.consumePendingRequest()
        #expect(model.targetText == "8.8.8.8")
        #expect(model.phase == .idle)

        router.open(.ping, target: "1.1.1.1", autostart: true)
        model.consumePendingRequest()
        #expect(model.targetText == "1.1.1.1")
        #expect(await waitUntil { model.phase == .finished })
        #expect(router.takeRequest(for: .ping) == nil)
    }

    @Test func mapInBGPOnlyForPublicAddresses() async {
        let router = AppRouter()
        let ip = cloudflare
        let (model, _, _) = makeModel(script: [.reply(rtt: 0.01, bytes: 64, ttl: 58, from: ip)], count: 1, router: router)
        model.targetText = "1.1.1.1"
        model.start()
        #expect(await waitUntil { model.phase == .finished })
        #expect(model.canMapInBGP)
        model.mapInBGP()
        #expect(router.selectedTool == .bgp)
        #expect(router.takeRequest(for: .bgp) == ToolRequest(target: "1.1.1.1", autostart: true))
    }

    @Test func samplesStaySortedBySequence() {
        let (model, _, _) = makeModel(script: [])
        let ip = cloudflare
        for sequence in [2, 0, 1, 1] {
            model.append(PingSample(sequence: sequence, sentAt: Date(), outcome: .reply(rtt: 0.01, bytes: 64, ttl: nil, from: ip)))
        }
        #expect(model.samples.map(\.sequence) == [0, 1, 2])
        #expect(model.stats.received == 3)
    }

    // MARK: Export

    @Test func exportMatchesSpecFormat() {
        let ip = cloudflare
        let samples = [
            PingSample(sequence: 0, sentAt: Date(), outcome: .reply(rtt: 0.0132, bytes: 64, ttl: 58, from: ip)),
            PingSample(sequence: 1, sentAt: Date(), outcome: .timeout),
            PingSample(sequence: 2, sentAt: Date(), outcome: .reply(rtt: 0.0142, bytes: 64, ttl: 58, from: ip)),
        ]
        let text = PingExport.text(target: resolvedTarget("1.1.1.1"), samples: samples,
                                   stats: PingStatistics(samples: samples), payloadSize: 56,
                                   date: utc("2026-11-07T12:34:00Z"))
        #expect(text == """
            PING 1.1.1.1 (1.1.1.1): 56 data bytes
            64 bytes from 1.1.1.1: icmp_seq=0 ttl=58 time=13.2 ms
            Request timeout for icmp_seq 1
            64 bytes from 1.1.1.1: icmp_seq=2 ttl=58 time=14.2 ms
            --- 1.1.1.1 ping statistics ---
            3 packets transmitted, 2 packets received, 33.3% packet loss
            round-trip min/avg/max/stddev = 13.2/13.7/14.2/0.5 ms, jitter 1.0 ms
            — IP Tools for iOS, 2026-11-07 12:34 UTC
            """)
    }

    @Test func exportWithHostnameAndNoReplies() {
        let samples = [PingSample(sequence: 0, sentAt: Date(), outcome: .timeout)]
        let text = PingExport.text(target: resolvedTarget("1.1.1.1", hostname: "one.one.one.one"), samples: samples,
                                   stats: PingStatistics(samples: samples), payloadSize: 120,
                                   date: utc("2026-11-07T12:34:00Z"))
        #expect(text == """
            PING one.one.one.one (1.1.1.1): 120 data bytes
            Request timeout for icmp_seq 0
            --- one.one.one.one ping statistics ---
            1 packets transmitted, 0 packets received, 100.0% packet loss
            — IP Tools for iOS, 2026-11-07 12:34 UTC
            """)
    }

    @Test func exportIsEmptyBeforeResults() {
        let (model, _, _) = makeModel(script: [])
        #expect(model.exportText.isEmpty)
    }

    @Test func chartNiceMax() {
        #expect(PingChart.niceMax(0) == 10)
        #expect(PingChart.niceMax(22.3) == 50)
        #expect(PingChart.niceMax(100) == 200)
        #expect(PingChart.niceMax(8) == 10)
    }

    // MARK: Count chip (DESIGN 4.3.1)

    @Test func customCountValidationIsOneToTenThousand() {
        #expect(PingCount.validated("1") == 1)
        #expect(PingCount.validated("10000") == 10_000)
        #expect(PingCount.validated(" 37 ") == 37)
        #expect(PingCount.validated("0") == nil)
        #expect(PingCount.validated("-5") == nil)
        #expect(PingCount.validated("10001") == nil)
        #expect(PingCount.validated("") == nil)
        #expect(PingCount.validated("1.5") == nil)
        #expect(PingCount.validated("abc") == nil)
        #expect(PingCount.exceedsLimit("10001"))
        #expect(!PingCount.exceedsLimit("10000"))
        #expect(!PingCount.exceedsLimit("abc"))
    }

    @Test func chipLabelsAndCustomRow() {
        #expect(PingCount.label(10) == "10 pings")
        #expect(PingCount.label(1) == "1 ping")
        #expect(PingCount.label(nil) == "Until stopped")
        #expect(PingCount.customValue(10) == nil)
        #expect(PingCount.customValue(nil) == nil)
        #expect(PingCount.customValue(37) == 37)
    }

    @Test func chipAndSettingsShareOneValue() async {
        let ip = cloudflare
        let (model, _, settings) = makeModel(script: [.reply(rtt: 0.01, bytes: 64, ttl: 58, from: ip)], count: 10)
        // The chip and the settings picker both write SettingsStore.ping.count.
        settings.ping.count = 37
        #expect(PingCount.customValue(model.settings.ping.count) == 37)
        model.settings.ping.count = nil
        #expect(settings.ping.count == nil)
        model.settings.ping.count = 2
        model.targetText = "1.1.1.1"
        model.start()
        #expect(await waitUntil { model.phase == .finished })
        #expect(model.samples.count == 2)
    }

    @Test func chipDisabledWhileRunningAndCountCapturedAtStart() async {
        let ip = cloudflare
        let (model, _, settings) = makeModel(script: [.reply(rtt: 0.01, bytes: 64, ttl: 58, from: ip)], count: 10)
        #expect(!model.isBusy)
        model.targetText = "1.1.1.1"
        model.start()
        #expect(model.isBusy)                       // PingView passes isDisabled: model.isBusy to the chip
        #expect(await waitUntil { model.phase == .running })
        #expect(model.isBusy)
        #expect(model.runCount == 10)
        settings.ping.count = 3                     // applies to the next Start only
        #expect(model.runCount == 10)
        model.stop()
        #expect(!model.isBusy)
    }

    @Test func headerShowsProgressAsThreeOfTen() {
        #expect(PingCount.progress(sent: 3, count: 10) == "3 of 10")
        #expect(PingCount.progress(sent: 3, count: nil) == "3 sent")
    }
}

final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func next() -> Int { lock.withLock { count += 1; return count } }
}
