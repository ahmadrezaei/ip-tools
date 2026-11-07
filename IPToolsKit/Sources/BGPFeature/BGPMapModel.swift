// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import BGPGraph
import Foundation
import NetCore
import Observation
import RIPEstat
import SharedUI

@MainActor @Observable public final class BGPMapModel {
    public enum Phase: Equatable { case idle, loading(String), pickingPrefix(asn: UInt32, holder: String?, prefixes: [String]), loaded, failed(String) }
    public enum DisplayMode: Sendable { case graph, list }

    public var targetText: String = ""
    public var maxNodesPerLayer: Int = 6        // 6 / 12 / 30 -> rebuilds graph + layout off-main
    public var selection: NodeID?
    public var displayMode: DisplayMode = .graph
    public private(set) var phase: Phase = .idle
    public private(set) var result: BGPResult?
    public private(set) var layout: GraphLayout?

    @ObservationIgnored let api: any RIPEstatAPI
    @ObservationIgnored let recents: RecentsStore
    @ObservationIgnored let router: AppRouter
    public var recentsStore: RecentsStore { recents }

    public init(api: any RIPEstatAPI, recents: RecentsStore, router: AppRouter) {
        self.api = api
        self.recents = recents
        self.router = router
    }

    /// Stub: UI agent implements. Parses targetText -> BGPQuery -> fetch.
    public func map() {}
    /// Stub: UI agent implements.
    public func choosePrefix(_ prefix: String) {}
    /// Stub: UI agent implements.
    public func cancel() {}

    /// Stub: UI agent implements (format in DESIGN §6.10).
    public var exportText: String { BGPExport.text(result: result) }
}
