// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import Testing
@testable import RIPEstat

@Suite struct ParsingTests {
    // MARK: Error envelopes

    @Test func errorEnvelopeCarriesMessages() throws {
        let data = try Fixture.data("network-info_AS13335_error")
        do {
            _ = try RIPEstatParsing.networkInfo(data)
            Issue.record("expected an error")
        } catch let RIPEstatError.api(messages) {
            #expect(messages.count == 1)
            #expect(messages[0].contains("unsupported type ASN"))
        }
        #expect(throws: RIPEstatError.self) { try RIPEstatParsing.lookingGlass(Fixture.data("looking-glass_AS13335_error")) }
    }

    @Test func envelopeStatusCode429IsRateLimited() {
        let body = #"{"status":"error","status_code":429,"messages":[["error","Too many requests"]],"data":{}}"#
        #expect(throws: RIPEstatError.rateLimited) { try RIPEstatParsing.networkInfo(Data(body.utf8)) }
    }

    @Test func garbageIsADecodingError() {
        #expect(throws: RIPEstatError.self) { try RIPEstatParsing.networkInfo(Data("<html>".utf8)) }
        let wrongShape = #"{"status":"ok","data":[1,2,3]}"#
        #expect(throws: RIPEstatError.self) { try RIPEstatParsing.networkInfo(Data(wrongShape.utf8)) }
    }

    @Test func unknownFieldsAreIgnoredAndMissingOptionalsTolerated() throws {
        let body = #"{"status":"ok","status_code":200,"messages":"weird","brand_new":1,"data":{"prefix":"1.0.0.0/24","asns":["13335"],"extra":{"a":1}}}"#
        let info = try RIPEstatParsing.networkInfo(Data(body.utf8))
        #expect(info.prefix == "1.0.0.0/24")
    }

    // MARK: ASN normalisation

    @Test func asnsAreNormalisedFromStringsAndInts() throws {
        let strings = #"{"status":"ok","data":{"prefix":"p","asns":["13335","AS174"]}}"#
        #expect(try RIPEstatParsing.networkInfo(Data(strings.utf8)).originASNs == [13335, 174])
        let ints = #"{"status":"ok","data":{"prefix":"p","asns":[13335,174]}}"#
        #expect(try RIPEstatParsing.networkInfo(Data(ints.utf8)).originASNs == [13335, 174])
        let overview = #"{"status":"ok","data":{"announced":true,"asns":[{"asn":13335,"holder":"X"},{"asn":"174","holder":"Y"},{"asn":null}]}}"#
        let o = try RIPEstatParsing.prefixOverview(Data(overview.utf8), resource: "r")
        #expect(o.origins.map(\.asn) == [13335, 174])
        #expect(ASNText.parse("1.10") == 65546)       // asdot
        #expect(ASNText.parse("4294967295") == 4294967295)
        #expect(ASNText.parse("-5") == nil)
    }

    @Test func routingStatusOriginsAreInts() throws {
        let body = #"{"status":"ok","data":{"visibility":{"v4":{"ris_peers_seeing":5,"total_ris_peers":10},"v6":{"ris_peers_seeing":0,"total_ris_peers":0}},"origins":[{"origin":13335},{"origin":"174"}]}}"#
        let s = try RIPEstatParsing.routingStatus(Data(body.utf8))
        #expect(s.origins == [13335, 174])
        #expect(s.v4 == .init(seeing: 5, total: 10))
        let empty = try RIPEstatParsing.routingStatus(Data(#"{"status":"ok","data":{}}"#.utf8))
        #expect(empty.v4 == nil && empty.v6 == nil && empty.origins.isEmpty)
    }

    // MARK: AS paths

    @Test func asPathParsing() {
        #expect(RIPEstatParsing.parseASPath("1 2 3").asns == [1, 2, 3])
        let set = RIPEstatParsing.parseASPath("1 2 {3,4} 5")
        #expect(set.asns == [1, 2, 5] && set.hadASSet)
        let spaced = RIPEstatParsing.parseASPath("1 {3, 4} 5")
        #expect(spaced.asns == [1, 5] && spaced.hadASSet)
        let confed = RIPEstatParsing.parseASPath("(65001 65002) 7 8")
        #expect(confed.asns == [7, 8] && confed.hadASSet)
        #expect(RIPEstatParsing.parseASPath("1 1 1 2").asns == [1, 1, 1, 2])     // prepending is the builder's job
        #expect(RIPEstatParsing.parseASPath("").asns.isEmpty)
        #expect(RIPEstatParsing.parseASPath("1 junk 2").asns == [1, 2])
    }

    @Test func lookingGlassDropsASSetsAndKeepsRaw() throws {
        let body = """
        {"status":"ok","data":{"latest_time":"2026-11-07T08:00:00","rrcs":[{"rrc":"rrc01","location":"London, GB","peers":[
        {"as_path":"10 20 {30,40}","prefix":"1.0.0.0/24","peer":"192.0.2.1","last_updated":"2026-11-07T07:59:00.123456"},
        {"as_path":"10 20 30","prefix":"1.0.0.0/24","peer":"192.0.2.2","last_updated":"garbage"},
        "not a peer"]}]}}
        """
        let lg = try RIPEstatParsing.lookingGlass(Data(body.utf8))
        #expect(lg.collectors == [.init(id: "RRC01", location: "London, GB")])
        #expect(lg.routes.count == 2)                                   // the malformed peer is skipped
        #expect(lg.routes[0].asPath == [10, 20] && lg.routes[0].hadASSet)
        #expect(lg.routes[0].rawASPath == "10 20 {30,40}")
        #expect(lg.routes[1].lastUpdated == nil)
    }

    @Test func bgpStateTolerantPathShapes() throws {
        let body = """
        {"status":"ok","data":{"timestamp":"2026-11-07T13:59:53","bgp_state":[
        {"target_prefix":"p","source_id":"05-2001:db8::1","path":["1","2",3]},
        {"target_prefix":"p","source_id":"12-192.0.2.9","path":"7 {8,9} 10"},
        {"target_prefix":"p","source_id":"nodash","path":[]}]}}
        """
        let lg = try RIPEstatParsing.bgpState(Data(body.utf8))
        #expect(lg.routes[0].collector == "RRC05")
        #expect(lg.routes[0].peerIP == "2001:db8::1")
        #expect(lg.routes[0].asPath == [1, 2, 3])
        #expect(lg.routes[1].asPath == [7, 10] && lg.routes[1].hadASSet)
        #expect(lg.routes[2].asPath.isEmpty)
    }

    // MARK: Timestamps

    @Test func timestampParsing() throws {
        let plain = try #require(DateParsing.parse("2026-11-07T12:32:48"))
        #expect(plain.timeIntervalSince1970 == 1_794_054_768)
        let frac = try #require(DateParsing.parse("2026-11-07T12:32:48.993082"))
        #expect(abs(frac.timeIntervalSince(plain) - 0.993082) < 1e-6)
        #expect(DateParsing.parse("2026-11-07T12:32:48Z") == plain)
        #expect(DateParsing.parse("2026-11-07 12:32:48") == plain)
        #expect(DateParsing.parse("2026-11-07T14:32:48+02:00") == plain)
        #expect(DateParsing.parse("1970-01-01T00:00:00")?.timeIntervalSince1970 == 0)
        #expect(DateParsing.parse("2024-02-29T00:00:00")?.timeIntervalSince1970 == 1_709_164_800)
        #expect(DateParsing.parse(nil) == nil)
        #expect(DateParsing.parse("") == nil)
        #expect(DateParsing.parse("yesterday") == nil)
        #expect(DateParsing.parse("2026-13-07T12:32:48") == nil)
    }

    // MARK: ASName.short

    @Test(arguments: [
        ("CLOUDFLARENET - Cloudflare, Inc.", "Cloudflare"),
        ("GCORE G-Core Labs S.A.", "G-Core Labs"),
        ("HURRICANE - Hurricane Electric LLC", "Hurricane Electric"),
        ("TWELVE99 Arelion Sweden AB", "Arelion Sweden"),
        ("COGENT-174 - Cogent Communications, LLC", "Cogent Communications"),
        ("GOOGLE - Google LLC", "Google"),
        ("FOO", "FOO"),
        ("  PADDED  ", "PADDED"),
        ("ROSTELECOM-AS PJSC Rostelecom", "PJSC Rostelecom"),
        ("AKAMAI-ASN1 Akamai International B.V.", "Akamai International"),
        ("EXAMPLE Example Networks Pte. Ltd.", "Example Networks"),
        ("DTAG Deutsche Telekom AG", "Deutsche Telekom"),
        ("A - B - C Ltd", "B - C"),
    ])
    func shortNameTable(holder: String, expected: String) {
        #expect(ASName.short(holder) == expected)
    }
}
