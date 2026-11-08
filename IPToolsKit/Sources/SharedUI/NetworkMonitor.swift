// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Network
import Observation

@MainActor @Observable public final class NetworkMonitor {
    public private(set) var isOnline: Bool = true
    /// +1 whenever interface types, status or gateways change.
    public private(set) var pathGeneration: Int = 0
    @ObservationIgnored private let monitor = NWPathMonitor()

    /// NWPathMonitor on a private queue.
    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "com.ahmadrezaei.iptools.network-monitor"))
    }

    deinit { monitor.cancel() }
}
