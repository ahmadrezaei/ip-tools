// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SwiftUI

public enum Tool: String, CaseIterable, Codable, Identifiable, Sendable {
    case ping, traceroute, bgp
    public var id: String { rawValue }

    public var title: LocalizedStringKey {
        switch self {
        case .ping: "Ping"
        case .traceroute: "Traceroute"
        case .bgp: "BGP Map"
        }
    }

    public var systemImage: String {
        switch self {
        case .ping: "dot.radiowaves.left.and.right"
        case .traceroute: "point.topleft.down.to.point.bottomright.curvepath"
        case .bgp: "point.3.connected.trianglepath.dotted"
        }
    }
}
