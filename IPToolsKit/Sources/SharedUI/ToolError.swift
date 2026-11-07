// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore

/// A ready-made `DisplayableError` for tool screens.
public struct ToolError: DisplayableError, Equatable {
    public let title: String
    public let message: String
    public let systemImage: String
    public let action: ErrorAction?

    public init(title: String, message: String, systemImage: String = "exclamationmark.triangle",
                action: ErrorAction? = .retry) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.action = action
    }

    /// Maps NetCore errors to the copy in DESIGN §4.2.
    public init(_ error: NetError) {
        switch error {
        case .invalidTarget(let input):
            self.init(title: String(localized: "Invalid Target"),
                      message: String(localized: "\"\(input)\" isn't a valid IP address or hostname."),
                      action: nil)
        case .resolutionFailed(let host, _):
            self.init(title: String(localized: "Couldn't Resolve \(host)"),
                      message: String(localized: "Check the spelling or your DNS."),
                      systemImage: "questionmark.circle")
        case .noAddress(let host, let family):
            let version = family == .v6 ? "IPv6" : "IPv4"
            self.init(title: String(localized: "\(host) has no \(version) address"),
                      message: String(localized: "Choose Automatic or the other IP version in Settings."),
                      systemImage: "network.slash", action: nil)
        case .socketUnavailable(let code):
            self.init(title: String(localized: "Network Socket Unavailable"),
                      message: String(localized: "The system refused to open an ICMP socket (error \(Int(code)))."))
        case .networkUnreachable(let family):
            if family == .v6 {
                self.init(title: String(localized: "No IPv6 Route"),
                          message: String(localized: "This network doesn't support IPv6."),
                          systemImage: "network.slash")
            } else {
                self.init(title: String(localized: "Network Unreachable"),
                          message: String(localized: "Check your connection and try again."),
                          systemImage: "network.slash")
            }
        case .localNetworkDenied:
            self.init(title: String(localized: "Local Network access is off"),
                      message: String(localized: "Allow Local Network access for IP Tools in Settings to reach devices on your network."),
                      systemImage: "wifi.exclamationmark", action: .openSettings)
        case .sendFailed(let code):
            self.init(title: String(localized: "Couldn't Send Packet"),
                      message: String(localized: "The system reported error \(Int(code))."))
        }
    }

    /// Any error: NetError gets its specific copy, everything else a generic one.
    public static func from(_ error: any Error) -> ToolError {
        if let net = error as? NetError { return ToolError(net) }
        if let toolError = error as? ToolError { return toolError }
        return ToolError(title: String(localized: "Something Went Wrong"), message: error.localizedDescription)
    }

    /// One-line text for inline display (rows, run headers).
    public var summary: String { title }
}
