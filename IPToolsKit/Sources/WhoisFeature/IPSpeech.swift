// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore
import SwiftUI

/// Speakable forms of addresses and ASNs (DESIGN §14.13).
enum IPSpeech {
    /// The parts of an address in reading order: IPv4 octets, IPv6 groups with "double colon" for `::`.
    static func parts(_ address: IPAddress) -> [String] {
        let text = address.description
        if address.family == .v4 { return text.split(separator: ".").map(String.init) }
        var result: [String] = []
        let halves = text.components(separatedBy: "::")
        for (index, half) in halves.enumerated() {
            if index > 0 { result.append(String(localized: "double colon")) }
            result.append(contentsOf: half.split(separator: ":").map(String.init))
        }
        return result
    }

    /// "2001, 67c, 2e8, 22, double colon, c100, 696"
    static func plain(_ address: IPAddress) -> String {
        parts(address).joined(separator: ", ")
    }

    /// Groups that contain hex letters are spelled out character by character.
    static func label(_ address: IPAddress) -> AttributedString {
        var result = AttributedString()
        let items = parts(address)
        for (index, item) in items.enumerated() {
            var piece = AttributedString(item)
            if item.contains(where: \.isLetter) && address.family == .v6 && item != String(localized: "double colon") {
                piece.accessibilitySpeechSpellsOutCharacters = true
            }
            result.append(piece)
            if index < items.count - 1 { result.append(AttributedString(", ")) }
        }
        return result
    }

    /// "AS 15169"
    static func asn(_ number: UInt32) -> String { "AS \(number)" }

    // MARK: Announcements

    static func loaded(_ result: WhoisResult) -> String {
        let summary = result.summary
        var parts: [String] = []
        if let organization = summary.organization ?? summary.name { parts.append(organization) }
        if let rir = summary.rir { parts.append(rir.displayName) }
        if let country = summary.country { parts.append(CountryFormat.name(country)) }
        let detail = parts.joined(separator: ", ")
        return detail.isEmpty ? String(localized: "Whois loaded") : String(localized: "Whois loaded: \(detail)")
    }

    static func myIP(_ snapshot: MyIPSnapshot) -> String {
        switch (snapshot.address(.v4), snapshot.address(.v6)) {
        case let (v4?, _?):
            return String(localized: "Your IPv4 address is \(plain(v4)). IPv6 address found.")
        case let (v4?, nil):
            return String(localized: "Your IPv4 address is \(plain(v4)).")
        case let (nil, v6?):
            return String(localized: "Your IPv6 address is \(plain(v6)).")
        case (nil, nil):
            return String(localized: "Couldn't find your IP address.")
        }
    }
}
