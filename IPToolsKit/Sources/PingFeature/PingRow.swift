// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import NetCore
import SharedUI
import SwiftUI

/// One reply line: colour dot, #seq, details, RTT.
struct PingRow: View {
    let sample: PingSample

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(dotColor).frame(width: 9, height: 9).accessibilityHidden(true)
            Text("#\(sample.sequence)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 34, alignment: .leading)
            switch sample.outcome {
            case let .reply(rtt, bytes, ttl, _):
                Text(detail(bytes: bytes, ttl: ttl)).font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(Format.rtt(rtt)).font(.body.weight(.semibold).monospacedDigit())
            case .timeout:
                Text("Request timed out").font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            case let .unreachable(code, from):
                Text(UnreachableReason(code: code, family: from.family).pingDescription)
                    .font(.subheadline).foregroundStyle(.red)
                Spacer(minLength: 0)
            case let .error(error):
                Text(ToolError(error).title).font(.subheadline).foregroundStyle(.red)
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .copyContextMenu(copyText)
    }

    private var dotColor: Color {
        switch sample.outcome {
        case let .reply(rtt, _, _, _): RTTColor.color(for: rtt)
        case .timeout: RTTColor.color(for: nil)
        case .unreachable, .error: .red
        }
    }

    private func detail(bytes: Int, ttl: Int?) -> String {
        if let ttl { return String(localized: "\(bytes) bytes · ttl \(ttl)") }
        return String(localized: "\(bytes) bytes")
    }

    private var copyText: String {
        switch sample.outcome {
        case let .reply(rtt, bytes, ttl, from):
            "\(bytes) bytes from \(from): icmp_seq=\(sample.sequence)" + (ttl.map { " ttl=\($0)" } ?? "") + " time=\(Format.ms(rtt)) ms"
        case .timeout: "Request timeout for icmp_seq \(sample.sequence)"
        case let .unreachable(code, from): "icmp_seq=\(sample.sequence) " + UnreachableReason(code: code, family: from.family).pingDescription
        case let .error(error): "icmp_seq=\(sample.sequence) " + ToolError(error).title
        }
    }
}

#Preview {
    let ip = IPAddress("1.1.1.1")!
    VStack(spacing: 0) {
        PingRow(sample: PingSample(sequence: 4, sentAt: Date(), outcome: .reply(rtt: 0.0136, bytes: 64, ttl: 58, from: ip)))
        PingRow(sample: PingSample(sequence: 3, sentAt: Date(), outcome: .reply(rtt: 0.136, bytes: 64, ttl: 58, from: ip)))
        PingRow(sample: PingSample(sequence: 2, sentAt: Date(), outcome: .reply(rtt: 0.321, bytes: 64, ttl: nil, from: ip)))
        PingRow(sample: PingSample(sequence: 1, sentAt: Date(), outcome: .timeout))
        PingRow(sample: PingSample(sequence: 0, sentAt: Date(), outcome: .unreachable(code: 1, from: ip)))
    }
    .cardStyle()
    .padding()
}
