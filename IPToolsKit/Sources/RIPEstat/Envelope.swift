// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation

/// Common RIPEstat response envelope. `data` decoding is specific to each call.
struct Envelope<Payload: Decodable & Sendable>: Decodable, Sendable {
    let status: String
    let statusCode: Int?
    let messages: [[String]]?
    let data: Payload?

    enum CodingKeys: String, CodingKey {
        case status
        case statusCode = "status_code"
        case messages
        case data
    }
}
