// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import Testing
import NetCore
@testable import SharedUI

@Suite @MainActor struct SharedUITests {
    @Test func routerHandsOverRequestOnce() {
        let router = AppRouter()
        let tick = router.requestTick
        router.open(.traceroute, target: "8.8.8.8", autostart: true)
        #expect(router.selectedTool == .traceroute)
        #expect(router.requestTick == tick + 1)
        #expect(router.takeRequest(for: .traceroute) == ToolRequest(target: "8.8.8.8", autostart: true))
        #expect(router.takeRequest(for: .traceroute) == nil)
        #expect(router.takeRequest(for: .ping) == nil)
    }

    @Test func recentsDeduplicateLimitAndPersist() {
        let name = "iptools.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = RecentsStore(defaults: defaults, limit: 3)
        store.record("Example.com", tool: .ping)
        store.record("1.1.1.1", tool: .ping)
        store.record("example.COM", tool: .traceroute)
        #expect(store.items.map(\.display) == ["example.COM", "1.1.1.1"])
        #expect(store.items.first?.lastTool == .traceroute)
        store.record("8.8.8.8", tool: .ping)
        store.record("9.9.9.9", tool: .ping)
        #expect(store.items.count == 3)
        #expect(store.items.first?.display == "9.9.9.9")
        #expect(RecentsStore(defaults: defaults, limit: 3).items.map(\.display) == store.items.map(\.display))
        #expect(store.suggestions(matching: "").count == 3)
        #expect(store.suggestions(matching: "8.8").map(\.display) == ["8.8.8.8"])
        store.remove(store.items[0])
        #expect(store.items.count == 2)
        store.clear()
        #expect(store.items.isEmpty)
    }

    @Test func recentsIgnoreBlank() {
        let store = RecentsStore(defaults: UserDefaults(suiteName: "iptools.tests.\(UUID().uuidString)")!)
        store.record("   ", tool: .ping)
        #expect(store.items.isEmpty)
    }

    @Test func targetValidation() {
        #expect(TargetValidation("", mode: .host) == .empty)
        #expect(TargetValidation("  ", mode: .host) == .empty)
        #expect(TargetValidation("1.1.1.1", mode: .host) == .valid)
        #expect(TargetValidation("example.com", mode: .host) == .valid)
        #expect(TargetValidation("https://example.com/x", mode: .host) == .valid)
        #expect(TargetValidation("bad host!", mode: .host) == .invalid)
        #expect(TargetValidation("13335", mode: .host) == .invalid)
        #expect(TargetValidation("AS13335", mode: .bgp) == .valid)
        #expect(TargetValidation("1.1.1.0/24", mode: .bgp) == .valid)
    }

    @Test func rttThresholds() {
        #expect(RTTColor.color(for: 0.0799) == .green)
        #expect(RTTColor.color(for: 0.080) == .orange)
        #expect(RTTColor.color(for: 0.199) == .orange)
        #expect(RTTColor.color(for: 0.200) == .red)
        #expect(RTTColor.color(for: nil) != .green)
        #expect(RTTColor.lossColor(0) == .primary)
        #expect(RTTColor.lossColor(0.05) == .orange)
        #expect(RTTColor.lossColor(0.5) == .red)
    }

    @Test func formatting() {
        #expect(Format.rtt(0.0136) == "13.6 ms")
        #expect(Format.rtt(0.136) == "136 ms")
        #expect(Format.rtt(1.5) == "1.50 s")
        #expect(Format.ms(0.0132) == "13.2")
        #expect(Format.percent(0.05) == "5%")
        #expect(Format.utcStamp(ISO8601DateFormatter().date(from: "2026-11-07T12:34:56Z")!) == "2026-11-07 12:34 UTC")
    }

    @Test func unreachableCodes() {
        #expect(UnreachableReason(code: 1, family: .v4) == .host)
        #expect(UnreachableReason(code: 0, family: .v4) == .network)
        #expect(UnreachableReason(code: 13, family: .v4) == .prohibited)
        #expect(UnreachableReason(code: 0, family: .v6) == .network)
        #expect(UnreachableReason(code: 1, family: .v6) == .prohibited)
        #expect(UnreachableReason(code: 3, family: .v6) == .host)
        #expect(UnreachableReason.host.flag == "!H")
        #expect(UnreachableReason.host.traceLabel == "!H host unreachable")
    }

    @Test func toolErrorMapping() {
        #expect(ToolError(.localNetworkDenied).action == .openSettings)
        #expect(ToolError(.resolutionFailed(host: "apple.cmo", reason: "")).title == "Couldn't Resolve apple.cmo")
        #expect(ToolError(.networkUnreachable(family: .v6)).message == "This network doesn't support IPv6.")
        #expect(ToolError.from(NetError.sendFailed(errno: 50)).action == .retry)
    }

    @Test func settingsPersist() {
        let name = "iptools.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults)
        #expect(settings.ping.count == 10)
        #expect(settings.trace.lookUpASNs)
        settings.ping.count = nil
        settings.trace.options.maxHops = 15
        settings.addressPreference = .ipv6
        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.ping.count == nil)
        #expect(reloaded.trace.options.maxHops == 15)
        #expect(reloaded.addressPreference == .ipv6)
    }

    @Test func settingsDecodingToleratesMissingFields() {
        let json = #"{"ping":{"count":5,"interval":2},"trace":{"options":{"maxHops":12},"lookUpASNs":false},"addressPreference":"ipv4"}"#
        let decoded = SettingsStore.decodeSnapshot(Data(json.utf8))
        #expect(decoded?.ping.count == 5)
        #expect(decoded?.ping.interval == 2)
        #expect(decoded?.ping.payloadSize == PingOptions.default.payloadSize)   // missing -> default
        #expect(decoded?.trace.options.maxHops == 12)
        #expect(decoded?.trace.options.probesPerHop == TraceOptions.default.probesPerHop)
        #expect(decoded?.trace.resolveHostnames == true)                         // missing -> default
        #expect(decoded?.trace.lookUpASNs == false)
        #expect(decoded?.addressPreference == .ipv4)
        let partial = SettingsStore.decodeSnapshot(Data(#"{"addressPreference":"ipv6"}"#.utf8))
        #expect(partial?.addressPreference == .ipv6)
        #expect(partial?.ping == PingOptions.default)
    }

    @Test func routerCarriesTraceSnapshot() {
        let router = AppRouter()
        let ip = IPAddress("8.8.8.8")!
        let target = ResolvedTarget(input: "8.8.8.8", address: ip, hostname: nil, allAddresses: [ip])
        let snapshot = TraceSnapshot(
            target: target,
            hops: [TraceSnapshot.Hop(ttl: 1, address: ip, hostname: nil, asn: 15169, rtts: [0.01], reachedTarget: true)],
            completion: .reachedDestination(hops: 1), finishedAt: Date(timeIntervalSince1970: 1_000))
        router.open(.bgp, target: "8.8.8.8", autostart: true, trace: snapshot)
        let request = router.takeRequest(for: .bgp)
        #expect(request?.trace == snapshot)
        #expect(request?.target == "8.8.8.8")
        router.open(.bgp, target: "8.8.8.8", autostart: true)
        #expect(router.takeRequest(for: .bgp)?.trace == nil)
    }

    @Test func pathGenerationBumpsOnRealChangeAndRejoin() {
        let monitor = NetworkMonitor()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let wifi = NetworkMonitor.PathSignature(isSatisfied: true, interfaceTypes: ["wifi"], gateways: ["192.168.1.1"])
        // Pin the baseline far in the past so the system's own first update cannot interfere.
        monitor.apply(wifi, now: t0)
        let base = monitor.pathGeneration
        monitor.apply(wifi, now: t0.addingTimeInterval(0.2))
        #expect(monitor.pathGeneration == base)
        // Identical signature later: another Wi-Fi network behind the same gateway.
        monitor.apply(wifi, now: t0.addingTimeInterval(30))
        #expect(monitor.pathGeneration == base + 1)
        monitor.apply(NetworkMonitor.PathSignature(isSatisfied: true, interfaceTypes: ["cellular"], gateways: []),
                      now: t0.addingTimeInterval(60))
        #expect(monitor.pathGeneration == base + 2)
        monitor.apply(NetworkMonitor.PathSignature(isSatisfied: false, interfaceTypes: [], gateways: []),
                      now: t0.addingTimeInterval(90))
        #expect(monitor.pathGeneration == base + 3)
        monitor.apply(NetworkMonitor.PathSignature(isSatisfied: false, interfaceTypes: [], gateways: []),
                      now: t0.addingTimeInterval(120))
        #expect(monitor.pathGeneration == base + 3)
    }
}
