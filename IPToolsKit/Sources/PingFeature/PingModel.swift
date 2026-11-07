// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore
import Observation
import SharedUI

@MainActor @Observable public final class PingModel {
    public enum Phase: Equatable { case idle, resolving, running, finished, stopped(reason: String?), failed(String) }

    public var targetText: String = ""
    public private(set) var phase: Phase = .idle
    public private(set) var resolved: ResolvedTarget?
    public private(set) var samples: [PingSample] = []
    public private(set) var stats: PingStatistics = PingStatistics(samples: [PingSample]())

    @ObservationIgnored let service: any PingService
    @ObservationIgnored let settings: SettingsStore
    @ObservationIgnored let recents: RecentsStore
    public var recentsStore: RecentsStore { recents }

    public init(service: any PingService, settings: SettingsStore, recents: RecentsStore) {
        self.service = service
        self.settings = settings
        self.recents = recents
    }

    /// Stub: UI agent implements.
    public func start() {}
    /// Stub: UI agent implements.
    public func stop(reason: String? = nil) {}

    /// Stub: UI agent implements (format in DESIGN §4.6).
    public var exportText: String { PingExport.text(target: resolved, samples: samples, stats: stats) }
}
