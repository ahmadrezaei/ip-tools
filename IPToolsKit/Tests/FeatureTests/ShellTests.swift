// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import Testing
import NetCore
import RIPEstat
import SharedUI
@testable import AppShell

@Suite @MainActor struct ShellTests {
    @Test func previewEnvironmentSharesOneRouter() async {
        let env = AppEnvironment.preview()
        env.recents.clear()
        env.router.open(.ping, target: "1.1.1.1", autostart: false)
        env.ping.consumePendingRequest()
        #expect(env.ping.targetText == "1.1.1.1")
        env.router.open(.traceroute, target: "8.8.8.8", autostart: false)
        env.trace.consumePendingRequest()
        #expect(env.trace.targetText == "8.8.8.8")
    }

    @Test func pingRunsAgainstPreviewMocks() async {
        let env = AppEnvironment.preview()
        env.recents.clear()
        env.settings.ping.count = 2
        env.ping.targetText = "1.1.1.1"
        env.ping.start()
        #expect(await waitUntil { env.ping.phase == .finished })
        #expect(env.ping.samples.count == 2)
        #expect(env.recents.items.first?.display == "1.1.1.1")
        env.recents.clear()
    }

    @Test func recentWhoisReopensWhoisWithoutAutostart() {
        let env = AppEnvironment.preview()
        env.recents.clear()
        env.recents.record("8.8.8.8", tool: .whois)
        let item = env.recents.items[0]
        #expect(item.lastTool == .whois)
        env.router.open(item.lastTool, target: item.display, autostart: false)
        #expect(env.router.selectedTool == .whois)
        #expect(env.router.takeRequest(for: .whois) == ToolRequest(target: "8.8.8.8", autostart: false))
        env.recents.clear()
    }

    @Test func aboutHasVersion() {
        #expect(!AboutSections.versionString.isEmpty)
        #expect(AboutSections.repositoryURL.absoluteString == "https://github.com/ahmadrezaei/ip-tools")
    }

    @Test func previewTraceScriptIsTheGoogleTrace() async {
        let env = AppEnvironment.preview()
        env.recents.clear()
        env.settings.trace.lookUpASNs = false
        env.settings.trace.resolveHostnames = false
        env.trace.targetText = "8.8.8.8"
        env.trace.start()
        #expect(await waitUntil(timeout: .seconds(15)) { if case .finished = env.trace.phase { true } else { false } })
        #expect(env.trace.hops.count == 11)
        #expect(env.trace.hops[9].isSilent)
        #expect(env.trace.hops[10].isDestination)
        #expect(env.trace.snapshot()?.hops.count == 11)
        env.bgp.stopForBackground()
        env.recents.clear()
    }
}

#if DEBUG
@Suite struct ScreenshotModeTests {
    @Test func parsesArguments() {
        let m = ScreenshotMode(arguments: ["app", "-screenshotTool", "bgp", "-screenshotTarget", "1.1.1.1",
                                           "-screenshotExpandHeader", "YES", "-screenshotPingCount", "5"])
        #expect(m?.tool == .bgp)
        #expect(m?.target == "1.1.1.1")
        #expect(m?.expandHeader == true)
        #expect(m?.pingCount == 5)
    }

    @Test func whoisToolWithAndWithoutTarget() {
        let withTarget = ScreenshotMode(arguments: ["app", "-screenshotTool", "whois", "-screenshotTarget", "AS3333"])
        #expect(withTarget?.tool == .whois)
        #expect(withTarget?.target == "AS3333")
        let empty = ScreenshotMode(arguments: ["app", "-screenshotTool", "WHOIS", "-screenshotTarget", ""])
        #expect(empty?.tool == .whois)
        #expect(empty?.target == nil)
    }

    @Test func fixedMyIPNeverCallsTheRealClient() async throws {
        let base = CountingAPI()
        let api = ScreenshotMyIPAPI(base: base)
        #expect(try await api.whatsMyIP(over: .v4).ip == "193.0.6.139")
        #expect(try await api.whatsMyIP(over: .v6).ip == "2001:67c:2e8:22::c100:696")
        #expect(try await api.whatsMyIP().ip == "193.0.6.139")
        #expect(base.whatsMyIPCalls == 0)
        // everything else is forwarded
        _ = try? await api.networkInfo("1.1.1.1")
        _ = try? await api.prefixOverview("1.1.1.0/24")
        _ = try? await api.lookingGlass("1.1.1.1")
        _ = try? await api.asOverview(13335)
        _ = try? await api.asNames([13335])
        _ = try? await api.announcedPrefixes(13335)
        _ = try? await api.routingStatus("1.1.1.0/24")
        _ = try? await api.whois("1.1.1.1")
        _ = try? await api.abuseContacts("1.1.1.1")
        _ = try? await api.registeredCountry("1.1.1.1")
        _ = try? await api.geolocation("1.1.1.1")
        #expect(base.forwarded == 11)
        #expect(base.whatsMyIPCalls == 0)
    }

    @Test func absentOrInvalidToolIsNil() {
        #expect(ScreenshotMode(arguments: ["app"]) == nil)
        #expect(ScreenshotMode(arguments: ["app", "-screenshotTool", "nope"]) == nil)
        #expect(ScreenshotMode(arguments: ["app", "-screenshotTool"]) == nil)
    }
}

/// RIPEstat stand-in that counts calls: `whatsMyIP` separately from everything else, which always fails.
private final class CountingAPI: RIPEstatAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var _whatsMyIP = 0, _forwarded = 0
    var whatsMyIPCalls: Int { lock.withLock { _whatsMyIP } }
    var forwarded: Int { lock.withLock { _forwarded } }

    private func forward<T>() throws -> T {
        lock.withLock { _forwarded += 1 }
        throw RIPEstatError.offline
    }

    func whatsMyIP() async throws -> WhatsMyIP { lock.withLock { _whatsMyIP += 1 }; throw RIPEstatError.offline }
    func whatsMyIP(over version: IPVersion) async throws -> WhatsMyIP { lock.withLock { _whatsMyIP += 1 }; throw RIPEstatError.offline }
    func networkInfo(_ ip: String) async throws -> NetworkInfo { try forward() }
    func prefixOverview(_ prefix: String) async throws -> PrefixOverview { try forward() }
    func lookingGlass(_ resource: String) async throws -> LookingGlass { try forward() }
    func asOverview(_ asn: UInt32) async throws -> ASOverview { try forward() }
    func asNames(_ asns: [UInt32]) async throws -> [UInt32: String] { try forward() }
    func announcedPrefixes(_ asn: UInt32) async throws -> [String] { try forward() }
    func routingStatus(_ prefix: String) async throws -> RoutingStatus { try forward() }
    func whois(_ resource: String) async throws -> WhoisResponse { try forward() }
    func abuseContacts(_ resource: String) async throws -> AbuseContacts { try forward() }
    func registeredCountry(_ resource: String) async throws -> String? { try forward() }
    func geolocation(_ ip: String) async throws -> GeoLocation? { try forward() }
}
#endif
