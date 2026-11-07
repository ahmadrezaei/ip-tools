// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation

enum DateParsing {
    /// RIPEstat timestamps are ISO-8601 without timezone (UTC), with optional fractional seconds.
    /// Also accepts a trailing `Z`, a `±hh:mm` offset and a space instead of `T`.
    static func parse(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        let b = Array(string.utf8)
        guard b.count >= 19, b[4] == 0x2D, b[7] == 0x2D, b[10] == 0x54 || b[10] == 0x20,
              b[13] == 0x3A, b[16] == 0x3A else { return nil }
        func num(_ from: Int, _ len: Int) -> Int? {
            var v = 0
            for i in from..<(from + len) {
                guard i < b.count, b[i] >= 0x30, b[i] <= 0x39 else { return nil }
                v = v * 10 + Int(b[i] - 0x30)
            }
            return v
        }
        guard let year = num(0, 4), let month = num(5, 2), let day = num(8, 2),
              let hour = num(11, 2), let minute = num(14, 2), let second = num(17, 2),
              (1...12).contains(month), (1...31).contains(day), hour < 24, minute < 60, second < 61
        else { return nil }
        var index = 19
        var fraction = 0.0
        if index < b.count, b[index] == 0x2E {
            index += 1
            var scale = 0.1
            while index < b.count, b[index] >= 0x30, b[index] <= 0x39 {
                fraction += Double(b[index] - 0x30) * scale
                scale /= 10
                index += 1
            }
        }
        var offset = 0
        if index < b.count {
            if b[index] == 0x5A { index += 1 } else if b[index] == 0x2B || b[index] == 0x2D {
                let sign = b[index] == 0x2D ? -1 : 1
                guard let oh = num(index + 1, 2) else { return nil }
                var om = 0
                if index + 3 < b.count {
                    let start = b[index + 3] == 0x3A ? index + 4 : index + 3
                    om = num(start, 2) ?? 0
                }
                offset = sign * (oh * 3600 + om * 60)
                index = b.count
            }
        }
        // Days since 1970-01-01 (civil-from-days algorithm).
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = month > 2 ? month - 3 : month + 9
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        let days = era * 146_097 + doe - 719_468
        let seconds = days * 86_400 + hour * 3600 + minute * 60 + second - offset
        return Date(timeIntervalSince1970: Double(seconds) + fraction)
    }
}
