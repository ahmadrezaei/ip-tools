// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Network
import Observation

@MainActor @Observable public final class NetworkMonitor {
    public private(set) var isOnline: Bool = true
    /// +1 whenever interface types, status or gateways change.
    public private(set) var pathGeneration: Int = 0
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var lastSignature: PathSignature?

    /// What counts as "the network changed": status, interface types and gateways.
    struct PathSignature: Hashable, Sendable {
        var isSatisfied: Bool
        var interfaceTypes: [String]
        var gateways: [String]

        init(isSatisfied: Bool, interfaceTypes: [String], gateways: [String]) {
            self.isSatisfied = isSatisfied
            self.interfaceTypes = interfaceTypes.sorted()
            self.gateways = gateways.sorted()
        }

        init(_ path: NWPath) {
            self.init(isSatisfied: path.status == .satisfied,
                      interfaceTypes: path.availableInterfaces.map { "\($0.type)" },
                      gateways: path.gateways.map { "\($0)" })
        }
    }

    /// NWPathMonitor on a private queue.
    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let signature = PathSignature(path)
            Task { @MainActor in
                self?.isOnline = online
                self?.apply(signature)
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.ahmadrezaei.iptools.network-monitor"))
    }

    /// The first signature is the baseline; every later difference bumps `pathGeneration`.
    func apply(_ signature: PathSignature) {
        defer { lastSignature = signature }
        guard let lastSignature, lastSignature != signature else { return }
        pathGeneration += 1
    }

    deinit { monitor.cancel() }
}
