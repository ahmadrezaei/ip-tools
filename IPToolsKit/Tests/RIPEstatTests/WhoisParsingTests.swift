// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import Testing
@testable import RIPEstat

@Suite struct WhoisParsingTests {
    private func envelope(_ data: String, status: String = "ok", messages: String = "[]") -> Data {
        Data(#"{"messages":\#(messages),"status":"\#(status)","status_code":200,"data":\#(data)}"#.utf8)
    }

    // MARK: whois

    @Test func decodesArinResponse() throws {
        let response = try Fixture.whois("8.8.8.8")
        #expect(response.resource == "8.8.8.8")
        #expect(response.authorities == ["arin"])
        #expect(response.records.count == 4)
        #expect(response.records.map(\.id) == [0, 1, 2, 3])
        #expect(response.irrRecords.count == 1)
        #expect(response.irrRecords[0].id == 4)            // ids continue after the resource records
        #expect(response.warnings.isEmpty)                 // the "converted to a prefix" info is ignored
        #expect(response.queryTime != nil)
        let first = response.records[0]
        #expect(first.primaryKey == "NetRange")
        #expect(first.primaryValue == "8.8.8.0 - 8.8.8.255")
        #expect(first.source == "ARIN")
        #expect(first.first("CIDR") == "8.8.8.0/24")
        #expect(first.first("cidr") == nil)                // case-sensitive
        #expect(first.first("OriginAS") == "")             // empty values are kept
        #expect(response.irrRecords[0].source == "RADB")
    }

    @Test func linksKeepOnlyWebAndMailSchemes() throws {
        let body = envelope("""
        {"records":[[
          {"key":"a","value":"1","details_link":"https://stat.ripe.net/AS1"},
          {"key":"b","value":"2","details_link":"javascript:alert(1)"},
          {"key":"c","value":"3","details_link":"mailto:noc@example.net"},
          {"key":"d","value":"4","details_link":"http://example.net/x"},
          {"key":"e","value":"5","details_link":"ftp://example.net/x"},
          {"key":"f","value":"6","details_link":""},
          {"key":"g","value":"7"}
        ]],"irr_records":[],"authorities":["RIPE "],"resource":"x","query_time":"2026-11-25T14:34:00"}
        """)
        let fields = try WhoisParsing.whois(body, resource: "x").records[0].fields
        #expect(fields.map { $0.link != nil } == [true, false, true, true, false, false, false])
        #expect(fields[0].link?.absoluteString == "https://stat.ripe.net/AS1")
        let response = try WhoisParsing.whois(body, resource: "x")
        #expect(response.authorities == ["ripe"])
    }

    @Test func trimsKeysAndValuesButKeepsEmptiesAndRepeats() throws {
        let body = envelope("""
        {"records":[[
          {"key":" Comment ","value":" first line "},
          {"key":"Comment","value":" "},
          {"key":"Comment","value":null},
          {"key":"Comment","value":"third"},
          {"key":"  ","value":"dropped"},
          {"value":"no key"}
        ]],"irr_records":[],"authorities":[]}
        """)
        let record = try WhoisParsing.whois(body, resource: "x").records[0]
        #expect(record.all("Comment") == ["first line", "", "", "third"])
        #expect(record.fields.count == 4)
    }

    @Test func noMatchResponse() throws {
        let response = try Fixture.whois("2001-4860-4860--8888", resource: "x")
        #expect(response.isNoMatch)
        #expect(response.records[0].isNoMatchMarker)
        #expect(response.records[0].primaryKey == "No match found for + ! 2001")
        #expect(response.records[0].primaryValue == "4860:4860::8888.")
        #expect(response.irrRecords.count == 1)
    }

    @Test func lowConfidenceWarning() throws {
        let response = try Fixture.whois("10.0.0.1")
        #expect(response.warnings == ["Authoritative RIR could not be identified. Best match is returned!"])
        #expect(response.isLowConfidence)
        #expect(!(try Fixture.whois("8.8.8.8")).isLowConfidence)
    }

    @Test func irrDeduplicationIgnoresRemarksBanner() throws {
        let response = try Fixture.whois("193.0.6.139")
        #expect(response.irrRecords.count == 1)
        #expect(response.irrRecords[0].all("remarks").isEmpty)    // the plain copy is kept
        #expect(response.irrRecords[0].all("origin") == ["3333"])
        // Different objects with the same origin are both kept.
        #expect(try Fixture.whois("1.1.1.1").irrRecords.count == 2)
        #expect(try Fixture.whois("88.198.0.1").irrRecords.count == 1)
        // Same route, different origin: kept.
        #expect(try Fixture.whois("2001-4860---32").irrRecords.count == 42)
    }

    @Test func emptyRecordsAreLACNIC() throws {
        let response = try Fixture.whois("200.160.2.3")
        #expect(response.records.isEmpty)
        #expect(response.authorities == ["lacnic"])
        #expect(response.irrRecords.count == 1)
        #expect(!response.isNoMatch)
        #expect(try Fixture.whois("AS22548").irrRecords.isEmpty)
    }

    @Test func apiErrorsAndBadBodies() {
        #expect(throws: RIPEstatError.self) { try WhoisParsing.whois(Data("<html>502</html>".utf8), resource: "x") }
        #expect(throws: RIPEstatError.rateLimited) {
            try WhoisParsing.whois(Data(#"{"status":"error","status_code":429,"messages":[]}"#.utf8), resource: "x")
        }
        #expect(throws: RIPEstatError.self) {
            try WhoisParsing.whois(Data(#"{"status":"ok","status_code":200,"messages":[]}"#.utf8), resource: "x")
        }
    }

    @Test func oneBrokenRecordDoesNotSpoilTheOthers() throws {
        let body = envelope(#"{"records":[[{"key":"a","value":"1"}], "garbage", [{"key":"b","value":"2"}]],"irr_records":[]}"#)
        let response = try WhoisParsing.whois(body, resource: "x")
        #expect(response.records.count == 2)
        #expect(response.resource == "x")
        #expect(response.authorities.isEmpty)
        #expect(response.queryTime == nil)
    }

    // MARK: abuse-contact-finder

    @Test func abuseContacts() throws {
        let abuse = try Fixture.abuse("2001-4860-4860--8888")
        #expect(abuse.emails == ["arin-contact@google.com", "network-abuse@google.com"])
        #expect(abuse.authoritativeRIR == "arin")
        #expect(try Fixture.abuse("193.0.6.139").emails == ["abuse@ripe.net"])
        #expect(try Fixture.abuse("1.1.1.1").authoritativeRIR == "apnic")
    }

    @Test func abuseDeduplicatesAndTrims() throws {
        let body = envelope(#"{"abuse_contacts":[" a@x.net","a@x.net","","b@x.net"],"authoritative_rir":" "}"#)
        let abuse = try WhoisParsing.abuse(body)
        #expect(abuse.emails == ["a@x.net", "b@x.net"])
        #expect(abuse.authoritativeRIR == nil)
        #expect(try WhoisParsing.abuse(envelope("{}")).emails.isEmpty)
    }

    @Test func abuseBackendErrorEnvelope() throws {
        let body = try Fixture.data("abuse-contact-finder_200.160.2.3_error")
        do {
            _ = try WhoisParsing.abuse(body)
            Issue.record("expected an error")
        } catch let RIPEstatError.api(messages) {
            #expect(messages.first?.contains("RDAP Abuse Contacts API") == true)
        }
    }

    // MARK: rir-stats-country and geolocation

    @Test func registeredCountry() throws {
        #expect(try Fixture.country("8.8.8.8") == "US")
        #expect(try Fixture.country("200.160.2.3") == "BR")
        #expect(try Fixture.country("AS13335") == "US")
        #expect(try WhoisParsing.country(envelope(#"{"located_resources":[]}"#)) == nil)
        #expect(try WhoisParsing.country(envelope(#"{"located_resources":[{"location":""},{"location":"nl"}]}"#)) == "NL")
        #expect(try WhoisParsing.country(envelope("{}")) == nil)
    }

    @Test func geolocationWithCity() throws {
        let geo = try #require(try WhoisParsing.geolocation(Fixture.data("maxmind-geo-lite_116.203.0.1")))
        #expect(geo.country == "DE")
        #expect(geo.city == "Nuremberg")
        #expect(geo.coveredFraction == 1)
    }

    @Test func geolocationWithEmptyCity() throws {
        let geo = try #require(try WhoisParsing.geolocation(Fixture.data("maxmind-geo-lite_193.0.6.139")))
        #expect(geo.country == "NL")
        #expect(geo.city == nil)
    }

    @Test func geolocationMissing() throws {
        #expect(try WhoisParsing.geolocation(envelope(#"{"located_resources":[]}"#)) == nil)
        #expect(try WhoisParsing.geolocation(envelope(#"{"located_resources":[{"locations":[]}]}"#)) == nil)
        #expect(try WhoisParsing.geolocation(envelope(#"{"located_resources":[{"locations":[{"country":"","city":""}]}]}"#)) == nil)
        let partial = try WhoisParsing.geolocation(envelope(#"{"located_resources":[{"locations":[{"country":"de","covered_percentage":50}]}]}"#))
        #expect(partial == GeoLocation(country: "DE", city: nil, coveredFraction: 0.5))
    }

    // MARK: client calls

    @Test func clientCallsUseTheCachedFetch() async throws {
        let stub = StubProtocol.register { request in
            switch request.call {
            case "whois": return .ok((try? Fixture.data("whois_8.8.8.8")) ?? Data())
            case "abuse-contact-finder": return .ok((try? Fixture.data("abuse-contact-finder_8.8.8.8")) ?? Data())
            case "rir-stats-country": return .ok((try? Fixture.data("rir-stats-country_8.8.8.8")) ?? Data())
            default: return .ok((try? Fixture.data("maxmind-geo-lite_116.203.0.1")) ?? Data())
            }
        }
        let client = RIPEstatClient(session: stub.session, baseURL: stub.baseURL)
        #expect(try await client.whois("8.8.8.8").records.count == 4)
        #expect(try await client.whois("8.8.8.8").records.count == 4)
        #expect(try await client.abuseContacts("8.8.8.8").emails == ["network-abuse@google.com"])
        #expect(try await client.registeredCountry("8.8.8.8") == "US")
        #expect(try await client.geolocation("116.203.0.1")?.city == "Nuremberg")
        let requests = StubProtocol.recorded(stub.host)
        #expect(requests.map(\.call) == ["whois", "abuse-contact-finder", "rir-stats-country", "maxmind-geo-lite"])
        #expect(requests.allSatisfy { $0.timeoutInterval == 30 })
        #expect(requests.allSatisfy { $0.url?.query?.hasSuffix("sourceapp=ahmadrezaei-iptools") == true })
        #expect(requests[0].resource == "8.8.8.8")
    }

    @Test func clientEncodesPrefixAndAS() async throws {
        let stub = StubProtocol.register { _ in .ok((try? Fixture.data("whois_AS13335")) ?? Data()) }
        let client = RIPEstatClient(session: stub.session, baseURL: stub.baseURL)
        _ = try await client.whois("AS13335")
        _ = try await client.whois("2001:4860::/32")
        let requests = StubProtocol.recorded(stub.host)
        #expect(requests.map(\.resource) == ["AS13335", "2001:4860::/32"])
    }

    @Test func clientMapsHTTPErrors() async throws {
        let body = try Fixture.data("whois_ORG-HOA1-RIPE_error")
        let stub = StubProtocol.register { _ in .ok(body, status: 400) }
        let client = RIPEstatClient(session: stub.session, baseURL: stub.baseURL)
        await #expect(throws: RIPEstatError.self) { try await client.whois("ORG-HOA1-RIPE") }
        let busy = StubProtocol.register { _ in .ok(Data("<html>502</html>".utf8), status: 502) }
        let busyClient = RIPEstatClient(session: busy.session, baseURL: busy.baseURL)
        await #expect(throws: RIPEstatError.http(status: 502)) { try await busyClient.whois("8.8.8.8") }
        let limited = StubProtocol.register { _ in .ok(Data(), status: 429) }
        let limitedClient = RIPEstatClient(session: limited.session, baseURL: limited.baseURL)
        await #expect(throws: RIPEstatError.rateLimited) { try await limitedClient.abuseContacts("8.8.8.8") }
    }

    // MARK: mock

    @Test func mockServesFixtures() async throws {
        let mock = MockRIPEstat(fixtureBundle: Bundle.module, latency: .zero)
        #expect(try await mock.whois("193.0.6.139").records.count == 1)
        #expect(try await mock.whois("2001:4860::/32").records.count == 12)
        #expect(try await mock.abuseContacts("193.0.6.139").emails == ["abuse@ripe.net"])
        #expect(try await mock.registeredCountry("200.160.2.3") == "BR")
        #expect(try await mock.geolocation("116.203.0.1")?.city == "Nuremberg")
        await #expect(throws: RIPEstatError.self) { try await mock.whois("ORG-HOA1-RIPE") }
        await #expect(throws: RIPEstatError.self) { try await mock.abuseContacts("200.160.2.3") }
    }

    @Test func mockFallsBackWithoutFixtures() async throws {
        let mock = MockRIPEstat(fixtureBundle: Bundle(for: StubProtocol.self), latency: .zero)
        let address = try await mock.whois("8.8.4.4")
        #expect(address.records[0].primaryValue == "8.8.8.0/24")
        #expect(try await mock.whois("9.9.9.0/24").records[0].primaryValue == "9.9.9.0/24")
        #expect(try await mock.whois("AS64500").records[0].primaryKey == "aut-num")
        #expect(try await mock.abuseContacts("9.9.9.9").emails == ["abuse@example.net"])
        #expect(try await mock.registeredCountry("9.9.9.9") == "NL")
        #expect(try await mock.geolocation("9.9.9.9")?.city == "Amsterdam")
        #expect(try await mock.whatsMyIP(over: .v4).ip == "193.0.6.139")
        #expect(try await mock.whatsMyIP(over: .v6).ip == "2001:67c:2e8:22::c100:696")
    }
}
