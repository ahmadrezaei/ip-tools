// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SwiftUI

/// Compact prefix and origin(s) above both views; the chips live in the All routes summary.
struct PrefixHeaderCard: View {
    let result: BGPResult?
    var hostLine: String?
    var isLoading = false
    var onSelectASN: (UInt32) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let result {
                Text(verbatim: result.prefix)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .textSelection(.enabled)
                if let hostLine {
                    Text(verbatim: hostLine).font(.footnote).foregroundStyle(.secondary)
                }
                originRows(result)
            } else if isLoading {
                Text(verbatim: "0.0.0.0/24").font(.system(size: 20, weight: .bold, design: .monospaced))
                Text(verbatim: "Origin AS00000 Placeholder").font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.05)))
        .redacted(reason: result == nil ? .placeholder : [])
        .padding(.horizontal)
        .accessibilityElement(children: result == nil ? .ignore : .contain)
    }

    private func originRows(_ result: BGPResult) -> some View {
        let origins = result.originASNs
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(origins.prefix(3), id: \.self) { asn in
                HStack(spacing: 6) {
                    Text(origins.count > 1 ? "Origin" : "Origin").font(.subheadline).foregroundStyle(.secondary)
                    Button { onSelectASN(asn) } label: {
                        Text(verbatim: "AS\(asn)")
                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Shows AS details"))
                    if let name = BGPText.fullName(result.holder(of: asn)) {
                        Text(name).font(.subheadline).lineLimit(1)
                    }
                }
            }
            if origins.count > 3 {
                Text("+\(origins.count - 3) more origins").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
