// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore
import RIPEstat
import SharedUI

/// Why a lookup produced no result. Shown through `ErrorStateView`; mirrors `BGPFailure`.
public struct WhoisFailure: DisplayableError, Hashable, Sendable {
    public enum Kind: Hashable, Sendable { case busy, timeout, offline, notFound, unresolved, invalid, other }

    public let kind: Kind
    public let message: String

    public init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }

    public var title: String {
        switch kind {
        case .busy: String(localized: "RIPEstat is busy")
        case .timeout: String(localized: "No response")
        case .offline: String(localized: "You're offline")
        case .notFound: String(localized: "No Registry Record")
        case .unresolved: String(localized: "Host not found")
        case .invalid: String(localized: "Can't look that up")
        case .other: String(localized: "Something went wrong")
        }
    }

    public var systemImage: String {
        switch kind {
        case .busy: "hourglass"
        case .timeout: "clock.badge.exclamationmark"
        case .offline: "wifi.slash"
        case .notFound: "questionmark.folder"
        case .invalid, .unresolved: "questionmark.circle"
        case .other: "exclamationmark.triangle"
        }
    }

    public var action: ErrorAction? {
        switch kind {
        case .busy, .timeout, .offline, .other: .retry
        case .notFound, .unresolved, .invalid: nil
        }
    }

    static let busyFailure = WhoisFailure(kind: .busy, message: String(localized: "RIPEstat is busy. Try again in a moment."))
    static let timeoutFailure = WhoisFailure(kind: .timeout, message: String(localized: "RIPEstat didn't respond."))
    static let offlineFailure = WhoisFailure(kind: .offline, message: String(localized: "Connect to the Internet and try again."))
    static let invalidInput = WhoisFailure(
        kind: .invalid, message: String(localized: "Enter an IP address, prefix, AS number or hostname."))
    static let backgrounded = WhoisFailure(kind: .other, message: String(localized: "Stopped — app moved to background."))

    static func notFound(_ resource: String) -> WhoisFailure {
        WhoisFailure(kind: .notFound,
                     message: String(localized: "No registry has a record for \(resource). It may be unallocated."))
    }

    static func from(_ error: any Error) -> WhoisFailure {
        switch error {
        case let error as WhoisFailure:
            return error
        case let error as RIPEstatError:
            switch error {
            case .offline: return .offlineFailure
            case .timeout: return .timeoutFailure
            case .rateLimited: return .busyFailure
            case let .http(status):
                if status == 429 || status >= 500 { return .busyFailure }
                return WhoisFailure(kind: .other, message: String(localized: "RIPEstat returned an error (HTTP \(status))."))
            case let .api(messages):
                return WhoisFailure(kind: .other, message: messages.first ?? String(localized: "RIPEstat returned an error."))
            case .decoding:
                return WhoisFailure(kind: .other, message: String(localized: "RIPEstat sent a response the app couldn't read."))
            }
        case let error as URLError:
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: return .offlineFailure
            case .timedOut: return .timeoutFailure
            default: return WhoisFailure(kind: .other, message: error.localizedDescription)
            }
        case let error as NetError:
            switch error {
            case let .resolutionFailed(host, _), let .noAddress(host, _):
                return WhoisFailure(kind: .unresolved, message: String(localized: "Couldn't find \(host). Check the name and try again."))
            default:
                return WhoisFailure(kind: .other, message: String(localized: "The address couldn't be used."))
            }
        default:
            return WhoisFailure(kind: .other, message: error.localizedDescription)
        }
    }

    /// Short message stored in a failed My IP slot.
    static func myIPMessage(for error: any Error) -> String {
        switch error {
        case RIPEstatError.rateLimited, PublicIPError.badResponse(status: 429):
            return String(localized: "RIPEstat is busy. Try again in a moment.")
        case let RIPEstatError.http(status) where status >= 500:
            return String(localized: "RIPEstat is busy. Try again in a moment.")
        case let PublicIPError.badResponse(status) where status >= 500:
            return String(localized: "RIPEstat is busy. Try again in a moment.")
        default:
            return String(localized: "RIPEstat didn't answer. Check your connection and try again.")
        }
    }
}
