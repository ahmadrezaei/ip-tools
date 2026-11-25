// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation

/// One HTTP/1.1 GET over an NWConnection pinned to an address family (DESIGN §14.5).
struct PinnedHTTPGet {
    static func get(host: String, path: String, headers: [String: String], version: IPVersion,
                    timeout: TimeInterval) async throws -> (status: Int, body: Data) {
        fatalError("TODO")
    }
}

/// Minimal HTTP/1.1 response parser: status line, case-insensitive headers, Content-Length, chunked, 64 KB body cap.
enum HTTP1Response {
    static func parse(_ raw: Data) throws -> (status: Int, headers: [String: String], body: Data) {
        fatalError("TODO")
    }
}
