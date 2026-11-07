// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SwiftUI

/// Toolbar share button for a plain-text export; disabled until there is text.
public struct ShareTextButton: View {
    private let text: String
    private let subject: String

    public init(text: String, subject: String = "") {
        self.text = text
        self.subject = subject
    }

    public var body: some View {
        ShareLink(item: text, subject: Text(subject)) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .disabled(text.isEmpty)
    }
}

public extension View {
    /// Long-press / right-click "Copy" for a row.
    func copyContextMenu(_ text: String, title: LocalizedStringKey = "Copy") -> some View {
        contextMenu {
            Button { Clipboard.copy(text) } label: { Label(title, systemImage: "doc.on.doc") }
        }
    }
}
