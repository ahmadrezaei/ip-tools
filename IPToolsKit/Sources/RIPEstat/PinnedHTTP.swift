// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import Network

/// One HTTP/1.1 GET over an NWConnection pinned to an address family (DESIGN §14.5).
///
/// Thin transport shell: connection set-up, timeouts and the "no route for this family" decision live here and
/// are exercised by the live test only. Everything about the bytes is in `HTTP1Response`, which is unit-tested.
struct PinnedHTTPGet {
    /// How long a connection may sit in `.waiting` before it is declared "no route for this family".
    static let noRouteGrace: TimeInterval = 1.5
    static let tcpConnectTimeout = 6

    static func get(host: String, path: String, headers: [String: String], version: IPVersion,
                    timeout: TimeInterval) async throws -> (status: Int, body: Data) {
        let request = requestBytes(host: host, path: path, headers: headers)
        let exchange = Exchange(version: version)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                exchange.start(host: host, request: request, timeout: timeout, continuation: continuation)
            }
        } onCancel: {
            exchange.cancel()
        }
    }

    static func requestBytes(host: String, path: String, headers: [String: String]) -> Data {
        var lines = ["GET \(path) HTTP/1.1", "Host: \(host)"]
        for key in headers.keys.sorted() where key.lowercased() != "host" && key.lowercased() != "connection" {
            lines.append("\(key): \(headers[key] ?? "")")
        }
        lines.append("Connection: close")
        return Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
    }

    /// Maps a Network.framework failure to the error the model reasons about.
    static func map(_ error: NWError, version: IPVersion) -> PublicIPError {
        switch error {
        case .tls:
            return .tls
        case .dns:
            return .noRoute(version)
        case .posix(let code):
            switch code {
            case .ENETUNREACH, .EHOSTUNREACH, .ENETDOWN, .EADDRNOTAVAIL, .EAFNOSUPPORT, .ENOENT:
                return .noRoute(version)
            case .ETIMEDOUT:
                return .timeout(version)
            default:
                return .badResponse(status: 0)
            }
        default:
            return .badResponse(status: 0)
        }
    }
}

/// State of one request. All mutable state is guarded by `lock`; Network.framework calls back on `queue`.
private final class Exchange: @unchecked Sendable {
    private let version: IPVersion
    private let queue = DispatchQueue(label: "ripestat.pinned-get")
    private let lock = NSLock()
    private var continuation: CheckedContinuation<(status: Int, body: Data), any Error>?
    private var connection: NWConnection?
    private var buffer = Data()
    private var waiting = false
    private var cancelled = false

    init(version: IPVersion) { self.version = version }

    func start(host: String, request: Data, timeout: TimeInterval,
               continuation: CheckedContinuation<(status: Int, body: Data), any Error>) {
        lock.lock()
        if cancelled {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = PinnedHTTPGet.tcpConnectTimeout
        let parameters = NWParameters(tls: NWProtocolTLS.Options(), tcp: tcp)
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = version == .v4 ? .v4 : .v6
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: 443, using: parameters)
        self.connection = connection
        lock.unlock()

        connection.stateUpdateHandler = { [weak self] state in self?.handle(state, request: request) }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self else { return }
            finish(.failure(PublicIPError.timeout(version)))
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
        finish(.failure(CancellationError()))
    }

    private func handle(_ state: NWConnection.State, request: Data) {
        switch state {
        case .ready:
            setWaiting(false)
            send(request)
        case .waiting:
            setWaiting(true)
            queue.asyncAfter(deadline: .now() + PinnedHTTPGet.noRouteGrace) { [weak self] in
                guard let self, isWaiting() else { return }
                finish(.failure(PublicIPError.noRoute(version)))
            }
        case .failed(let error):
            finish(.failure(PinnedHTTPGet.map(error, version: version)))
        case .setup, .preparing:
            setWaiting(false)
        case .cancelled:
            break
        @unknown default:
            break
        }
    }

    private func setWaiting(_ value: Bool) {
        lock.lock()
        waiting = value
        lock.unlock()
    }

    private func isWaiting() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return waiting
    }

    private func send(_ request: Data) {
        guard let connection = currentConnection() else { return }
        connection.send(content: request, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if let error {
                finish(.failure(PinnedHTTPGet.map(error, version: version)))
            } else {
                receive()
            }
        })
    }

    private func currentConnection() -> NWConnection? {
        lock.lock()
        defer { lock.unlock() }
        return connection
    }

    private func receive() {
        guard let connection = currentConnection() else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data { buffer.append(data) }
            if let error {
                finish(.failure(PinnedHTTPGet.map(error, version: version)))
                return
            }
            do {
                let parsed = try HTTP1Response.parse(buffer, atEOF: isComplete)
                finish(.success((parsed.status, parsed.body)))
            } catch HTTP1Response.ParseError.incomplete {
                if isComplete {
                    finish(.failure(PublicIPError.badResponse(status: 0)))
                } else {
                    receive()
                }
            } catch {
                finish(.failure(PublicIPError.badResponse(status: 0)))
            }
        }
    }

    private func finish(_ result: Result<(status: Int, body: Data), any Error>) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        let connection = connection
        self.connection = nil
        lock.unlock()
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        continuation?.resume(with: result)
    }
}

/// Minimal HTTP/1.1 response parser: status line, case-insensitive headers, Content-Length, chunked, 64 KB body cap.
enum HTTP1Response {
    enum ParseError: Error, Equatable {
        /// More bytes are needed (truncated head, body or chunk stream).
        case incomplete
        /// Not an HTTP/1.x response.
        case malformed
        /// The body is larger than `bodyLimit`.
        case tooLarge
    }

    static let bodyLimit = 64 * 1024

    /// Parses a complete response. `atEOF` says whether the peer has closed: a body without `Content-Length` or
    /// chunking runs to the end of the stream, so it is only complete at EOF. Header names are lower-cased.
    static func parse(_ raw: Data, atEOF: Bool = true) throws -> (status: Int, headers: [String: String], body: Data) {
        let bytes = Array(raw)
        let separator: [UInt8] = [0x0D, 0x0A, 0x0D, 0x0A]
        guard let headEnd = find(separator, in: bytes, from: 0) else {
            if bytes.count > 16 * 1024 { throw ParseError.malformed }
            throw ParseError.incomplete
        }
        let head = String(decoding: bytes[0..<headEnd], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let status = try statusCode(lines.removeFirst())
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { throw ParseError.malformed }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        let bodyStart = headEnd + separator.count
        let rest = Array(bytes[bodyStart...])
        let transfer = headers["transfer-encoding"]?.lowercased() ?? ""
        if transfer.contains("chunked") {
            return (status, headers, try decodeChunks(rest))
        }
        if let length = headers["content-length"] {
            guard let count = Int(length), count >= 0 else { throw ParseError.malformed }
            if count > bodyLimit { throw ParseError.tooLarge }
            guard rest.count >= count else { throw ParseError.incomplete }
            return (status, headers, Data(rest[0..<count]))
        }
        guard atEOF else {
            if rest.count > bodyLimit { throw ParseError.tooLarge }
            throw ParseError.incomplete
        }
        if rest.count > bodyLimit { throw ParseError.tooLarge }
        return (status, headers, Data(rest))
    }

    private static func statusCode(_ line: String) throws -> Int {
        let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2, parts[0].hasPrefix("HTTP/1."), parts[1].count == 3, let code = Int(parts[1]) else {
            throw ParseError.malformed
        }
        return code
    }

    private static func decodeChunks(_ bytes: [UInt8]) throws -> Data {
        var body = Data()
        var index = 0
        let crlf: [UInt8] = [0x0D, 0x0A]
        while true {
            guard let lineEnd = find(crlf, in: bytes, from: index) else { throw ParseError.incomplete }
            let sizeLine = String(decoding: bytes[index..<lineEnd], as: UTF8.self)
            let sizeText = sizeLine.split(separator: ";", maxSplits: 1).first.map(String.init) ?? ""
            guard let size = Int(sizeText.trimmingCharacters(in: .whitespaces), radix: 16), size >= 0 else {
                throw ParseError.malformed
            }
            index = lineEnd + 2
            if size == 0 {
                // Optional trailers, then the final blank line.
                while true {
                    guard let trailerEnd = find(crlf, in: bytes, from: index) else { throw ParseError.incomplete }
                    if trailerEnd == index { return body }
                    index = trailerEnd + 2
                }
            }
            if body.count + size > bodyLimit { throw ParseError.tooLarge }
            guard bytes.count >= index + size + 2 else { throw ParseError.incomplete }
            body.append(contentsOf: bytes[index..<(index + size)])
            guard bytes[index + size] == 0x0D, bytes[index + size + 1] == 0x0A else { throw ParseError.malformed }
            index += size + 2
        }
    }

    private static func find(_ needle: [UInt8], in haystack: [UInt8], from start: Int) -> Int? {
        guard haystack.count >= needle.count, start <= haystack.count - needle.count else { return nil }
        for i in start...(haystack.count - needle.count) where haystack[i] == needle[0] {
            if haystack[i..<(i + needle.count)].elementsEqual(needle) { return i }
        }
        return nil
    }
}
