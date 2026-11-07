// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Pasteboard access.
public enum Clipboard {
    public static func copy(_ string: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = string
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }

}

/// Opens the app's page in the system Settings app (no-op on macOS).
public enum SystemSettings {
    @MainActor public static func open() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}

public extension Color {
    /// Screen background behind cards (`systemGroupedBackground`).
    static var screenBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    /// Card fill (`secondarySystemGroupedBackground`).
    static var cardBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    /// Text field fill (`quaternarySystemFill`).
    static var fieldFill: Color {
        #if os(iOS)
        Color(uiColor: .quaternarySystemFill)
        #else
        Color(nsColor: .quaternarySystemFill)
        #endif
    }
}

/// System paste control: reads the pasteboard only on tap, without the "Allow Paste" prompt (iOS).
struct PasteFieldButton: View {
    let onPaste: (String) -> Void

    var body: some View {
        #if os(iOS)
        PasteButton(payloadType: String.self) { strings in
            if let text = strings.first { onPaste(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        .labelStyle(.iconOnly)
        .buttonBorderShape(.capsule)
        .tint(.secondary)
        .accessibilityLabel("Paste")
        #else
        Button {
            if let text = NSPasteboard.general.string(forType: .string) {
                onPaste(text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        } label: { Image(systemName: "doc.on.clipboard") }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Paste")
        #endif
    }
}

public extension View {
    /// keyboardType/.never/autocorrect off (iOS only).
    func hostInputTraits() -> some View {
        #if os(iOS)
        self
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        self.autocorrectionDisabled()
        #endif
    }

    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    func largeNavigationTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.large)
        #else
        self
        #endif
    }

    /// Rounded card used for stats, charts and result lists.
    func cardStyle(padding: CGFloat = 12) -> some View {
        self
            .padding(padding)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
