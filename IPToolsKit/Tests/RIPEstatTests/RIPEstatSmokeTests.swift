// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import Testing
@testable import RIPEstat

@Suite struct RIPEstatSmokeTests {
    @Test func shortNames() {
        #expect(ASName.short("CLOUDFLARENET - Cloudflare, Inc.") == "Cloudflare")
        #expect(ASName.short("GCORE G-Core Labs S.A.") == "G-Core Labs")
        #expect(ASName.short("HURRICANE - Hurricane Electric LLC") == "Hurricane Electric")
        #expect(ASName.short("TWELVE99 Arelion Sweden AB") == "Arelion Sweden")
    }

    @Test func fixturesAreBundled() {
        #expect(Bundle.module.url(forResource: "Fixtures", withExtension: nil) != nil)
    }
}
