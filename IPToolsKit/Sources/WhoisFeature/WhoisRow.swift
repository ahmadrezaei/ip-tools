// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import SharedUI
import SwiftUI

/// Country names and flags for ISO 3166 region codes and the registry pseudo codes (EU, AP, ZZ).
enum CountryFormat {
    private static let pseudoCodes: Set<String> = ["EU", "AP", "ZZ"]

    private static let isoCodes = Set(Locale.Region.isoRegions.map(\.identifier))

    static func isCountry(_ code: String) -> Bool {
        let code = code.uppercased()
        return !pseudoCodes.contains(code) && isoCodes.contains(code)
    }

    /// "United States", "EU (region)"
    static func name(_ code: String) -> String {
        let code = code.uppercased()
        guard isCountry(code), let name = Locale.current.localizedString(forRegionCode: code) else {
            return String(localized: "\(code) (region)")
        }
        return name
    }

    /// The flag emoji, or nil for codes that are not countries.
    static func flag(_ code: String) -> String? {
        let code = code.uppercased()
        guard isCountry(code), code.count == 2 else { return nil }
        let scalars = code.unicodeScalars.compactMap { UnicodeScalar(127_397 + $0.value) }
        return String(String.UnicodeScalarView(scalars))
    }
}

/// One key-value row of a summary card. The key sits in a fixed column; at accessibility sizes it stacks above.
struct WhoisRow<Value: View>: View {
    private let key: LocalizedStringKey
    private let spoken: String?
    private let interactive: Bool
    private let value: Value

    @Environment(\.dynamicTypeSize) private var typeSize

    /// `spoken` is the full VoiceOver sentence ("Organization, Google LLC"). `interactive` rows keep their own
    /// controls reachable instead of merging into one element.
    init(_ key: LocalizedStringKey, spoken: String? = nil, interactive: Bool = false, @ViewBuilder value: () -> Value) {
        self.key = key
        self.spoken = spoken
        self.interactive = interactive
        self.value = value()
    }

    var body: some View {
        let padded = layout.padding(.horizontal, 14).padding(.vertical, 7)
        if interactive {
            padded.accessibilityElement(children: .contain)
        } else if let spoken {
            padded.accessibilityElement(children: .combine).accessibilityLabel(spoken)
        } else {
            padded.accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private var layout: some View {
        if typeSize >= .accessibility1 {
            VStack(alignment: .leading, spacing: 2) {
                Text(key).font(.footnote).foregroundStyle(.secondary)
                value.frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(key).font(.footnote).foregroundStyle(.secondary).frame(width: 112, alignment: .leading)
                value.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

extension WhoisRow where Value == Text {
    /// A selectable text value with an optional provenance caption.
    init(_ key: LocalizedStringKey, text: String, spoken: String? = nil) {
        self.init(key, spoken: spoken ?? "\(key), \(text)") { Text(text) }
    }
}

/// A value with a caption under it ("from description"), selectable, long-press to copy.
struct WhoisValue: View {
    let text: String
    var caption: String?
    var monospaced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(text)
                .font(monospaced ? .body.monospaced() : .body)
                .textSelection(.enabled)
            if let caption {
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
        }
        .copyContextMenu(text)
    }
}

/// "AS15169" in a tinted capsule, as in the traceroute rows.
struct ASNBadge: View {
    let asn: UInt32

    var body: some View {
        Text(verbatim: "AS\(asn)")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .accessibilityLabel(IPSpeech.asn(asn))
    }
}

/// An `info.circle` button that shows a short explanation in a popover.
struct InfoPopoverButton: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @State private var shown = false

    var body: some View {
        Button { shown = true } label: {
            Image(systemName: "info.circle").font(.footnote)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(title)
        .popover(isPresented: $shown) {
            Text(message)
                .font(.footnote)
                .padding()
                .frame(maxWidth: 320, alignment: .leading)
                .presentationCompactAdaptation(.popover)
        }
    }
}

/// Section caption ("YOUR PUBLIC IP"), a heading for VoiceOver.
struct WhoisSectionCaption: View {
    private let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) { self.title = title }

    var body: some View {
        Text(title)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}
