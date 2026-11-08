// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SwiftUI

/// What the expanded card says about a your-path measurement that did not give a full path.
enum RouteNotice: Equatable {
    case none
    /// Partial or stopped: the path can be measured again.
    case measureAgain
    /// Failed, or no measurement service.
    case unavailable
    /// "Look up networks" is off, so there is nothing to measure with.
    case lookupsOff
}

/// Prefix, origin(s) and summary chips above the graph.
struct PrefixHeaderCard: View {
    let result: BGPResult?
    var hostLine: String?
    var isLoading = false
    var showUpdated = false
    var yourPath: YourPathStatus = .hidden
    var routeNotice: RouteNotice = .none
    var onYourPath: () -> Void = {}
    var onMeasureAgain: () -> Void = {}
    var onTurnOnLookups: () -> Void = {}
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
                chips(result)
                routeNoticeRow
                if yourPath != .hidden {
                    Text("Your public IP and the routers' addresses were looked up at RIPEstat (RIPE NCC).")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else if isLoading {
                Text(verbatim: "0.0.0.0/24").font(.system(size: 20, weight: .bold, design: .monospaced))
                Text(verbatim: "Origin AS00000 Placeholder").font(.subheadline)
                Text(verbatim: "000 paths · 00 collectors").font(.caption)
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

    private func chips(_ result: BGPResult) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                yourPathChip
                if result.originASNs.count > 1 {
                    chip(String(localized: "\(result.originASNs.count) origin ASes"), systemImage: "exclamationmark.triangle.fill", tint: .orange)
                }
                chip(String(localized: "\(result.graph.totalPaths) paths"))
                chip(String(localized: "\(result.collectors.count) collectors"))
                if let visibility = result.visibility {
                    chip(String(localized: "Seen by \(visibility.seeing)/\(visibility.total) peers"))
                }
                if result.graph.totalPaths < 3 {
                    chip(String(localized: "Seen by few collectors"), tint: .orange)
                }
                if showUpdated, let time = result.latestTime {
                    chip(String(localized: "Updated \(Self.timeFormatter.string(from: time)) UTC"))
                }
            }
        }
    }

    @ViewBuilder private var routeNoticeRow: some View {
        switch routeNotice {
        case .none:
            EmptyView()
        case .measureAgain:
            Button(action: onMeasureAgain) {
                Label("Measure again", systemImage: "arrow.clockwise").font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered).controlSize(.small)
        case .unavailable:
            chip(String(localized: "Your path unavailable"), systemImage: "exclamationmark.triangle", tint: .orange)
        case .lookupsOff:
            HStack(spacing: 8) {
                Text("Turn on network lookups to see your path").font(.caption).foregroundStyle(.secondary)
                Button("Turn On", action: onTurnOnLookups).buttonStyle(.bordered).controlSize(.small)
            }
        }
    }

    @ViewBuilder private var yourPathChip: some View {
        switch yourPath {
        case .hidden:
            EmptyView()
        case .measuring:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Measuring your path…")
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(Color.secondary.opacity(0.12)))
            .accessibilityElement(children: .combine)
        case .shown:
            Button(action: onYourPath) { chipLabel(String(localized: "━ Your path"), tint: .blue) }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Your path"))
                .accessibilityHint(Text("Shows details of your network"))
        case .partial:
            Button(action: onYourPath) { chipLabel(String(localized: "Your path: partial"), tint: .orange) }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Shows details of your network"))
        }
    }

    private func chipLabel(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.18)))
    }

    private func chip(_ text: String, systemImage: String? = nil, tint: Color = .secondary) -> some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(tint == .secondary ? Color.primary : tint)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(tint == .secondary ? 0.12 : 0.18)))
    }

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

/// Collapsed header: line 1 is the prefix with the your-path glyph, line 2 the origin.
struct PrefixCompactLabel: View {
    let prefix: String
    let origin: String
    var yourPath: YourPathStatus = .hidden

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(verbatim: prefix)
                    .font(.system(.footnote, design: .monospaced).weight(.bold))
                    .lineLimit(1)
                glyph.fixedSize()
            }
            Text(verbatim: origin)
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var glyph: some View {
        switch yourPath {
        case .hidden:
            EmptyView()
        case .measuring:
            ProgressView().controlSize(.mini)
                .accessibilityLabel(Text("Measuring your path"))
        case .shown:
            Capsule().fill(Color.blue).frame(width: 16, height: 3)
                .accessibilityLabel(Text("Your path shown"))
        case .partial:
            DashedLine()
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [4, 3]))
                .frame(width: 16, height: 3)
                .accessibilityLabel(Text("Your path partial"))
        }
    }
}

private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
