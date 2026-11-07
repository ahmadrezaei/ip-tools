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
}
