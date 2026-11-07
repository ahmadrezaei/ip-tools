// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Testing
import NetCore
@testable import AppShell

@Suite @MainActor struct FeatureSmokeTests {
    @Test func previewEnvironmentBuilds() {
        let env = AppEnvironment.preview()
        #expect(env.ping.targetText.isEmpty)
    }

    @Test func mockPingEmitsScript() async throws {
        let ip = IPAddress("1.1.1.1")!
        let target = ResolvedTarget(input: "1.1.1.1", address: ip, hostname: nil, allAddresses: [ip])
        var options = PingOptions(); options.count = 2
        let service = MockPingService(script: [.timeout], interval: .milliseconds(1))
        var n = 0
        for try await _ in service.ping(target, options: options) { n += 1 }
        #expect(n == 2)
    }
}
