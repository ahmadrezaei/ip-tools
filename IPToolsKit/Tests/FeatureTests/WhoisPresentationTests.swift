// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore
import RIPEstat
import Testing
@testable import WhoisFeature

@Suite struct WhoisPresentationTests {
    // MARK: IPSpeech

    @Test func ipv6IsSpokenInGroupsWithDoubleColon() {
        #expect(IPSpeech.plain(ip("2001:67c:2e8:22::c100:696")) == "2001, 67c, 2e8, 22, double colon, c100, 696")
        #expect(IPSpeech.plain(ip("::1")) == "double colon, 1")
        #expect(IPSpeech.plain(ip("193.0.6.139")) == "193, 0, 6, 139")
    }

    @Test func onlyGroupsWithLettersAreSpelledOut() {
        let label = IPSpeech.label(ip("2001:67c::1"))
        var spelled: [String] = []
        for run in label.runs where run.accessibilitySpeechSpellsOutCharacters == true {
            spelled.append(String(label[run.range].characters))
        }
        #expect(spelled == ["67c"])
        #expect(String(label.characters) == "2001, 67c, double colon, 1")
    }

    @Test func asnIsSpokenWithASpace() {
        #expect(IPSpeech.asn(15169) == "AS 15169")
    }

    // MARK: Device interpretation

    private func local(_ interface: LocalAddress.Interface, _ address: String) -> LocalAddress {
        LocalAddress(interface: interface, name: "en0", address: ip(address))
    }

    @Test func carrierGradeNATWinsOverPlainNAT() {
        let line = DeviceInterpretation.line(local: [local(.cellular, "100.72.13.5"), local(.wifi, "192.168.1.2")],
                                             publicV4: ip("193.0.6.139"), publicV6: nil)
        #expect(line == "Your carrier uses CGNAT: 100.72.13.5 is shared space, and many customers share 193.0.6.139.")
    }

    @Test func privateAddressBehindPublicOneIsNAT() {
        let line = DeviceInterpretation.line(local: [local(.wifi, "192.168.1.23")], publicV4: ip("193.0.6.139"), publicV6: nil)
        #expect(line == "Your router translates 192.168.1.23 to 193.0.6.139 (NAT).")
        #expect(DeviceInterpretation.line(local: [local(.wifi, "172.20.0.4")], publicV4: ip("193.0.6.139"), publicV6: nil) != nil)
        #expect(DeviceInterpretation.line(local: [local(.wifi, "172.32.0.4")], publicV4: ip("193.0.6.139"), publicV6: nil) == nil)
    }

    @Test func matchingIPv6MeansNoNAT() {
        let v6 = "2001:67c:2e8:22::c100:696"
        #expect(DeviceInterpretation.line(local: [local(.wifi, v6)], publicV4: nil, publicV6: ip(v6))
            == "Your IPv6 address is reachable as is (no NAT).")
        #expect(DeviceInterpretation.line(local: [local(.wifi, "2001:db8::1")], publicV4: nil, publicV6: ip(v6)) == nil)
        #expect(DeviceInterpretation.line(local: [], publicV4: nil, publicV6: nil) == nil)
    }

    @Test func sharedSpaceBoundaries() {
        #expect(DeviceInterpretation.isSharedSpace(ip("100.64.0.1")))
        #expect(DeviceInterpretation.isSharedSpace(ip("100.127.255.254")))
        #expect(!DeviceInterpretation.isSharedSpace(ip("100.128.0.1")))
        #expect(!DeviceInterpretation.isSharedSpace(ip("100.63.0.1")))
    }

    // MARK: Countries

    @Test func countryNamesAndFlags() {
        #expect(CountryFormat.flag("US") == "🇺🇸")
        #expect(CountryFormat.flag("nl") == "🇳🇱")
        #expect(CountryFormat.flag("EU") == nil)
        #expect(CountryFormat.flag("ZZ") == nil)
        #expect(CountryFormat.name("EU") == "EU (region)")
        #expect(CountryFormat.name("AP") == "AP (region)")
        #expect(!CountryFormat.name("US").isEmpty && CountryFormat.name("US") != "US (region)")
    }

    // MARK: Local verdict wording

    @Test func localVerdictTitlesSymbolsAndRows() {
        let range = SpecialPurposeRange(network: ip("192.168.0.0"), length: 16, kind: .privateUse, name: "Private use", rfc: "RFC 1918")
        let verdict = LocalVerdict(input: "192.168.1.1", reason: .address(range), embeddedIPv4: nil)
        #expect(verdict.title == "Private address")
        #expect(verdict.systemImage == "lock")
        #expect(verdict.rangeText == "192.168.0.0/16")
        #expect(verdict.typeText == "Private use")
        #expect(verdict.standard == "RFC 1918")
        #expect(verdict.sentence.hasPrefix("192.168.1.1 is in 192.168.0.0/16, a private range (RFC 1918)."))

        let cgnat = SpecialPurposeRange(network: ip("100.64.0.0"), length: 10, kind: .sharedCGNAT, name: "Shared address space", rfc: "RFC 6598")
        let shared = LocalVerdict(input: "100.64.0.1", reason: .address(cgnat), embeddedIPv4: nil)
        #expect(shared.systemImage == "building.2")
        #expect(shared.sentence.contains("CGNAT"))

        let documentation = SpecialPurposeRange(network: ip("192.0.2.0"), length: 24, kind: .documentation, name: "Documentation", rfc: "RFC 5737")
        #expect(LocalVerdict(input: "192.0.2.1", reason: .address(documentation), embeddedIPv4: nil).systemImage == "book.closed")
        let reserved = SpecialPurposeRange(network: ip("240.0.0.0"), length: 4, kind: .reserved, name: "Reserved", rfc: "RFC 1112")
        #expect(LocalVerdict(input: "240.0.0.1", reason: .address(reserved), embeddedIPv4: nil).systemImage == "nosign")
    }

    @Test func localVerdictForASNumbers() {
        let reserved = ReservedASN(range: 64512...65534, name: "Private use", rfc: "RFC 6996")
        let verdict = LocalVerdict(input: "AS64512", reason: .asn(reserved), embeddedIPv4: nil)
        #expect(verdict.title == "Private AS number")
        #expect(verdict.rangeText == "AS64512 – AS65534")
        #expect(verdict.sentence == "AS64512 is a private-use AS number (RFC 6996). Networks use it internally; it has no registry record.")
        let single = ReservedASN(range: 23456...23456, name: "AS_TRANS", rfc: "RFC 6793")
        #expect(LocalVerdict(input: "AS23456", reason: .asn(single), embeddedIPv4: nil).rangeText == "AS23456")
    }

    // MARK: Raw records

    @Test func paragraphKeysJoinIntoBlocks() {
        let record = whoisRecord([("inetnum", "1.0.0.0 - 1.0.0.255"), ("remarks", "line one"), ("remarks", ""), ("remarks", "line three"),
                                  ("country", "AU")])
        let blocks = RawRecordLayout.blocks(record)
        #expect(blocks.map(\.key) == ["inetnum", "remarks", "country"])
        #expect(blocks[1].lines == ["line one", "", "line three"])
    }

    @Test func descrOnlyJoinsWhenLong() {
        let short = whoisRecord([("descr", "a"), ("descr", "b"), ("descr", "c")])
        #expect(RawRecordLayout.blocks(short).count == 3)
        let long = whoisRecord([("descr", "a"), ("descr", "b"), ("descr", "c"), ("descr", "d")])
        #expect(RawRecordLayout.blocks(long).count == 1)
    }

    @Test func friendlyTitles() {
        #expect(RawRecordLayout.title(whoisRecord([("NetRange", "8.8.8.0 - 8.8.8.255")])) == "Network · 8.8.8.0 - 8.8.8.255")
        #expect(RawRecordLayout.title(whoisRecord([("aut-num", "AS3333")])) == "AS · AS3333")
        #expect(RawRecordLayout.title(whoisRecord([("OrgAbuseHandle", "ABUSE5250-ARIN")])) == "Abuse contact · ABUSE5250-ARIN")
        #expect(RawRecordLayout.title(whoisRecord([("OrgTechHandle", "ZG39-ARIN")])) == "Technical contact · ZG39-ARIN")
        #expect(RawRecordLayout.title(whoisRecord([("mystery", "x")])) == "mystery · x")
        #expect(RawRecordLayout.title(whoisRecord([("mystery", "")])) == "mystery")
    }

    @Test func bannersAreRecognised() {
        #expect(RawRecordLayout.isBanner("+-----+"))
        #expect(RawRecordLayout.isBanner("# ==== #"))
        #expect(!RawRecordLayout.isBanner("hello"))
        #expect(!RawRecordLayout.isBanner(""))
        #expect(!RawRecordLayout.isBanner("   "))
    }

    @Test func emailsBecomeLinksAndRecordLinksWin() {
        let text = RawRecordLayout.attributed("report to abuse@example.net please", link: nil)
        let links = text.runs.compactMap(\.link)
        #expect(links == [URL(string: "mailto:abuse@example.net")!])
        let linked = RawRecordLayout.attributed("193.0.0.0/21", link: URL(string: "https://stat.ripe.net/193.0.0.0/21"))
        #expect(linked.runs.compactMap(\.link).count == 1)
    }

    @Test func statLinksLookUpInPlace() {
        #expect(RawRecordsView.statResource(URL(string: "https://stat.ripe.net/193.0.0.0/21")!) == "193.0.0.0/21")
        #expect(RawRecordsView.statResource(URL(string: "https://stat.ripe.net/AS3333")!) == "AS3333")
        #expect(RawRecordsView.statResource(URL(string: "https://stat.ripe.net/app/x")!) == nil)
        #expect(RawRecordsView.statResource(URL(string: "https://stat.ripe.net/")!) == nil)
        #expect(RawRecordsView.statResource(URL(string: "https://example.com/AS3333")!) == nil)
        #expect(RawRecordsView.statResource(URL(string: "http://stat.ripe.net/AS3333")!) == nil)
    }

    // MARK: Failures and announcements

    @Test func failureMapping() {
        #expect(WhoisFailure.from(RIPEstatError.rateLimited).kind == .busy)
        #expect(WhoisFailure.from(RIPEstatError.http(status: 502)).kind == .busy)
        #expect(WhoisFailure.from(RIPEstatError.http(status: 404)).kind == .other)
        #expect(WhoisFailure.from(RIPEstatError.timeout).kind == .timeout)
        #expect(WhoisFailure.from(RIPEstatError.offline).kind == .offline)
        #expect(WhoisFailure.from(RIPEstatError.api(messages: ["bad"])).message == "bad")
        #expect(WhoisFailure.from(URLError(.notConnectedToInternet)).kind == .offline)
        #expect(WhoisFailure.from(URLError(.timedOut)).kind == .timeout)
        #expect(WhoisFailure.from(NetError.resolutionFailed(host: "x.test", reason: "no")).kind == .unresolved)
        #expect(WhoisFailure.from(NetError.localNetworkDenied).kind == .other)
        #expect(WhoisFailure.notFound("2001:db9::1").message == "No registry has a record for 2001:db9::1. It may be unallocated.")
        #expect(WhoisFailure.notFound("x").action == nil)
        #expect(WhoisFailure.busyFailure.action != nil)
    }

    @Test func announcements() {
        let summary = WhoisSummary(subject: .network, query: "8.8.8.8", organization: "Google LLC", country: "US", rir: .arin)
        let result = WhoisPreviewData.result(.address(ip("8.8.8.8"), hostname: nil), summary)
        #expect(IPSpeech.loaded(result).hasPrefix("Whois loaded: Google LLC, ARIN, "))
        let snapshot = MyIPSnapshot(v4: .found(ip("193.0.6.139"), reverseName: nil),
                                    v6: .found(ip("2001:db8::1"), reverseName: nil), viaVPN: false, generation: 0, fetchedAt: Date())
        #expect(IPSpeech.myIP(snapshot) == "Your IPv4 address is 193, 0, 6, 139. IPv6 address found.")
    }

    @Test func subjectResourcesAndProbing() {
        #expect(WhoisSubject.address(ip("8.8.8.8"), hostname: "dns.google").resource == "8.8.8.8")
        #expect(WhoisSubject.prefix(ip("1.1.1.0"), length: 24).resource == "1.1.1.0/24")
        #expect(WhoisSubject.asn(13335).resource == "AS13335")
        #expect(WhoisSubject.address(ip("8.8.8.8"), hostname: nil).canProbe)
        #expect(!WhoisSubject.asn(1).canProbe)
    }
}
