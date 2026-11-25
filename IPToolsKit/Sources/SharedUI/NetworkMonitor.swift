// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore
import Network
import Observation

@MainActor @Observable public final class NetworkMonitor {
    public private(set) var isOnline: Bool = true
    /// +1 whenever the status, interfaces, gateways or local IPv4 addresses change. Repeated updates for the same
    /// network do not count: iOS sends them often, and the app's own requests can cause them.
    public private(set) var pathGeneration: Int = 0
    /// `NWPath.supportsIPv4` of the latest path.
    public private(set) var supportsIPv4: Bool = true
    /// `NWPath.supportsIPv6` of the latest path.
    public private(set) var supportsIPv6: Bool = true
    /// `NWPath.usesInterfaceType(.other)` while the path is satisfied.
    public private(set) var usesVPN: Bool = false
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var lastSignature: PathSignature?

    /// What counts as "the network changed": status, interface types, gateways and the local IPv4 addresses of
    /// the Wi-Fi, cellular and wired interfaces the path uses (so two Wi-Fi networks behind the same gateway address still differ).
    /// IPv6 addresses are left out because temporary addresses rotate on the same network.
    struct PathSignature: Hashable, Sendable {
        var isSatisfied: Bool
        var interfaceTypes: [String]
        var gateways: [String]
        var addresses: [String]

        init(isSatisfied: Bool, interfaceTypes: [String], gateways: [String], addresses: [String] = []) {
            self.isSatisfied = isSatisfied
            self.interfaceTypes = interfaceTypes.sorted()
            self.gateways = gateways.sorted()
            self.addresses = addresses.sorted()
        }

        init(_ path: NWPath, local: [LocalAddress]) {
            let physical: Set<LocalAddress.Interface> = [.wifi, .cellular, .wired]
            let inUse = Set(path.availableInterfaces.map(\.name))
            self.init(isSatisfied: path.status == .satisfied,
                      interfaceTypes: path.availableInterfaces.map { "\($0.type)" },
                      gateways: path.gateways.map { "\($0)" },
                      addresses: local.filter {
                          physical.contains($0.interface) && inUse.contains($0.name) && $0.address.family == .v4
                      }.map { "\($0.name)|\($0.address)" })
        }
    }

    /// NWPathMonitor on a private queue.
    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let signature = PathSignature(path, local: LocalInterfaces.current())
            let v4 = path.supportsIPv4, v6 = path.supportsIPv6
            let vpn = online && path.usesInterfaceType(.other)
            Task { @MainActor in
                self?.isOnline = online
                self?.supportsIPv4 = v4
                self?.supportsIPv6 = v6
                self?.usesVPN = vpn
                self?.apply(signature)
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.ahmadrezaei.iptools.network-monitor"))
    }

    /// The first update is the baseline. Later, only a changed signature bumps `pathGeneration`.
    func apply(_ signature: PathSignature) {
        let previous = lastSignature
        lastSignature = signature
        guard let previous, previous != signature else { return }
        pathGeneration += 1
    }

    deinit { monitor.cancel() }
}
