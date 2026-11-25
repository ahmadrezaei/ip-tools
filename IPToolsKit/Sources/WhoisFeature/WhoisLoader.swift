// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore
import RIPEstat

public struct WhoisResult: Hashable, Sendable {
    public let subject: WhoisSubject
    public let summary: WhoisSummary
    public let raw: WhoisResponse?
    /// "2001:4860::/32" after the ARIN IPv6 retry.
    public let retriedWith: String?
    public let reverseName: String?
    public let location: GeoLocation?
    public let fetchedAt: Date

    public init(subject: WhoisSubject, summary: WhoisSummary, raw: WhoisResponse?, retriedWith: String?,
                reverseName: String?, location: GeoLocation?, fetchedAt: Date) {
        self.subject = subject
        self.summary = summary
        self.raw = raw
        self.retriedWith = retriedWith
        self.reverseName = reverseName
        self.location = location
        self.fetchedAt = fetchedAt
    }
}

public enum WhoisLoad: Hashable, Sendable { case loading, loaded(WhoisResult), failed(WhoisFailure) }

/// Request plans of DESIGN §14.8.
struct WhoisLoader: Sendable {
    private let api: any RIPEstatAPI
    private let reverseName: @Sendable (IPAddress) async -> String?
    private let includeLocation: Bool

    init(api: any RIPEstatAPI, reverseName: @escaping @Sendable (IPAddress) async -> String?, includeLocation: Bool) {
        self.api = api
        self.reverseName = reverseName
        self.includeLocation = includeLocation
    }

    /// Throws `WhoisFailure` or `CancellationError`.
    func load(_ subject: WhoisSubject) async throws -> WhoisResult { fatalError("TODO") }
}
