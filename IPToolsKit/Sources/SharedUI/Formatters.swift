// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation

public enum Format {
    /// "13.6 ms", "1.24 s"
    public static func rtt(_ seconds: TimeInterval) -> String {
        if seconds >= 1 { return String(format: "%.2f s", seconds) }
        let ms = seconds * 1000
        return ms >= 100 ? String(format: "%.0f ms", ms) : String(format: "%.1f ms", ms)
    }

    /// Milliseconds with one decimal and no unit: "13.6".
    public static func ms(_ seconds: TimeInterval) -> String {
        String(format: "%.1f", seconds * 1000)
    }

    /// "5%"
    public static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    /// "2 min ago"
    public static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// "2026-11-07 12:34 UTC"
    public static func utcStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date) + " UTC"
    }

    /// Last line of every text export: "— IP Tools for iOS, 2026-11-07 12:34 UTC".
    public static func exportFooter(_ date: Date = Date()) -> String {
        "— IP Tools for iOS, \(utcStamp(date))"
    }
}
