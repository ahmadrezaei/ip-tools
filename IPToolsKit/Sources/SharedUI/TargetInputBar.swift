// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import NetCore
import SwiftUI

/// Result of validating the text in a target field, locally and without network.
public enum TargetValidation: Sendable, Equatable {
    case empty, valid, invalid

    public init(_ text: String, mode: TargetParser.Mode) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            self = .empty
        } else {
            self = TargetParser.parse(trimmed, mode: mode) == nil ? .invalid : .valid
        }
    }
}

public struct TargetInputBar: View {
    @Binding private var text: String
    private let placeholder: LocalizedStringKey
    private let systemImage: String
    private let mode: TargetParser.Mode
    private let primaryTitle: LocalizedStringKey
    private let isRunning: Bool
    private let isEnabled: Bool
    private let recents: RecentsStore
    private let onSubmit: () -> Void
    private let onStop: () -> Void

    @Environment(\.isOnline) private var isOnline
    @Environment(\.targetFocusToken) private var focusToken
    @FocusState private var isFocused: Bool

    public init(text: Binding<String>, placeholder: LocalizedStringKey, systemImage: String,
                mode: TargetParser.Mode, primaryTitle: LocalizedStringKey, isRunning: Bool, isEnabled: Bool,
                recents: RecentsStore, onSubmit: @escaping () -> Void, onStop: @escaping () -> Void) {
        self._text = text
        self.placeholder = placeholder
        self.systemImage = systemImage
        self.mode = mode
        self.primaryTitle = primaryTitle
        self.isRunning = isRunning
        self.isEnabled = isEnabled
        self.recents = recents
        self.onSubmit = onSubmit
        self.onStop = onStop
    }

    private var validation: TargetValidation { TargetValidation(text, mode: mode) }
    private var canSubmit: Bool { isEnabled && validation == .valid && isOnline }

    private var suggestions: [RecentTarget] {
        guard isFocused, !isRunning else { return [] }
        return recents.suggestions(matching: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                field
                primaryButton
            }

            if validation == .invalid && !isRunning {
                Text(mode == .bgp ? "Not a valid IP address, prefix, AS number or hostname"
                                  : "Not a valid IP address or hostname")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 4)
                    .accessibilityIdentifier("targetValidationMessage")
            }

            if !isOnline { OfflineBanner() }

            let items = suggestions
            if !items.isEmpty {
                RecentsSuggestions(suggestions: items, onPick: pick, onDelete: { recents.remove($0) })
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .onChange(of: focusToken) { isFocused = true }
    }

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage).foregroundStyle(.secondary).accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .focused($isFocused)
                .hostInputTraits()
                .submitLabel(.go)
                .onSubmit { if canSubmit && !isRunning { onSubmit() } }
                .disabled(isRunning)
                .accessibilityIdentifier("targetField")
            if !isRunning {
                if text.isEmpty {
                    Button { if let pasted = Clipboard.paste() { text = pasted.trimmingCharacters(in: .whitespacesAndNewlines) } } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Paste")
                } else {
                    Button { text = ""; isFocused = true } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Clear")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.fieldFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder private var primaryButton: some View {
        if isRunning {
            Button("Stop", action: onStop)
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .accessibilityIdentifier("stopButton")
        } else {
            Button(primaryTitle) { isFocused = false; onSubmit() }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(!canSubmit)
                .accessibilityIdentifier("primaryButton")
        }
    }

    private func pick(_ item: RecentTarget) {
        text = item.display
        isFocused = false
    }
}

#Preview("States") {
    @Previewable @State var text = ""
    let recents = RecentsStore(defaults: UserDefaults(suiteName: "preview.targetbar") ?? .standard)
    VStack {
        TargetInputBar(text: $text, placeholder: "IP address or hostname", systemImage: "dot.radiowaves.left.and.right",
                       mode: .host, primaryTitle: "Start", isRunning: false, isEnabled: true, recents: recents,
                       onSubmit: {}, onStop: {})
        TargetInputBar(text: .constant("not a host!"), placeholder: "IP address or hostname", systemImage: "dot.radiowaves.left.and.right",
                       mode: .host, primaryTitle: "Start", isRunning: false, isEnabled: true, recents: recents,
                       onSubmit: {}, onStop: {})
        TargetInputBar(text: .constant("1.1.1.1"), placeholder: "IP address or hostname", systemImage: "dot.radiowaves.left.and.right",
                       mode: .host, primaryTitle: "Start", isRunning: true, isEnabled: true, recents: recents,
                       onSubmit: {}, onStop: {})
        TargetInputBar(text: .constant("1.1.1.1"), placeholder: "IP address or hostname", systemImage: "dot.radiowaves.left.and.right",
                       mode: .host, primaryTitle: "Start", isRunning: false, isEnabled: true, recents: recents,
                       onSubmit: {}, onStop: {})
            .environment(\.isOnline, false)
        Spacer()
    }
}
