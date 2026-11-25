// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore
import RIPEstat
import Testing
@testable import WhoisFeature

@Suite @MainActor struct WhoisExportTests {
    private let now = utc("2026-11-25T13:52:00Z")
    private let queried = utc("2026-11-25T13:40:00Z")
    /// "GOOGLE - Google LLC" -> "Google LLC" (the real rule lives in RIPEstat).
    private let holder: (String) -> String = { $0.components(separatedBy: " - ").last ?? $0 }

    private var google: WhoisResult {
        WhoisPreviewData.result(
            .address(ip("8.8.8.8"), hostname: nil),
            WhoisSummary(
                subject: .network, query: "8.8.8.8", cidrs: ["8.8.8.0/24"], range: "8.8.8.0 - 8.8.8.255", name: "GOGL",
                handle: "NET-8-8-8-0-2", organization: "Google LLC", organizationProvenance: .registry, orgHandle: "GOGL",
                country: "US", countryProvenance: .registry, rir: .arin, status: "Direct Allocation",
                originASNs: [15169], abuseEmails: ["network-abuse@google.com"],
                registered: utc("2023-12-28T00:00:00Z")),
            raw: whoisResponse("8.8.8.8", records: [
                whoisRecord([("NetRange", "8.8.8.0 - 8.8.8.255"), ("CIDR", "8.8.8.0/24"), ("OriginAS", "")]),
                whoisRecord([("No match found for + ! 2001", "x")], id: 1),
            ], irr: [whoisRecord([("route", "8.8.8.0/24"), ("origin", "AS15169")], id: 2)], queryTime: queried),
            reverse: "dns.google", location: GeoLocation(country: "US", city: "Mountain View", coveredFraction: 1),
            names: [15169: "GOOGLE - Google LLC"])
    }

    @Test func summaryMatchesTheSpecSample() {
        let expected = """
            WHOIS 8.8.8.8 (dns.google)
            Network     8.8.8.0/24  (8.8.8.0 - 8.8.8.255)
            Name        GOGL  (NET-8-8-8-0-2)
            Org         Google LLC  (GOGL)
            Country     US
            Registry    ARIN · Direct Allocation
            Origin AS   AS15169 Google LLC  (BGP)
            Abuse       network-abuse@google.com
            Registered  2023-12-28
            Source: ARIN whois via RIPEstat, 2026-11-25 13:40 UTC
            — IP Tools for iOS, 2026-11-25 13:52 UTC
            """
        #expect(WhoisExport.summary(google, now: now, holder: holder) == expected)
    }

    @Test func locationIsNeverExported() {
        let text = WhoisExport.full(google, now: now, holder: holder)
        #expect(!text.contains("Mountain View"))
        #expect(!text.contains("approx"))
        #expect(!text.contains("Location"))
    }

    @Test func fullRecordListsObjectsThenTheRoutingRegistry() {
        let text = WhoisExport.full(google, now: now, holder: holder)
        #expect(text.contains("""
            NetRange:  8.8.8.0 - 8.8.8.255
            CIDR:      8.8.8.0/24
            OriginAS:
            """))
        #expect(text.contains("--- routing registry (IRR) ---\nroute:   8.8.8.0/24\norigin:  AS15169"))
        #expect(text.hasSuffix("— IP Tools for iOS, 2026-11-25 13:52 UTC"))
    }

    @Test func provenanceStaysInTheText() {
        let result = WhoisPreviewData.result(
            .address(ip("200.160.2.3"), hostname: "nic.br"),
            WhoisSummary(subject: .network, query: "200.160.2.3", cidrs: ["200.160.0.0/20"],
                         organization: "Nucleo de Inf. e Coord. do Ponto BR", organizationProvenance: .asHolder(22548),
                         country: "BR", countryProvenance: .rirStatistics, rir: .lacnic, announced: true,
                         notes: [.registryRecordsUnavailable(.lacnic)]))
        let text = WhoisExport.summary(result, now: now, holder: holder)
        #expect(text.hasPrefix("WHOIS 200.160.2.3 (nic.br)"))
        #expect(text.contains("Org         Nucleo de Inf. e Coord. do Ponto BR  (network operator, from AS22548)"))
        #expect(text.contains("Country     BR  (RIR statistics)"))
        #expect(text.contains("Note: LACNIC doesn't share whois records through RIPEstat."))
        #expect(text.contains("Abuse       Not listed"))
        #expect(text.contains("Source: LACNIC whois via RIPEstat, "))
    }

    @Test func descriptionHolderIsLabelled() {
        let result = WhoisPreviewData.result(
            .address(ip("193.0.6.139"), hostname: nil),
            WhoisSummary(subject: .network, query: "193.0.6.139", organization: "RIPE Network Coordination Centre",
                         organizationProvenance: .description, orgHandle: "ORG-RIEN1-RIPE"))
        #expect(WhoisExport.summary(result, now: now, holder: holder).contains("(holder, from description)"))
    }

    @Test func asSummaryUsesAnnouncingInsteadOfOrigin() {
        let result = WhoisPreviewData.result(
            .asn(13335),
            WhoisSummary(subject: .autonomousSystem(13335), query: "AS13335", name: "CLOUDFLARENET", organization: "Cloudflare, Inc.",
                         country: "US", rir: .arin, announced: true, abuseEmails: ["abuse@cloudflare.com"]))
        let text = WhoisExport.summary(result, now: now, holder: holder)
        #expect(text.hasPrefix("WHOIS AS13335\n"))
        #expect(text.contains("Announcing  Yes, in BGP now"))
        #expect(!text.contains("Origin AS"))
    }

    @Test func myIPTextMatchesTheSpecSample() {
        let snapshot = MyIPSnapshot(
            v4: .found(ip("193.0.6.139"), reverseName: "www.ripe.net"),
            v6: .found(ip("2001:67c:2e8:22::c100:696"), reverseName: nil), viaVPN: false, generation: 0, fetchedAt: now)
        let result = WhoisPreviewData.result(
            .address(ip("193.0.6.139"), hostname: nil),
            WhoisSummary(subject: .network, query: "193.0.6.139", cidrs: ["193.0.0.0/21"], name: "RIPE-NCC", country: "NL",
                         rir: .ripe, originASNs: [3333], abuseEmails: ["abuse@ripe.net"]),
            names: [3333: "RIPE NCC"])
        let expected = """
            My public IP — 2026-11-25 13:52 UTC
            IPv4  193.0.6.139                 www.ripe.net
            IPv6  2001:67c:2e8:22::c100:696
            Network  193.0.0.0/21 · RIPE-NCC · AS3333 RIPE NCC · NL · RIPE NCC
            Abuse    abuse@ripe.net
            — IP Tools for iOS
            """
        #expect(WhoisExport.myIP(snapshot, result: result, now: now, holder: holder) == expected)
    }

    @Test func myIPTextWithoutAWhoisOrAnAddress() {
        let snapshot = MyIPSnapshot(v4: .found(ip("193.0.6.139"), reverseName: nil), v6: .unavailable(.noRoute), viaVPN: false,
                                    generation: 0, fetchedAt: now)
        #expect(WhoisExport.myIP(snapshot, result: nil, now: now, holder: holder)
            == "My public IP — 2026-11-25 13:52 UTC\nIPv4  193.0.6.139\n— IP Tools for iOS")
    }
}
