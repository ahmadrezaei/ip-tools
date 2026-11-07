// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SwiftUI

public struct RunHeader: View {
    private let text: AttributedString
    private let isLive: Bool

    public init(text: AttributedString, isLive: Bool) {
        self.text = text
        self.isLive = isLive
    }

    public var body: some View {
        HStack(spacing: 8) {
            if isLive { ProgressView().controlSize(.small) }
            Text(text)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
}
