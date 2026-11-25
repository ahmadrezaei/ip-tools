// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import Network
import Testing
@testable import RIPEstat

private let networkTestsEnabled = ProcessInfo.processInfo.environment["IPTOOLS_NET_TESTS"] == "1"

@Suite struct HTTP1ResponseTests {
    private func bytes(_ text: String) -> Data { Data(text.utf8) }

    @Test func contentLengthFixture() throws {
        let parsed = try HTTP1Response.parse(Fixture.http("whats-my-ip_content-length"))
        #expect(parsed.status == 200)
        #expect(parsed.headers["content-type"] == "application/json")
        #expect(parsed.headers["content-length"] == String(parsed.body.count))
        #expect(try RIPEstatParsing.whatsMyIP(parsed.body).ip == "193.0.6.139")
    }

    @Test func chunkedFixtureDecodesToTheSameBody() throws {
        let chunked = try HTTP1Response.parse(Fixture.http("whats-my-ip_chunked"))
        let plain = try HTTP1Response.parse(Fixture.http("whats-my-ip_content-length"))
        #expect(chunked.status == 200)
        #expect(chunked.headers["transfer-encoding"] == "chunked")
        #expect(chunked.body == plain.body)
    }

    @Test func tooManyRequests() throws {
        let parsed = try HTTP1Response.parse(Fixture.http("429"))
        #expect(parsed.status == 429)
        #expect(parsed.headers["retry-after"] == "5")
    }

    @Test func nginxBadGatewayHTML() throws {
        let parsed = try HTTP1Response.parse(Fixture.http("502_html"))
        #expect(parsed.status == 502)
        #expect(parsed.headers["content-type"] == "text/html")
        #expect(String(decoding: parsed.body, as: UTF8.self).contains("502 Bad Gateway"))
    }

    @Test func headerNamesAreCaseInsensitive() throws {
        let parsed = try HTTP1Response.parse(bytes("HTTP/1.1 200 OK\r\nCONTENT-length: 2\r\nX-Odd:   spaced  \r\n\r\nhiEXTRA"))
        #expect(parsed.body == bytes("hi"))                         // never reads past Content-Length
        #expect(parsed.headers["content-length"] == "2")
        #expect(parsed.headers["x-odd"] == "spaced")
    }

    @Test func truncatedResponsesAreIncomplete() throws {
        let full = try Fixture.http("whats-my-ip_content-length")
        #expect(throws: HTTP1Response.ParseError.incomplete) { try HTTP1Response.parse(full.dropLast(5)) }
        #expect(throws: HTTP1Response.ParseError.incomplete) { try HTTP1Response.parse(full.prefix(20)) }
        #expect(throws: HTTP1Response.ParseError.incomplete) { try HTTP1Response.parse(Data()) }
        let chunked = try Fixture.http("whats-my-ip_chunked")
        for cut in [1, 3, 7, 30] {
            #expect(throws: HTTP1Response.ParseError.incomplete) { try HTTP1Response.parse(chunked.dropLast(cut)) }
        }
    }

    @Test func bodyWithoutFramingRunsToEOF() throws {
        let raw = bytes("HTTP/1.1 200 OK\r\nConnection: close\r\n\r\nhello")
        #expect(throws: HTTP1Response.ParseError.incomplete) { try HTTP1Response.parse(raw, atEOF: false) }
        let parsed = try HTTP1Response.parse(raw, atEOF: true)
        #expect(parsed.body == bytes("hello"))
        #expect(try HTTP1Response.parse(raw).body == bytes("hello"))   // EOF is the default
    }

    @Test func noBodyResponses() throws {
        let parsed = try HTTP1Response.parse(bytes("HTTP/1.1 204 No Content\r\nContent-Length: 0\r\n\r\n"))
        #expect(parsed.status == 204)
        #expect(parsed.body.isEmpty)
    }

    @Test func chunkTrailersAndExtensions() throws {
        let raw = bytes("HTTP/1.1 200 OK\r\nTransfer-Encoding: Chunked\r\n\r\n3;x=y\r\nabc\r\n2\r\nde\r\n0\r\nTrailer: v\r\n\r\n")
        #expect(try HTTP1Response.parse(raw).body == bytes("abcde"))
        let missingTrailerEnd = bytes("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1\r\na\r\n0\r\nTrailer: v\r\n")
        #expect(throws: HTTP1Response.ParseError.incomplete) { try HTTP1Response.parse(missingTrailerEnd) }
    }

    @Test func malformedResponses() {
        let cases = [
            "SMTP/1.0 220 hi\r\n\r\n",
            "HTTP/1.1 abc OK\r\n\r\n",
            "HTTP/1.1\r\n\r\n",
            "HTTP/1.1 200 OK\r\nno colon here\r\n\r\n",
            "HTTP/1.1 200 OK\r\nContent-Length: -4\r\n\r\n",
            "HTTP/1.1 200 OK\r\nContent-Length: five\r\n\r\n",
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nzz\r\nab\r\n",
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\nabXX0\r\n\r\n",
        ]
        for text in cases {
            #expect(throws: HTTP1Response.ParseError.malformed, Comment(rawValue: text)) {
                try HTTP1Response.parse(Data(text.utf8))
            }
        }
        #expect(throws: HTTP1Response.ParseError.malformed) { try HTTP1Response.parse(Data(repeating: 0x41, count: 20_000)) }
    }

    @Test func bodyIsCappedAt64KB() throws {
        let limit = HTTP1Response.bodyLimit
        #expect(limit == 64 * 1024)
        let head = "HTTP/1.1 200 OK\r\nContent-Length: \(limit + 1)\r\n\r\n"
        #expect(throws: HTTP1Response.ParseError.tooLarge) {
            try HTTP1Response.parse(Data(head.utf8) + Data(repeating: 0x61, count: limit + 1))
        }
        let exact = "HTTP/1.1 200 OK\r\nContent-Length: \(limit)\r\n\r\n"
        #expect(try HTTP1Response.parse(Data(exact.utf8) + Data(repeating: 0x61, count: limit)).body.count == limit)
        let big = String(limit + 1, radix: 16)
        let chunked = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n\(big)\r\n"
        #expect(throws: HTTP1Response.ParseError.tooLarge) {
            try HTTP1Response.parse(Data(chunked.utf8) + Data(repeating: 0x61, count: limit + 1) + Data("\r\n0\r\n\r\n".utf8))
        }
        let overflow = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1\r\na\r\n7fffffffffffffff\r\n"
        #expect(throws: HTTP1Response.ParseError.tooLarge) { try HTTP1Response.parse(Data(overflow.utf8)) }
        let streaming = Data("HTTP/1.1 200 OK\r\n\r\n".utf8) + Data(repeating: 0x61, count: limit + 1)
        #expect(throws: HTTP1Response.ParseError.tooLarge) { try HTTP1Response.parse(streaming, atEOF: false) }
        #expect(throws: HTTP1Response.ParseError.tooLarge) { try HTTP1Response.parse(streaming, atEOF: true) }
    }
}

@Suite struct PublicIPTests {
    private typealias Call = (host: String, path: String, headers: [String: String], version: IPVersion, timeout: TimeInterval)

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [Call] = []
        func add(_ call: Call) { lock.lock(); items.append(call); lock.unlock() }
        var calls: [Call] { lock.lock(); defer { lock.unlock() }; return items }
    }

    private func client(recorder: Recorder, reply: @escaping @Sendable (IPVersion) throws -> (status: Int, body: Data)) -> RIPEstatClient {
        RIPEstatClient(session: .shared, baseURL: URL(string: "https://stat.example.test/data/")!,
                       sourceApp: "ahmadrezaei-iptools", maxConcurrent: 4,
                       pinnedGet: { host, path, headers, version, timeout in
                           recorder.add((host, path, headers, version, timeout))
                           return try reply(version)
                       })
    }

    @Test func requestShapeNeverCachedEightSecondTimeout() async throws {
        let body = try Fixture.data("whats-my-ip_v4")
        let recorder = Recorder()
        let client = client(recorder: recorder) { _ in (200, body) }
        #expect(try await client.whatsMyIP(over: .v4).ip == "193.0.6.139")
        #expect(try await client.whatsMyIP(over: .v4).ip == "193.0.6.139")
        let calls = recorder.calls
        #expect(calls.count == 2)                                   // nothing cached
        #expect(calls[0].host == "stat.example.test")
        #expect(calls[0].path == "/data/whats-my-ip/data.json?sourceapp=ahmadrezaei-iptools")
        #expect(calls[0].timeout == 8)
        #expect(calls[0].version == .v4)
        #expect(calls[0].headers["Accept"] == "application/json")
        #expect(calls[0].headers["User-Agent"]?.hasPrefix("IPTools/") == true)
    }

    @Test func bothFamiliesUseTheirFixture() async throws {
        let v4 = try Fixture.data("whats-my-ip_v4")
        let v6 = try Fixture.data("whats-my-ip_v6")
        let client = client(recorder: Recorder()) { version in (200, version == .v4 ? v4 : v6) }
        #expect(try await client.whatsMyIP(over: .v4).ip == "193.0.6.139")
        #expect(try await client.whatsMyIP(over: .v6).ip == "2001:67c:2e8:22::c100:696")
    }

    @Test func statusMapping() throws {
        let ok = try Fixture.data("whats-my-ip_v4")
        #expect(try RIPEstatClient.interpretPinned(status: 200, body: ok).ip == "193.0.6.139")
        #expect(throws: RIPEstatError.rateLimited) { try RIPEstatClient.interpretPinned(status: 429, body: Data()) }
        #expect(throws: PublicIPError.badResponse(status: 502)) { try RIPEstatClient.interpretPinned(status: 502, body: Data()) }
        #expect(throws: PublicIPError.badResponse(status: 404)) { try RIPEstatClient.interpretPinned(status: 404, body: ok) }
        #expect(throws: RIPEstatError.self) { try RIPEstatClient.interpretPinned(status: 200, body: Data("<html>".utf8)) }
    }

    @Test func fixturesThroughTheRawHTTPParser() async throws {
        let raw = try Fixture.http("429")
        let client = client(recorder: Recorder()) { _ in
            let parsed = try HTTP1Response.parse(raw)
            return (parsed.status, parsed.body)
        }
        await #expect(throws: RIPEstatError.rateLimited) { try await client.whatsMyIP(over: .v6) }
        let html = try Fixture.http("502_html")
        let badGateway = self.client(recorder: Recorder()) { _ in
            let parsed = try HTTP1Response.parse(html)
            return (parsed.status, parsed.body)
        }
        await #expect(throws: PublicIPError.badResponse(status: 502)) { try await badGateway.whatsMyIP(over: .v4) }
    }

    @Test func transportErrorsPropagateAndReleaseTheGate() async throws {
        let body = try Fixture.data("whats-my-ip_v4")
        let client = RIPEstatClient(session: .shared, baseURL: URL(string: "https://stat.example.test/data/")!,
                                    sourceApp: "x", maxConcurrent: 1,
                                    pinnedGet: { _, _, _, version, _ in
                                        if version == .v6 { throw PublicIPError.noRoute(.v6) }
                                        return (200, body)
                                    })
        for _ in 0..<3 {
            await #expect(throws: PublicIPError.noRoute(.v6)) { try await client.whatsMyIP(over: .v6) }
        }
        #expect(try await client.whatsMyIP(over: .v4).ip == "193.0.6.139")   // a single slot is free again
    }

    @Test func requestBytes() {
        let data = PinnedHTTPGet.requestBytes(host: "stat.ripe.net", path: "/data/whats-my-ip/data.json?sourceapp=x",
                                              headers: ["User-Agent": "UA", "Accept": "application/json", "Host": "evil", "connection": "keep-alive"])
        let text = String(decoding: data, as: UTF8.self)
        #expect(text == "GET /data/whats-my-ip/data.json?sourceapp=x HTTP/1.1\r\nHost: stat.ripe.net\r\n"
            + "Accept: application/json\r\nUser-Agent: UA\r\nConnection: close\r\n\r\n")
    }

    @Test func networkErrorMapping() {
        #expect(PinnedHTTPGet.map(.posix(.ENETUNREACH), version: .v6) == .noRoute(.v6))
        #expect(PinnedHTTPGet.map(.posix(.EHOSTUNREACH), version: .v4) == .noRoute(.v4))
        #expect(PinnedHTTPGet.map(.posix(.ETIMEDOUT), version: .v4) == .timeout(.v4))
        #expect(PinnedHTTPGet.map(.posix(.ECONNRESET), version: .v4) == .badResponse(status: 0))
        #expect(PinnedHTTPGet.map(.dns(-65554), version: .v6) == .noRoute(.v6))
        #expect(PinnedHTTPGet.map(.dns(-65568), version: .v6) == .badResponse(status: 0))
        #expect(PinnedHTTPGet.map(.posix(.ECONNREFUSED), version: .v4) == .badResponse(status: 0))
        #expect(PinnedHTTPGet.map(.tls(-9807), version: .v4) == .tls)
    }

    @Test func publicIPErrorsAreEquatable() {
        #expect(PublicIPError.noRoute(.v4) != PublicIPError.noRoute(.v6))
        #expect(PublicIPError.timeout(.v4) == PublicIPError.timeout(.v4))
        #expect(IPVersion.allCases == [.v4, .v6])
    }

    // MARK: Live (never in CI): IPTOOLS_NET_TESTS=1

    @Test(.enabled(if: networkTestsEnabled)) func livePinnedIPv4ReturnsAnIPv4Address() async throws {
        let client = RIPEstatClient()
        let result = try await client.whatsMyIP(over: .v4)
        let parts = result.ip.split(separator: ".")
        #expect(parts.count == 4)
        #expect(parts.allSatisfy { UInt8($0) != nil })
    }

    @Test(.enabled(if: networkTestsEnabled)) func livePinnedIPv6ReturnsAnIPv6AddressOrNoRoute() async throws {
        let client = RIPEstatClient()
        do {
            let result = try await client.whatsMyIP(over: .v6)
            #expect(result.ip.contains(":"))
        } catch PublicIPError.noRoute(let version) {
            #expect(version == .v6)
        }
    }
}
