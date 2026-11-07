// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore
import SharedUI

/// CLI-style text export of a traceroute (DESIGN §5.6).
enum TraceExport {
    static func text(target: ResolvedTarget?, options: TraceOptions, hops: [TraceHop], date: Date = Date()) -> String {
        let input = target?.input ?? ""
        let address = target?.address.description ?? input
        var lines = ["traceroute to \(input) (\(address)), \(options.maxHops) hops max, \(options.probesPerHop) probes"]
        for hop in hops { lines.append(line(for: hop, probes: options.probesPerHop)) }
        lines.append(Format.exportFooter(date))
        return lines.joined(separator: "\n")
    }

    static func line(for hop: TraceHop, probes: Int) -> String {
        let number = String(format: "%2d", hop.ttl)
        guard let first = hop.addresses.first else {
            return number + "  " + Array(repeating: "*", count: max(probes, hop.probes.count)).joined(separator: " ")
        }
        var label = hop.hostname.map { "\($0) (\(first))" } ?? first.description
        if let asn = hop.asn { label += " [AS\(asn.asn)]" }
        if hop.otherAddressCount > 0 { label += " +\(hop.otherAddressCount) other" }
        let times = hop.probes.map { probe in probe.rtt.map { "\(Format.ms($0)) ms" } ?? "*" }
        var result = number + "  " + label + "  " + times.joined(separator: "  ")
        if let reason = hop.unreachableReason { result += "  " + reason.flag }
        return result
    }
}
