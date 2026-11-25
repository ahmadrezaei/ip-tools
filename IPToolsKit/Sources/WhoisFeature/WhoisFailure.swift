// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
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
}
