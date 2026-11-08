// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import BGPGraph
import Foundation
import Observation

public enum BGPView: String, Sendable, CaseIterable { case yourRoute, allRoutes }

@MainActor @Observable public final class YourRouteModel {
    public enum Phase: Equatable {
        case idle, locating, measuring(ttl: Int), done, partial(String), stopped(String),
             lookupsOff, unavailable, failed(String)
    }
    public private(set) var phase: Phase = .idle
    public private(set) var chain: ASChain?
    public private(set) var myNetwork: MyNetwork?
    public var selection: String?                     // ASChain.Node.id

    public init() {}

    public func measureAgain() { fatalError("TODO") }
    public func stop(reason: String? = nil) {}
    public var exportText: String { fatalError("TODO") }              // DESIGN 6.11.11
    public var accessibilitySentence: String { fatalError("TODO") }   // DESIGN 6.11.10
}
