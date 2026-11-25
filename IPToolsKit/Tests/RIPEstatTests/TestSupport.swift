// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import Testing
@testable import RIPEstat

enum Fixture {
    static func data(_ name: String, ext: String = "json") throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    /// A hand-built raw HTTP/1.1 response (`http_<name>.bin`).
    static func http(_ name: String) throws -> Data { try data("http_\(name)", ext: "bin") }

    static func date(_ text: String) -> Date? { DateParsing.parse(text) }

    // Decoded fixtures for the whois tests.
    static func whois(_ key: String, resource: String? = nil) throws -> WhoisResponse {
        try WhoisParsing.whois(data("whois_\(key)"), resource: resource ?? key)
    }

    static func network(_ key: String) throws -> NetworkInfo { try RIPEstatParsing.networkInfo(data("network-info_\(key)")) }
    static func abuse(_ key: String) throws -> AbuseContacts { try WhoisParsing.abuse(data("abuse-contact-finder_\(key)")) }
    static func country(_ key: String) throws -> String? { try WhoisParsing.country(data("rir-stats-country_\(key)")) }

    static func asOverview(_ asn: UInt32) throws -> ASOverview {
        try RIPEstatParsing.asOverview(data("as-overview_AS\(asn)"), asn: asn)
    }

    static func names() throws -> [UInt32: String] {
        try RIPEstatParsing.asNames(data("as-names_15169-3333-22548-24940"))
    }
}

/// What a stubbed endpoint answers.
enum StubReply: Sendable {
    case ok(Data, status: Int = 200)
    case fail(URLError.Code)
}

/// URLProtocol stub. Each test uses its own host (`t<uuid>.test`), so tests can run in parallel.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) -> StubReply
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]
    nonisolated(unsafe) private static var requests: [String: [URLRequest]] = [:]
    private static let lock = NSLock()

    static func register(_ handler: @escaping Handler) -> (host: String, baseURL: URL, session: URLSession) {
        let host = "t\(UUID().uuidString.prefix(8).lowercased()).test"
        lock.lock(); handlers[host] = handler; requests[host] = []; lock.unlock()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return (host, URL(string: "https://\(host)/data/")!, URLSession(configuration: config))
    }

    static func recorded(_ host: String) -> [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return requests[host] ?? []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        Self.lock.lock()
        let handler = Self.handlers[host]
        Self.requests[host, default: []].append(request)
        Self.lock.unlock()
        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        switch handler(request) {
        case .fail(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .ok(let data, let status):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

extension URLRequest {
    /// "bgp-state" for `.../data/bgp-state/data.json?...`.
    var call: String { url?.pathComponents.dropLast().last ?? "" }
    var resource: String {
        URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "resource" }?.value ?? ""
    }
}
