// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore

public enum WhoisSubject: Hashable, Sendable {
    case address(IPAddress, hostname: String?)
    case prefix(IPAddress, length: Int)
    case asn(UInt32)

    /// "8.8.8.8", "1.1.1.0/24", "AS13335"
    public var resource: String {
        switch self {
        case let .address(address, _): address.description
        case let .prefix(address, length): "\(address)/\(length)"
        case let .asn(number): "AS\(number)"
        }
    }

    /// Ping/Traceroute buttons.
    public var canProbe: Bool {
        if case .address = self { return true }
        return false
    }
}
