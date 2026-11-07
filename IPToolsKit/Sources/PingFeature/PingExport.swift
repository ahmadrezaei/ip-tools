// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore
import SharedUI

/// CLI-style text export of a ping run (DESIGN §4.6).
enum PingExport {
    static func text(target: ResolvedTarget?, samples: [PingSample], stats: PingStatistics,
                     payloadSize: Int = 56, date: Date = Date()) -> String {
        let name = target?.hostname ?? target?.input ?? ""
        let address = target?.address.description ?? name
        let display = target?.input ?? name
        var lines = ["PING \(display) (\(address)): \(payloadSize) data bytes"]

        for sample in samples {
            switch sample.outcome {
            case let .reply(rtt, bytes, ttl, from):
                var line = "\(bytes) bytes from \(from): icmp_seq=\(sample.sequence)"
                if let ttl { line += " ttl=\(ttl)" }
                line += " time=\(Format.ms(rtt)) ms"
                lines.append(line)
            case .timeout:
                lines.append("Request timeout for icmp_seq \(sample.sequence)")
            case let .unreachable(code, from):
                let reason = UnreachableReason(code: code, family: from.family)
                lines.append("From \(from) icmp_seq=\(sample.sequence) Destination \(reason.noun.capitalized) Unreachable")
            case let .error(error):
                lines.append("ping: icmp_seq=\(sample.sequence) \(ToolError(error).title)")
            }
        }

        lines.append("--- \(display) ping statistics ---")
        lines.append("\(stats.sent) packets transmitted, \(stats.received) packets received, "
            + String(format: "%.1f%% packet loss", stats.lossFraction * 100))
        if let min = stats.min, let avg = stats.avg, let max = stats.max, let stddev = stats.stddev {
            var line = "round-trip min/avg/max/stddev = \(Format.ms(min))/\(Format.ms(avg))/\(Format.ms(max))/\(Format.ms(stddev)) ms"
            if let jitter = stats.jitter { line += ", jitter \(Format.ms(jitter)) ms" }
            lines.append(line)
        }
        lines.append(Format.exportFooter(date))
        return lines.joined(separator: "\n")
    }
}
