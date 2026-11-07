// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import NetCore
import SwiftUI

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

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: systemImage).foregroundStyle(.secondary)
                TextField(placeholder, text: $text)
                    .hostInputTraits()
                    .submitLabel(.go)
                    .onSubmit { if isEnabled && !isRunning { onSubmit() } }
                    .disabled(isRunning)
                if isRunning {
                    Button("Stop", role: .destructive, action: onStop).buttonStyle(.borderedProminent)
                } else {
                    Button(primaryTitle, action: onSubmit)
                        .buttonStyle(.borderedProminent)
                        .disabled(!isEnabled)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            if !isRunning {
                let suggestions = recents.suggestions(matching: text)
                if !suggestions.isEmpty && !text.isEmpty {
                    RecentsSuggestions(suggestions: suggestions) { text = $0.display }
                }
            }
        }
    }
}
