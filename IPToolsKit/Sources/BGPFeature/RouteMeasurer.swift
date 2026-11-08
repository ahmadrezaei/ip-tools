// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import BGPGraph
import Foundation
import NetCore
import RIPEstat

/// DESIGN 6.11.5.
struct RouteMeasurer: Sendable {
    enum Update: Sendable { case hops([ChainHop]), finished(reachedOrigin: Bool), failed(Error) }
    init(service: any TraceService, api: any RIPEstatAPI) {}
    func measure(_ target: ResolvedTarget, origins: Set<UInt32>, prefixTarget: Bool) -> AsyncStream<Update> {
        fatalError("TODO")
    }
}
