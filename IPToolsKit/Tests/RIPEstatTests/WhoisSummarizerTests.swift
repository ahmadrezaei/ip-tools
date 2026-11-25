// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import Testing
@testable import RIPEstat

/// DESIGN §14.9.4: one test per row of the golden table, fixture-driven, plus the rules behind them.
@Suite struct WhoisSummarizerTests {
    private func network(_ query: String, _ inputs: WhoisInputs) -> WhoisSummary {
        WhoisSummarizer.summarize(query: query, subject: .network, inputs: inputs)
    }

    private func autonomousSystem(_ asn: UInt32, _ inputs: WhoisInputs) -> WhoisSummary {
        WhoisSummarizer.summarize(query: "AS\(asn)", subject: .autonomousSystem(asn), inputs: inputs)
    }

    // MARK: Golden table

    @Test func golden_8_8_8_8() throws {
        let s = network("8.8.8.8", WhoisInputs(whois: try Fixture.whois("8.8.8.8"), network: try Fixture.network("8.8.8.8"),
                                               abuse: try Fixture.abuse("8.8.8.8")))
        #expect(s.cidrs == ["8.8.8.0/24"])
        #expect(s.range == "8.8.8.0 - 8.8.8.255")
        #expect(s.name == "GOGL")
        #expect(s.handle == "NET-8-8-8-0-2")
        #expect(s.organization == "Google LLC")
        #expect(s.orgHandle == "GOGL")
        #expect(s.organizationProvenance == .registry)
        #expect(s.country == "US")
        #expect(s.countryProvenance == .registry)
        #expect(s.rir == .arin)
        #expect(s.status == "Direct Allocation")
        #expect(s.parent == "NET8 (NET-8-0-0-0-0)")
        #expect(s.routedPrefix == "8.8.8.0/24")
        #expect(s.originASNs == [15169])
        #expect(s.registeredOrigins == [15169])
        #expect(s.announced == true)
        #expect(s.abuseEmails == ["network-abuse@google.com"])
        #expect(s.abuseProvenance == nil)
        #expect(s.registered == Fixture.date("2023-12-28"))
        #expect(s.summaryRecordID == 0)
        #expect(s.notes.isEmpty)
        #expect(!s.isEmpty)
        #expect(s.contacts.contains(.init(role: "Abuse", handle: "ABUSE5250-ARIN")))
        #expect(s.contacts.contains(.init(role: "Tech", handle: "ZG39-ARIN")))
    }

    @Test func golden_arinIPv6_noMatchThenRetry() throws {
        let first = try Fixture.whois("2001-4860-4860--8888", resource: "2001:4860:4860::8888")
        #expect(first.isNoMatch)
        #expect(WhoisSummarizer.summaryRecord(in: first.records) == nil)
        // The feature then retries with the covering prefix from network-info.
        let info = try Fixture.network("2001-4860-4860--8888")
        #expect(info.prefix == "2001:4860::/32")
        let retried = try Fixture.whois("2001-4860---32", resource: "2001:4860::/32")
        #expect(!retried.isNoMatch)
        let s = network("2001:4860:4860::8888", WhoisInputs(whois: retried, network: info,
                                                            abuse: try Fixture.abuse("2001-4860-4860--8888")))
        #expect(s.name == "GOOGLE-IPV6")                   // not ARIN-004 (/23)
        #expect(s.cidrs == ["2001:4860::/32"])
        #expect(s.handle == "NET6-2001-4860-1")
        #expect(s.parent == "ARIN-004 (NET6-2001-4800-0)")
        #expect(s.summaryRecordID == 1)
        #expect(s.organization == "Google LLC")
        #expect(s.orgHandle == "GOGL")
        #expect(s.country == "US")
        #expect(s.countryProvenance == .registry)
        #expect(s.rir == .arin)
        #expect(s.abuseEmails == ["arin-contact@google.com", "network-abuse@google.com"])
        #expect(s.registeredOrigins == [15169])            // sub-prefix IRR routes of other origins are not ours
        #expect(s.originASNs == [15169])
        // Resource-level contacts win over the parent organisation's.
        #expect(s.contacts.contains(.init(role: "Abuse", handle: "ZG39-ARIN")))
        #expect(!s.contacts.contains { $0.handle == "ARIN-HOSTMASTER" })
        #expect(s.range == "2001:4860:: - 2001:4860:ffff:ffff:ffff:ffff:ffff:ffff")
    }

    @Test func golden_193_0_6_139() throws {
        let s = network("193.0.6.139", WhoisInputs(whois: try Fixture.whois("193.0.6.139"),
                                                    network: try Fixture.network("193.0.6.139"),
                                                    abuse: try Fixture.abuse("193.0.6.139")))
        #expect(s.cidrs == ["193.0.0.0/21"])
        #expect(s.range == "193.0.0.0 - 193.0.7.255")
        #expect(s.name == "RIPE-NCC")
        #expect(s.descriptions == ["RIPE Network Coordination Centre", "Amsterdam, Netherlands"])
        #expect(s.organization == "RIPE Network Coordination Centre")
        #expect(s.organizationProvenance == .description)
        #expect(s.orgHandle == "ORG-RIEN1-RIPE")
        #expect(s.country == "NL")
        #expect(s.rir == .ripe)
        #expect(s.status == "ASSIGNED PA")
        #expect(s.registered == Fixture.date("2003-03-17T12:15:57Z"))
        #expect(s.lastModified == Fixture.date("2026-03-19T09:08:35Z"))
        #expect(s.registeredOrigins == [3333])             // duplicate IRR object collapsed
        #expect(s.abuseEmails == ["abuse@ripe.net"])
        #expect(s.abuseProvenance == nil)
        #expect(s.contacts.contains(.init(role: "Admin", handle: "MDIR-RIPE")))
        #expect(s.contacts.contains(.init(role: "Maintainer", handle: "RIPE-NCC-MNT")))
    }

    @Test func golden_1_1_1_1() throws {
        let whois = try Fixture.whois("1.1.1.1")
        let s = network("1.1.1.1", WhoisInputs(whois: whois, abuse: try Fixture.abuse("1.1.1.1")))
        #expect(s.cidrs == ["1.1.1.0/24"])
        #expect(s.name == "APNIC-LABS")
        #expect(s.organization == "APNIC and Cloudflare DNS Resolver project")
        #expect(s.organizationProvenance == .description)
        #expect(s.country == "AU")
        #expect(s.rir == .apnic)
        #expect(s.status == "ASSIGNED PORTABLE")
        #expect(s.lastModified == Fixture.date("2023-04-26T22:57:58Z"))
        #expect(s.registeredOrigins == [13335])
        #expect(s.abuseEmails == ["helpdesk@apnic.net"])
    }

    @Test func golden_1_1_1_1_finderFailedUsesRemarks() throws {
        let s = network("1.1.1.1", WhoisInputs(whois: try Fixture.whois("1.1.1.1"), failed: [.abuse]))
        #expect(s.abuseEmails == ["resolver-abuse@cloudflare.com"])
        #expect(s.abuseProvenance == .registry)
        #expect(s.notes.contains(.missing(.abuse)))
    }

    @Test func golden_196_216_2_1() throws {
        let s = network("196.216.2.1", WhoisInputs(whois: try Fixture.whois("196.216.2.1")))
        #expect(s.cidrs == ["196.216.2.0/23"])
        #expect(s.name == "AFRINIC")
        #expect(s.organization == "AfriNIC - Internal Use")
        #expect(s.country == "ZA")
        #expect(s.rir == .afrinic)
        #expect(s.status == "ASSIGNED PI")
        #expect(s.parent == "196.0.0.0 - 196.255.255.255")
        #expect(s.registeredOrigins == [33764])
    }

    @Test func golden_200_160_2_3_lacnic() throws {
        let whois = try Fixture.whois("200.160.2.3")
        #expect(whois.records.isEmpty)
        #expect(!whois.isNoMatch)                          // nothing to retry
        let s = network("200.160.2.3", WhoisInputs(whois: whois, network: try Fixture.network("200.160.2.3"),
                                                   abuse: nil, country: try Fixture.country("200.160.2.3"),
                                                   names: try Fixture.names(), failed: [.abuse]))
        #expect(s.notes.first == .registryRecordsUnavailable(.lacnic))
        #expect(s.cidrs == ["200.160.0.0/20"])
        #expect(s.range == "200.160.0.0 - 200.160.15.255")
        #expect(s.routedPrefix == "200.160.0.0/20")
        #expect(s.organization == "Nucleo de Inf. e Coord. do Ponto BR - NIC.BR")
        #expect(s.organizationProvenance == .asHolder(22548))
        #expect(s.country == "BR")
        #expect(s.countryProvenance == .rirStatistics)
        #expect(s.rir == .lacnic)
        #expect(s.originASNs == [22548])
        #expect(s.registeredOrigins == [22548])
        #expect(s.summaryRecordID == nil)
        #expect(!s.isEmpty)
    }

    @Test func golden_hetznerOperatorFromAS() throws {
        let s = network("116.203.0.1", WhoisInputs(whois: try Fixture.whois("116.203.0.1"),
                                                   network: try Fixture.network("116.203.0.1"),
                                                   names: try Fixture.names()))
        #expect(s.cidrs == ["116.203.0.0/20"])             // the registry block, not the /16 BGP prefix
        #expect(s.routedPrefix == "116.203.0.0/16")
        #expect(s.name == "CLOUD-NBG1")
        #expect(s.descriptions.isEmpty)
        #expect(s.organization == "Hetzner Online GmbH")
        #expect(s.organizationProvenance == .asHolder(24940))
        #expect(s.orgHandle == "ORG-HOA1-RIPE")
        #expect(s.country == "DE")
        #expect(s.rir == .ripe)
        #expect(s.status == "ASSIGNED PA")
    }

    @Test func golden_descriptionHolderForHetznerWithDescr() throws {
        let s = network("88.198.0.1", WhoisInputs(whois: try Fixture.whois("88.198.0.1"),
                                                  network: try Fixture.network("88.198.0.1"),
                                                  names: try Fixture.names()))
        #expect(s.organization == "Hetzner Online AG")
        #expect(s.organizationProvenance == .description)
        #expect(s.registeredOrigins == [24940])            // the /16 route covers the /20
    }

    @Test func golden_10_0_0_1_ianaCatchAllIsEmpty() throws {
        let whois = try Fixture.whois("10.0.0.1")
        #expect(whois.isLowConfidence)
        let s = network("10.0.0.1", WhoisInputs(whois: whois, network: try Fixture.network("10.0.0.1")))
        #expect(s.isEmpty)
        #expect(s.summaryRecordID == nil)
        #expect(s.cidrs.isEmpty)
        #expect(s.rir == nil)                              // authorities are not trusted at low confidence
        #expect(s.notes == [.lowConfidence])               // a dropped catch-all is "no record", not "unavailable"
    }

    @Test func golden_AS13335() throws {
        let s = autonomousSystem(13335, WhoisInputs(whois: try Fixture.whois("AS13335"),
                                                    asOverview: try Fixture.asOverview(13335),
                                                    abuse: try Fixture.abuse("AS13335"),
                                                    country: try Fixture.country("AS13335")))
        #expect(s.subject == .autonomousSystem(13335))
        #expect(s.name == "CLOUDFLARENET")
        #expect(s.handle == "13335")
        #expect(s.organization == "Cloudflare, Inc.")
        #expect(s.organizationProvenance == .registry)
        #expect(s.orgHandle == "CLOUD14")
        #expect(s.country == "US")
        #expect(s.countryProvenance == .registry)             // the registry's own value wins over statistics
        #expect(s.rir == .arin)
        #expect(s.registered == Fixture.date("2010-07-14"))
        #expect(s.abuseEmails == ["abuse@cloudflare.com"])
        #expect(s.announced == true)
        #expect(s.cidrs.isEmpty)
        #expect(s.originASNs.isEmpty)
        #expect(s.contacts.contains(.init(role: "Abuse", handle: "ABUSE2916-ARIN")))
        #expect(s.contacts.contains(.init(role: "NOC", handle: "NOC11962-ARIN")))
    }

    @Test func golden_AS3333_rpsl() throws {
        let whois = try Fixture.whois("AS3333")
        #expect(whois.records.count == 1)
        let s = autonomousSystem(3333, WhoisInputs(whois: whois, asOverview: try Fixture.asOverview(3333)))
        #expect(s.name == "RIPE-NCC-AS")
        #expect(s.organization == "Reseaux IP Europeens Network Coordination Centre (RIPE NCC)")
        #expect(s.organizationProvenance == .description)
        #expect(s.orgHandle == "ORG-RIEN1-RIPE")
        #expect(s.rir == .ripe)
        #expect(s.summaryRecordID == 0)
        // The 80+ remarks/import/export lines stay in the raw record, not in the summary.
        #expect(whois.records[0].all("remarks").count > 20)
        #expect(whois.records[0].all("import").count > 10)
        #expect(s.descriptions == ["Reseaux IP Europeens Network Coordination Centre (RIPE NCC)"])
    }

    @Test func golden_AS22548_lacnicEmpty() throws {
        let whois = try Fixture.whois("AS22548")
        let s = autonomousSystem(22548, WhoisInputs(whois: whois, asOverview: try Fixture.asOverview(22548),
                                                    abuse: nil, country: try Fixture.country("AS22548")))
        #expect(s.notes == [.registryRecordsUnavailable(.lacnic)])
        #expect(s.organization == "Nucleo de Inf. e Coord. do Ponto BR - NIC.BR")
        #expect(s.organizationProvenance == .asHolder(22548))
        #expect(s.country == "BR")
        #expect(s.countryProvenance == .rirStatistics)
        #expect(s.rir == .lacnic)
        #expect(s.announced == true)
        #expect(!s.isEmpty)
    }

    @Test func golden_ORG_error_isAnAPIError() throws {
        let body = try Fixture.data("whois_ORG-HOA1-RIPE_error")
        #expect(throws: RIPEstatError.api(messages: [
            "ORG-HOA1-RIPE is of an unsupported resource type. It should be one of: IP prefix/range/address, asn.",
        ])) { try WhoisParsing.whois(body, resource: "ORG-HOA1-RIPE") }
    }

    // MARK: Rules

    private func record(_ id: Int, _ pairs: [(String, String)]) -> WhoisRecord {
        WhoisRecord(id: id, fields: pairs.map { WhoisField(key: $0.0, value: $0.1, link: nil) })
    }

    @Test func mostSpecificNetworkObjectWins() {
        let records = [
            record(0, [("NetRange", "2001:4800:: - 2001:49FF:FFFF:FFFF:FFFF:FFFF:FFFF:FFFF"), ("CIDR", "2001:4800::/23")]),
            record(1, [("OrgName", "Someone")]),
            record(2, [("NetRange", "2001:4860:: - 2001:4860:FFFF:FFFF:FFFF:FFFF:FFFF:FFFF"), ("CIDR", "2001:4860::/32")]),
        ]
        #expect(WhoisSummarizer.summaryRecord(in: records)?.id == 2)
        #expect(WhoisSummarizer.summaryRecord(in: records.reversed())?.id == 2)
    }

    @Test func tiesGoToTheLaterObject() {
        let records = [
            record(0, [("inetnum", "10.0.0.0/24"), ("netname", "A")]),
            record(1, [("inetnum", "10.0.1.0/24"), ("netname", "B")]),
        ]
        #expect(WhoisSummarizer.summaryRecord(in: records)?.id == 1)
    }

    @Test func rangeOnlyObjectsUseTheEnclosingBlock() {
        let records = [
            record(0, [("inetnum", "193.0.0.0 - 193.0.255.255")]),         // /16
            record(1, [("inetnum", "193.0.0.0 - 193.0.7.255")]),           // /21
            record(2, [("inetnum", "193.0.4.0 - 193.0.9.255")]),           // not aligned: enclosing /20
        ]
        #expect(WhoisSummarizer.summaryRecord(in: records)?.id == 1)
    }

    @Test func autonomousSystemObjectIsTheFallbackAndMarkersNeverMatch() {
        let marker = record(0, [("No match found for + ! 2001", "4860:4860::8888."), ("source", "ARIN")])
        let autNum = record(1, [("aut-num", "AS3333")])
        #expect(WhoisSummarizer.summaryRecord(in: [marker]) == nil)
        #expect(WhoisSummarizer.summaryRecord(in: []) == nil)
        #expect(WhoisSummarizer.summaryRecord(in: [marker, autNum])?.id == 1)
    }

    @Test func noMatchMarkerShapes() {
        #expect(record(0, [("No match found for 1.2.3.4", "")]).isNoMatchMarker)
        #expect(record(0, [("%", "This is the RIPE Database")]).isNoMatchMarker)
        #expect(record(0, [("% comment", "x")]).isNoMatchMarker)
        #expect(!record(0, [("inetnum", "1.2.3.0/24")]).isNoMatchMarker)
        let response = WhoisResponse(resource: "x", authorities: [],
                                     records: [record(0, [("No match found for x", "")]), record(1, [("inetnum", "1.2.3.0/24")])],
                                     irrRecords: [], warnings: [], queryTime: nil)
        #expect(!response.isNoMatch)                       // a real object beside the marker
    }

    @Test func noMatchWithRoutedPrefixStillSummarisesWithoutRegistry() throws {
        let first = try Fixture.whois("2001-4860-4860--8888", resource: "2001:4860:4860::8888")
        let s = network("2001:4860:4860::8888", WhoisInputs(whois: first, network: try Fixture.network("2001-4860-4860--8888")))
        #expect(s.summaryRecordID == nil)
        #expect(s.notes.first == .registryRecordsUnavailable(.arin))
        #expect(s.cidrs == ["2001:4860::/32"])
        #expect(s.registeredOrigins == [15169])
        #expect(!s.isEmpty)
    }

    @Test func ianaCatchAllNeedsTheWarning() {
        let object = record(0, [("inetnum", "0.0.0.0/0"), ("netname", "IANA-BLK"), ("source", "RIPE")])
        let quiet = WhoisResponse(resource: "10.0.0.1", authorities: ["ripe"], records: [object], irrRecords: [],
                                  warnings: [], queryTime: nil)
        #expect(network("10.0.0.1", WhoisInputs(whois: quiet)).summaryRecordID == 0)
        let warned = WhoisResponse(resource: "10.0.0.1", authorities: ["ripe"], records: [object], irrRecords: [],
                                   warnings: ["Authoritative RIR could not be identified. Best match is returned!"],
                                   queryTime: nil)
        #expect(network("10.0.0.1", WhoisInputs(whois: warned)).summaryRecordID == nil)
        // A /9 (IPv4) or /13 (IPv6) with the warning is a real block.
        let big = record(0, [("inetnum", "10.0.0.0/9")])
        let bigWarned = WhoisResponse(resource: "10.0.0.1", authorities: [], records: [big], irrRecords: [],
                                      warnings: warned.warnings, queryTime: nil)
        #expect(network("10.0.0.1", WhoisInputs(whois: bigWarned)).summaryRecordID == 0)
        let v6 = record(0, [("inet6num", "2000::/12")])
        let v6Warned = WhoisResponse(resource: "2000::1", authorities: [], records: [v6], irrRecords: [],
                                     warnings: warned.warnings, queryTime: nil)
        #expect(network("2000::1", WhoisInputs(whois: v6Warned)).summaryRecordID == nil)
        let v6Real = record(0, [("inet6num", "2000::/13")])
        let v6Kept = WhoisResponse(resource: "2000::1", authorities: [], records: [v6Real], irrRecords: [],
                                   warnings: warned.warnings, queryTime: nil)
        #expect(network("2000::1", WhoisInputs(whois: v6Kept)).summaryRecordID == 0)
        #expect(network("2000::1", WhoisInputs(whois: v6Kept)).notes == [.lowConfidence])
    }

    @Test func whoisFailureLeavesBGPFacts() throws {
        let s = network("8.8.8.8", WhoisInputs(network: try Fixture.network("8.8.8.8"), abuse: try Fixture.abuse("8.8.8.8"),
                                               names: try Fixture.names(), failed: [.registry]))
        #expect(s.summaryRecordID == nil)
        #expect(s.cidrs == ["8.8.8.0/24"])
        #expect(s.organization == "Google LLC")
        #expect(s.organizationProvenance == .asHolder(15169))
        #expect(s.notes == [.missing(.registry)])          // no "records unavailable": we never heard from the registry
        #expect(!s.isEmpty)
    }

    @Test func notAnnouncedNote() {
        let object = record(0, [("inetnum", "192.0.2.0/24"), ("netname", "X"), ("source", "RIPE")])
        let whois = WhoisResponse(resource: "192.0.2.1", authorities: ["ripe"], records: [object], irrRecords: [],
                                  warnings: [], queryTime: nil)
        let s = network("192.0.2.1", WhoisInputs(whois: whois, network: NetworkInfo(prefix: nil, originASNs: [])))
        #expect(s.announced == false)
        #expect(s.notes == [.notAnnounced])
        // An unknown BGP state (the call failed) is not "not announced".
        let unknown = network("192.0.2.1", WhoisInputs(whois: whois, failed: [.routing]))
        #expect(unknown.announced == nil)
        #expect(unknown.notes == [.missing(.routing)])
    }

    @Test func prefixOverviewFeedsRouting() {
        let overview = PrefixOverview(resource: "1.1.1.0/24", announced: true,
                                      origins: [ASHolder(asn: 13335, holder: "CLOUDFLARENET - Cloudflare, Inc.")])
        let s = network("1.1.1.0/24", WhoisInputs(prefixOverview: overview))
        #expect(s.routedPrefix == "1.1.1.0/24")
        #expect(s.originASNs == [13335])
        #expect(s.announced == true)
        #expect(s.organization == "Cloudflare, Inc.")
        #expect(s.organizationProvenance == .asHolder(13335))
        let dark = PrefixOverview(resource: "192.0.2.0/24", announced: false, origins: [])
        let d = network("192.0.2.0/24", WhoisInputs(prefixOverview: dark))
        #expect(d.routedPrefix == nil)
        #expect(d.announced == false)
        #expect(d.isEmpty)
    }

    @Test func emptyRule() {
        #expect(network("2001:db9::1", WhoisInputs()).isEmpty)
        #expect(!network("2001:db9::1", WhoisInputs(country: "BR")).isEmpty)
        #expect(network("2001:db9::1", WhoisInputs(whois: WhoisResponse(resource: "x", authorities: ["arin"], records: [],
                                                                      irrRecords: [], warnings: [], queryTime: nil))).isEmpty)
    }

    @Test func holderRuleSkipsPostalLinesAndNetname() {
        let object = record(0, [("inetnum", "192.0.2.0/24"), ("netname", "EXAMPLE-NET"), ("descr", "EXAMPLE-NET"),
                                ("descr", "1000 Brussels"), ("descr", "Brussels, Belgium"),
                                ("descr", "Example Telecom SA"), ("source", "RIPE")])
        let whois = WhoisResponse(resource: "192.0.2.1", authorities: ["ripe"], records: [object], irrRecords: [],
                                  warnings: [], queryTime: nil)
        let s = network("192.0.2.1", WhoisInputs(whois: whois))
        #expect(s.organization == "Example Telecom SA")
        #expect(s.descriptions.count == 4)
    }

    @Test func orgNameBeatsDescriptions() {
        let object = record(0, [("inetnum", "192.0.2.0/24"), ("descr", "Some text"), ("org-name", "Real Org"),
                                ("source", "APNIC")])
        let whois = WhoisResponse(resource: "192.0.2.1", authorities: ["apnic"], records: [object], irrRecords: [],
                                  warnings: [], queryTime: nil)
        let s = network("192.0.2.1", WhoisInputs(whois: whois))
        #expect(s.organization == "Real Org")
        #expect(s.organizationProvenance == .registry)
        let owner = record(0, [("inetnum", "192.0.2.0/24"), ("owner", "Owner Inc"), ("source", "LACNIC")])
        let ownerSummary = network("192.0.2.1", WhoisInputs(whois: WhoisResponse(resource: "x", authorities: [],
                                                                                records: [owner], irrRecords: [],
                                                                                warnings: [], queryTime: nil)))
        #expect(ownerSummary.organization == "Owner Inc")
        #expect(ownerSummary.rir == .lacnic)
    }

    @Test func arinOrgFallsBackToOrgNameObjectAndCustomerFormat() {
        let object = record(0, [("NetRange", "192.0.2.0 - 192.0.2.255"), ("CIDR", "192.0.2.0/24"), ("NetName", "CUST"),
                                ("Customer", "Example Customer (C0123)"), ("Parent", "()"), ("source", "ARIN")])
        let orgs = [record(1, [("OrgName", "Other"), ("OrgId", "OTHER"), ("Country", "ca")])]
        let whois = WhoisResponse(resource: "192.0.2.1", authorities: ["arin"], records: [object] + orgs, irrRecords: [],
                                  warnings: [], queryTime: nil)
        let s = network("192.0.2.1", WhoisInputs(whois: whois))
        #expect(s.organization == "Example Customer")
        #expect(s.orgHandle == "C0123")
        #expect(s.parent == nil)                           // "()" means no parent
        #expect(s.country == "CA")                         // no org object matches the handle: the first one
        let bare = record(0, [("NetRange", "192.0.2.0 - 192.0.2.255"), ("CIDR", "192.0.2.0/24, 192.0.3.0/24"), ("source", "ARIN")])
        let bareWhois = WhoisResponse(resource: "x", authorities: ["arin"], records: [bare] + orgs, irrRecords: [],
                                      warnings: [], queryTime: nil)
        let b = network("192.0.2.1", WhoisInputs(whois: bareWhois))
        #expect(b.organization == "Other")
        #expect(b.orgHandle == "OTHER")
        #expect(b.cidrs == ["192.0.2.0/24", "192.0.3.0/24"])
    }

    @Test func arinOriginASIsReadAndMergedWithIRR() {
        let object = record(0, [("NetRange", "192.0.2.0 - 192.0.2.255"), ("CIDR", "192.0.2.0/24"),
                                ("OriginAS", "AS64500, AS64501"), ("source", "ARIN")])
        let route = record(1, [("route", "192.0.2.0/24"), ("origin", "64501")])
        let route2 = record(2, [("route", "192.0.2.0/24"), ("origin", "64502")])
        let whois = WhoisResponse(resource: "192.0.2.1", authorities: ["arin"], records: [object],
                                  irrRecords: [route, route2], warnings: [], queryTime: nil)
        #expect(network("192.0.2.1", WhoisInputs(whois: whois)).registeredOrigins == [64500, 64501, 64502])
    }

    @Test func abuseFallbackOrder() {
        let object = record(0, [("NetRange", "192.0.2.0 - 192.0.2.255"), ("CIDR", "192.0.2.0/24"), ("source", "ARIN")])
        let org = record(1, [("OrgAbuseHandle", "A-ARIN"), ("OrgAbuseEmail", "org@example.net")])
        let resource = record(2, [("RAbuseHandle", "B-ARIN"), ("RAbuseEmail", "res@example.net")])
        func summary(_ records: [WhoisRecord], finder: [String] = []) -> WhoisSummary {
            let whois = WhoisResponse(resource: "x", authorities: ["arin"], records: records, irrRecords: [],
                                      warnings: [], queryTime: nil)
            return network("192.0.2.1", WhoisInputs(whois: whois, abuse: AbuseContacts(emails: finder, authoritativeRIR: nil)))
        }
        #expect(summary([object, org, resource], finder: ["f@example.net"]).abuseEmails == ["f@example.net"])
        #expect(summary([object, org, resource]).abuseEmails == ["res@example.net"])
        #expect(summary([object, org]).abuseEmails == ["org@example.net"])
        #expect(summary([object, org]).abuseProvenance == .registry)
        let rpsl = record(0, [("inetnum", "192.0.2.0/24"), ("abuse-mailbox", "box@example.net"), ("source", "RIPE")])
        #expect(summary([rpsl]).abuseEmails == ["box@example.net"])
        let remark = record(0, [("inetnum", "192.0.2.0/24"), ("remarks", "Report abuse to: noc@example.net please"),
                                ("source", "RIPE")])
        #expect(summary([remark]).abuseEmails == ["noc@example.net"])
        let none = record(0, [("inetnum", "192.0.2.0/24"), ("remarks", "contact noc@example.net"), ("source", "RIPE")])
        #expect(summary([none]).abuseEmails.isEmpty)
        #expect(summary([none]).abuseProvenance == nil)
    }

    @Test func rirFallsBackToAuthorityThenAbuseFinder() {
        let whois = WhoisResponse(resource: "x", authorities: ["lacnic"], records: [], irrRecords: [], warnings: [], queryTime: nil)
        #expect(network("x", WhoisInputs(whois: whois)).rir == .lacnic)
        let none = WhoisResponse(resource: "x", authorities: [], records: [], irrRecords: [], warnings: [], queryTime: nil)
        #expect(network("x", WhoisInputs(whois: none, abuse: AbuseContacts(emails: [], authoritativeRIR: "apnic"))).rir == .apnic)
        #expect(network("x", WhoisInputs(whois: none)).rir == nil)
    }

    @Test func failedPartsBecomeNotesInStableOrder() {
        let s = network("x", WhoisInputs(country: "NL", failed: [.names, .location, .country, .abuse, .routing, .registry]))
        #expect(s.notes == [.missing(.registry), .missing(.routing), .missing(.abuse), .missing(.country),
                            .missing(.location), .missing(.names)])
    }

    @Test func summaryRecordIDPointsAtTheUsedRecord() throws {
        let retried = try Fixture.whois("2001-4860---32", resource: "2001:4860::/32")
        let used = try #require(WhoisSummarizer.summaryRecord(in: retried.records))
        #expect(retried.records[used.id].first("NetName") == "GOOGLE-IPV6")
        #expect(retried.records.count == 12)
    }

    @Test func unparsableRangeObjectStillSummarises() {
        let object = record(0, [("inetnum", "garbage"), ("netname", "X"), ("source", "RIPE")])
        let whois = WhoisResponse(resource: "x", authorities: ["ripe"], records: [object], irrRecords: [], warnings: [], queryTime: nil)
        let s = network("x", WhoisInputs(whois: whois))
        #expect(s.cidrs.isEmpty)
        #expect(s.range == nil)
        #expect(s.name == "X")
    }
}
