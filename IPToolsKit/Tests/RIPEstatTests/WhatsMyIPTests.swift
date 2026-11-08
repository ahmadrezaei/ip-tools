// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import Testing
@testable import RIPEstat

@Suite struct WhatsMyIPTests {
    @Test func parsesFixture() throws {
        let result = try RIPEstatParsing.whatsMyIP(Fixture.data("whats-my-ip"))
        #expect(result.ip == "91.107.240.242")
    }

    @Test func missingIPIsADecodingError() {
        let body = #"{"status":"ok","status_code":200,"data":{}}"#
        #expect(throws: RIPEstatError.self) { try RIPEstatParsing.whatsMyIP(Data(body.utf8)) }
        let empty = #"{"status":"ok","status_code":200,"data":{"ip":""}}"#
        #expect(throws: RIPEstatError.self) { try RIPEstatParsing.whatsMyIP(Data(empty.utf8)) }
    }

    @Test func errorEnvelopeIsAPIError() {
        let body = #"{"status":"error","status_code":500,"messages":[["error","boom"]],"data":{}}"#
        #expect(throws: RIPEstatError.api(messages: ["boom"])) { try RIPEstatParsing.whatsMyIP(Data(body.utf8)) }
    }

    @Test func clientRequestShapeNeverCachedTenSecondTimeout() async throws {
        let body = try Fixture.data("whats-my-ip")
        let stub = StubProtocol.register { _ in .ok(body) }
        let client = RIPEstatClient(session: stub.session, baseURL: stub.baseURL)
        let first = try await client.whatsMyIP()
        let second = try await client.whatsMyIP()
        #expect(first.ip == "91.107.240.242" && second.ip == first.ip)
        let requests = StubProtocol.recorded(stub.host)
        #expect(requests.count == 2)            // never served from the response cache
        let request = try #require(requests.first)
        #expect(request.call == "whats-my-ip")
        #expect(request.timeoutInterval == 10)
        let query = try #require(request.url?.query)
        #expect(query == "sourceapp=ahmadrezaei-iptools")   // no resource parameter
    }

    @Test func clientTimeoutMapsToTimeout() async {
        let stub = StubProtocol.register { _ in .fail(.timedOut) }
        let client = RIPEstatClient(session: stub.session, baseURL: stub.baseURL)
        await #expect(throws: RIPEstatError.timeout) { try await client.whatsMyIP() }
    }

    @Test func mockServesFixture() async throws {
        let mock = MockRIPEstat(fixtureBundle: Bundle.module, latency: .zero)
        #expect(try await mock.whatsMyIP().ip == "91.107.240.242")
    }

    @Test func mockWithoutFixturesFallsBack() async throws {
        let mock = MockRIPEstat(fixtureBundle: Bundle(for: StubProtocol.self), latency: .zero)
        #expect(try await mock.whatsMyIP().ip == "91.107.240.242")
    }

    @Test func defaultImplementationThrowsForOldFakes() async {
        struct Fake: RIPEstatAPI {
            func networkInfo(_ ip: String) async throws -> NetworkInfo { fatalError() }
            func prefixOverview(_ prefix: String) async throws -> PrefixOverview { fatalError() }
            func lookingGlass(_ resource: String) async throws -> LookingGlass { fatalError() }
            func asOverview(_ asn: UInt32) async throws -> ASOverview { fatalError() }
            func asNames(_ asns: [UInt32]) async throws -> [UInt32: String] { fatalError() }
            func announcedPrefixes(_ asn: UInt32) async throws -> [String] { fatalError() }
            func routingStatus(_ prefix: String) async throws -> RoutingStatus { fatalError() }
        }
        await #expect(throws: RIPEstatError.self) { try await Fake().whatsMyIP() }
    }
}
