// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Testing
@testable import BGPGraph

@Suite struct BGPGraphSmokeTests {
    @Test func builderStubDoesNotCrash() {
        let graph = GraphBuilder.build(from: [])
        #expect(graph.totalPaths == 0)
    }
}
