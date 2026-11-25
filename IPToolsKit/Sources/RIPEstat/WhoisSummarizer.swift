// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation

public enum WhoisSummarizer {
    public static func summarize(query: String, subject: WhoisSummary.Subject, inputs: WhoisInputs) -> WhoisSummary {
        fatalError("TODO")
    }

    /// DESIGN §14.9.2 most-specific rule; nil when only markers.
    public static func summaryRecord(in records: [WhoisRecord]) -> WhoisRecord? { fatalError("TODO") }

    /// "193.0.0.0 - 193.0.7.255" -> ["193.0.0.0/21"]; minimal cover for non-aligned ranges.
    public static func cidrs(fromRange range: String) -> [String] { fatalError("TODO") }
}
