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

    public init(input: String, reason: Reason, embeddedIPv4: IPAddress?) {
        self.input = input
        self.reason = reason
        self.embeddedIPv4 = embeddedIPv4
    }
}
