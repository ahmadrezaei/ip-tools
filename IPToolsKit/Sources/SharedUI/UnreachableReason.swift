// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore

/// Human meaning of an ICMP / ICMPv6 Destination Unreachable code.
public enum UnreachableReason: Sendable, Equatable {
    case network, host, prohibited, port, other(UInt8)

    public init(code: UInt8, family: IPAddress.Family) {
        switch family {
        case .v4:
            switch code {
            case 0, 6: self = .network
            case 1, 7: self = .host
            case 3: self = .port
            case 9, 10, 13: self = .prohibited
            default: self = .other(code)
            }
        case .v6:
            switch code {
            case 0: self = .network
            case 1: self = .prohibited
            case 3: self = .host
            case 4: self = .port
            default: self = .other(code)
            }
        }
    }

    /// "host", "network", "port", "communication prohibited".
    public var noun: String {
        switch self {
        case .network: String(localized: "network")
        case .host: String(localized: "host")
        case .port: String(localized: "port")
        case .prohibited: String(localized: "communication prohibited")
        case .other(let code): String(localized: "code \(Int(code))")
        }
    }

    /// "Destination unreachable (host)"
    public var pingDescription: String {
        String(localized: "Destination unreachable (\(noun))")
    }

    /// short flag: "!N", "!H", "!S" (port), "!P" (prohibited).
    public var flag: String {
        switch self {
        case .network: "!N"
        case .host: "!H"
        case .port: "!S"
        case .prohibited: "!P"
        case .other(let code): "!<\(code)>"
        }
    }

    /// "!H host unreachable"
    public var traceLabel: String {
        switch self {
        case .network: String(localized: "!N net unreachable")
        case .host: String(localized: "!H host unreachable")
        case .port: String(localized: "!S port unreachable")
        case .prohibited: String(localized: "!P prohibited")
        case .other(let code): String(localized: "!<\(Int(code))> unreachable")
        }
    }
}
