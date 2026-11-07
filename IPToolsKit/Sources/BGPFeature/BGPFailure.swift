// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore
import RIPEstat
import SharedUI

/// Why a map request produced no graph. Shown through `ErrorStateView`.
public struct BGPFailure: DisplayableError, Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case notRouted, notAnnounced, busy, timeout, offline, invalid, unresolved, other }

    public let kind: Kind
    public let message: String

    public init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }

    public var title: String {
        switch kind {
        case .notRouted: String(localized: "Not routed")
        case .notAnnounced: String(localized: "Not announced")
        case .busy: String(localized: "RIPEstat is busy")
        case .timeout: String(localized: "No response")
        case .offline: String(localized: "You're offline")
        case .invalid: String(localized: "Can't map that")
        case .unresolved: String(localized: "Host not found")
        case .other: String(localized: "Something went wrong")
        }
    }

    public var systemImage: String {
        switch kind {
        case .notRouted: "network.slash"
        case .notAnnounced: "antenna.radiowaves.left.and.right.slash"
        case .busy: "hourglass"
        case .timeout: "clock.badge.exclamationmark"
        case .offline: "wifi.slash"
        case .invalid, .unresolved: "questionmark.circle"
        case .other: "exclamationmark.triangle"
        }
    }

    public var action: ErrorAction? {
        switch kind {
        case .busy, .timeout, .offline, .other: .retry
        case .notRouted, .notAnnounced, .invalid, .unresolved: nil
        }
    }

    static func from(_ error: any Error) -> BGPFailure {
        switch error {
        case let error as RIPEstatError:
            switch error {
            case .offline: return .offlineFailure
            case .timeout: return .timeoutFailure
            case .rateLimited: return .busyFailure
            case let .http(status):
                if status == 429 || status >= 500 { return .busyFailure }
                return BGPFailure(kind: .other, message: String(localized: "RIPEstat returned an error (HTTP \(status))."))
            case let .api(messages):
                return BGPFailure(kind: .other, message: messages.first ?? String(localized: "RIPEstat returned an error."))
            case .decoding:
                return BGPFailure(kind: .other, message: String(localized: "RIPEstat sent a response the app couldn't read."))
            }
        case let error as URLError:
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: return .offlineFailure
            case .timedOut: return .timeoutFailure
            default: return BGPFailure(kind: .other, message: error.localizedDescription)
            }
        case let error as NetError:
            if case let .resolutionFailed(host, _) = error {
                return BGPFailure(kind: .unresolved, message: String(localized: "Couldn't find \(host). Check the name and try again."))
            }
            return BGPFailure(kind: .other, message: String(localized: "The address couldn't be used."))
        default:
            return BGPFailure(kind: .other, message: error.localizedDescription)
        }
    }

    static let busyFailure = BGPFailure(kind: .busy, message: String(localized: "RIPEstat is busy. Try again in a moment."))
    static let timeoutFailure = BGPFailure(kind: .timeout, message: String(localized: "RIPEstat didn't respond."))
    static let offlineFailure = BGPFailure(kind: .offline, message: String(localized: "Connect to the Internet and try again."))
}
