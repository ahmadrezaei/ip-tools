// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import Testing
@testable import RIPEstat

@Suite struct WhoisSupportTests {
    // MARK: RIR

    @Test func rirIdentifiers() {
        let table: [(String, RIR?)] = [
            ("ARIN", .arin), ("arin", .arin), ("RIPE", .ripe), ("RIPE-NONAUTH", .ripe), ("RIPE NCC", .ripe),
            ("ripencc", .ripe), ("AfriNIC", .afrinic), ("APNIC", .apnic), ("lacnic", .lacnic), (" LACNIC ", .lacnic),
            ("RADB", nil), ("", nil), ("IANA", nil),
        ]
        for (text, expected) in table {
            #expect(RIR(identifier: text) == expected, Comment(rawValue: text))
        }
    }

    @Test func rirDisplayNames() {
        #expect(RIR.allCases.map(\.displayName) == ["AFRINIC", "APNIC", "ARIN", "LACNIC", "RIPE NCC"])
    }

    // MARK: Holder names

    @Test func holderNameStripsOnlyTheHandle() {
        #expect(ASName.holderName("GOOGLE - Google LLC") == "Google LLC")
        #expect(ASName.holderName("HETZNER-AS Hetzner Online GmbH") == "Hetzner Online GmbH")
        #expect(ASName.holderName("AS22548 - Nucleo de Inf. e Coord. do Ponto BR - NIC.BR")
            == "Nucleo de Inf. e Coord. do Ponto BR - NIC.BR")
        #expect(ASName.holderName("CLOUDFLARENET - Cloudflare, Inc.") == "Cloudflare, Inc.")
        #expect(ASName.holderName("SINGLEWORD") == "SINGLEWORD")
        // `short` keeps dropping the legal suffix as before.
        #expect(ASName.short("CLOUDFLARENET - Cloudflare, Inc.") == "Cloudflare")
        #expect(ASName.short("HETZNER-AS Hetzner Online GmbH") == "Hetzner Online")
    }

    // MARK: Dates

    @Test func dateOnlyAndZuluFormats() throws {
        let day = try #require(DateParsing.parse("2023-12-28"))
        #expect(day.timeIntervalSince1970 == 1_703_721_600)
        let zulu = try #require(DateParsing.parse("2003-03-17T12:15:57Z"))
        #expect(zulu.timeIntervalSince1970 == 1_047_903_357)
        #expect(DateParsing.parse("2026-03-19T09:08:35Z") == DateParsing.parse("2026-03-19T09:08:35"))
        #expect(DateParsing.parse("1970-01-01T00:00:00Z")?.timeIntervalSince1970 == 0)
        #expect(DateParsing.parse("2023-13-28") == nil)
        #expect(DateParsing.parse("2023-12-3") == nil)
        #expect(DateParsing.parse("2023/12/28") == nil)
        #expect(DateParsing.parse("") == nil)
        #expect(DateParsing.parse(nil) == nil)
        #expect(DateParsing.parse("2026-11-25T14:34:00")?.timeIntervalSince1970 == 1_795_617_240)
    }

    // MARK: Summary model

    @Test func summaryDefaults() {
        let summary = WhoisSummary(subject: .network, query: "x")
        #expect(summary.isEmpty)
        #expect(summary.cidrs.isEmpty && summary.notes.isEmpty && summary.contacts.isEmpty)
        #expect(!WhoisSummary(subject: .network, query: "x", country: "NL").isEmpty)
        #expect(!WhoisSummary(subject: .network, query: "x", routedPrefix: "1.0.0.0/24").isEmpty)
        #expect(!WhoisSummary(subject: .network, query: "x", registeredOrigins: [1]).isEmpty)
        #expect(!WhoisSummary(subject: .network, query: "x", summaryRecordID: 0).isEmpty)
        #expect(!WhoisSummary(subject: .autonomousSystem(1), query: "AS1", organization: "Org").isEmpty)
    }

    @Test func recordAccessors() {
        let record = WhoisRecord(id: 3, fields: [
            WhoisField(key: "descr", value: "a", link: nil), WhoisField(key: "descr", value: "b", link: nil),
            WhoisField(key: "source", value: "RIPE", link: nil),
        ])
        #expect(record.first("descr") == "a")
        #expect(record.all("descr") == ["a", "b"])
        #expect(record.first("missing") == nil)
        #expect(record.all("missing").isEmpty)
        #expect(record.source == "RIPE")
        #expect(record.primaryKey == "descr" && record.primaryValue == "a")
        let empty = WhoisRecord(id: 0, fields: [])
        #expect(empty.primaryKey == "" && empty.primaryValue == "")
        #expect(!empty.isNoMatchMarker)
        #expect(empty.source == nil)
    }
}
