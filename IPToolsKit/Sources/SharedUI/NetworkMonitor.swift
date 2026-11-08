// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import Network
import Observation

@MainActor @Observable public final class NetworkMonitor {
    public private(set) var isOnline: Bool = true
    /// +1 on every satisfied path update (so Wi-Fi to Wi-Fi switches count) and whenever the status or interfaces change.
    public private(set) var pathGeneration: Int = 0
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var lastSignature: PathSignature?
    @ObservationIgnored private var lastUpdate: Date?

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

    /// The first update is the baseline. Later, every satisfied update bumps `pathGeneration`, and so does any
    /// signature change; identical consecutive updates within one second are treated as duplicates.
    func apply(_ signature: PathSignature, now: Date = Date()) {
        let previous = lastSignature
        let previousTime = lastUpdate
        lastSignature = signature
        lastUpdate = now
        guard let previous else { return }
        let duplicate = previous == signature && previousTime.map { now.timeIntervalSince($0) < 1 } == true
        guard !duplicate, signature.isSatisfied || previous != signature else { return }
        pathGeneration += 1
    }

    deinit { monitor.cancel() }
}
