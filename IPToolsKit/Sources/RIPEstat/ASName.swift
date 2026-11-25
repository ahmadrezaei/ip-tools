// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation

public extension ASName {
    /// Rule 1 only (strip the leading handle), suffix kept.
    static func holderName(_ holder: String) -> String { strippingHandle(holder) }
}

public enum ASName {
    private static let suffixes = rawSuffixes.sorted { $0.count > $1.count }   // longest match wins (" Pte. Ltd." before " Ltd.")
    private static let rawSuffixes = [
        ", Inc.", " Inc.", ", LLC", " LLC", " Ltd.", " Ltd", " Limited", " S.A.", " SA", " GmbH", " B.V.", " B.V",
        " AB", " AG", " S.p.A.", " e.V.", " UG", " Sdn Bhd", " Pte. Ltd.",
    ]

    /// Short display name for an AS holder string (rule in DESIGN §11).
    public static func short(_ holder: String) -> String {
        var name = strippingHandle(holder)
        for suffix in suffixes where name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
            break
        }
        return name.trimmingCharacters(in: .whitespaces)
    }

    /// Rule 1: drop the leading handle ("GOOGLE - Google LLC" and "HETZNER-AS Hetzner Online GmbH" lose the first word).
    fileprivate static func strippingHandle(_ holder: String) -> String {
        var name = holder.trimmingCharacters(in: .whitespaces)
        if let range = name.range(of: " - ") {
            name = String(name[range.upperBound...])
        } else {
            let parts = name.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            if parts.count > 1 { name = String(parts[1]) }
        }
        return name.trimmingCharacters(in: .whitespaces)
    }
}
