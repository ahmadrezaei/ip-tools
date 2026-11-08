// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import Testing
import NetCore
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

    @Test func absentOrInvalidToolIsNil() {
        #expect(ScreenshotMode(arguments: ["app"]) == nil)
        #expect(ScreenshotMode(arguments: ["app", "-screenshotTool", "nope"]) == nil)
        #expect(ScreenshotMode(arguments: ["app", "-screenshotTool"]) == nil)
    }
}
#endif
