// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation

public enum ASName {
    private static let suffixes = rawSuffixes.sorted { $0.count > $1.count }   // longest match wins (" Pte. Ltd." before " Ltd.")
    private static let rawSuffixes = [
        ", Inc.", " Inc.", ", LLC", " LLC", " Ltd.", " Ltd", " Limited", " S.A.", " SA", " GmbH", " B.V.", " B.V",
        " AB", " AG", " S.p.A.", " e.V.", " UG", " Sdn Bhd", " Pte. Ltd.",
    ]

    /// Short display name for an AS holder string (rule in DESIGN §11).
    public static func short(_ holder: String) -> String {
        var name = holder.trimmingCharacters(in: .whitespaces)
        if let range = name.range(of: " - ") {
            name = String(name[range.upperBound...])
        } else {
            let parts = name.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            if parts.count > 1 { name = String(parts[1]) }
        }
        for suffix in suffixes where name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
            break
        }
        return name.trimmingCharacters(in: .whitespaces)
    }
}
