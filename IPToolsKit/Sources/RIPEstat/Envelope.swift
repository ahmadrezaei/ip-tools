// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation

/// Common RIPEstat response envelope. `data` decoding is specific to each call.
struct Envelope<Payload: Decodable & Sendable>: Decodable, Sendable {
    let status: String
    let statusCode: Int?
    let messages: [[String]]
    let data: Payload?

    enum CodingKeys: String, CodingKey {
        case status
        case statusCode = "status_code"
        case messages
        case data
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "ok"
        statusCode = try? c.decodeIfPresent(Int.self, forKey: .statusCode)
        messages = (try? c.decodeIfPresent([[String]].self, forKey: .messages)) ?? []
        data = try c.decodeIfPresent(Payload.self, forKey: .data)
    }
}

/// Only the envelope fields; never fails on an unexpected `data` shape.
struct EnvelopeProbe: Decodable, Sendable {
    let status: String
    let statusCode: Int?
    let messages: [[String]]

    enum CodingKeys: String, CodingKey {
        case status
        case statusCode = "status_code"
        case messages
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "ok"
        statusCode = try? c.decodeIfPresent(Int.self, forKey: .statusCode)
        messages = (try? c.decodeIfPresent([[String]].self, forKey: .messages)) ?? []
    }

    /// Message texts, preferring the "error" level ones.
    var errorTexts: [String] {
        let errors = messages.filter { $0.first == "error" && $0.count > 1 }.map { $0[1] }
        if !errors.isEmpty { return errors }
        return messages.compactMap { $0.count > 1 ? $0[1] : $0.first }
    }
}

/// Decodes either an Int, a numeric String ("13335", "AS13335", asdot "1.10") or a Double into a UInt32.
struct FlexASN: Decodable, Sendable {
    let value: UInt32?

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int64.self) {
            value = UInt32(exactly: i)
        } else if let s = try? c.decode(String.self) {
            value = ASNText.parse(s)
        } else if let d = try? c.decode(Double.self) {
            value = UInt32(exactly: d)
        } else {
            value = nil
        }
    }
}

enum ASNText {
    /// "13335", "AS13335", "as13335", asdot "1.10" (= 65546).
    static func parse(_ text: String) -> UInt32? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("as") { s = String(s.dropFirst(2)) }
        if let n = UInt32(s) { return n }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count == 2, let hi = UInt32(parts[0]), let lo = UInt32(parts[1]), hi <= 0xFFFF, lo <= 0xFFFF {
            return hi << 16 | lo
        }
        return nil
    }
}

/// An array element that decodes to nil instead of failing the whole array.
struct Lossy<T: Decodable & Sendable>: Decodable, Sendable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}
