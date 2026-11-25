// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore

public struct LocalVerdict: Hashable, Sendable {
    public enum Reason: Hashable, Sendable { case address(SpecialPurposeRange), asn(ReservedASN) }

    public let input: String
    public let reason: Reason
    /// "Look up 8.8.8.8 instead".
    public let embeddedIPv4: IPAddress?

    /// False for a prefix such as "192.168.0.0/16": there is no single host to ping or trace.
    public let isSingleAddress: Bool

    public init(input: String, reason: Reason, embeddedIPv4: IPAddress?, isSingleAddress: Bool = true) {
        self.input = input
        self.reason = reason
        self.embeddedIPv4 = embeddedIPv4
        self.isSingleAddress = isSingleAddress
    }

    /// Ping and Traceroute make sense: one address whose range allows probing.
    public var canProbe: Bool {
        if isSingleAddress, case let .address(range) = reason { range.allowsProbing } else { false }
    }
}
