// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SwiftUI

public extension AttributedString {
    /// Builds a header string from pieces, e.g. `[("Pinging ", false), ("1.1.1.1", true)]`.
    init(segments: [(text: String, bold: Bool)]) {
        self.init()
        for segment in segments {
            var piece = AttributedString(segment.text)
            if segment.bold { piece.inlinePresentationIntent = .stronglyEmphasized }
            append(piece)
        }
    }
}

public struct RunHeader: View {
    private let text: AttributedString
    private let isLive: Bool
    private let showsProgress: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    /// `isLive` shows a pulsing green dot (static with Reduce Motion); `showsProgress` shows a spinner instead
    /// (resolving / loading).
    public init(text: AttributedString, isLive: Bool, showsProgress: Bool = false) {
        self.text = text
        self.isLive = isLive
        self.showsProgress = showsProgress
    }

    public var body: some View {
        HStack(spacing: 8) {
            if showsProgress {
                ProgressView().controlSize(.small)
            } else if isLive {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                    .opacity(reduceMotion || !pulsing ? 1 : 0.35)
                    .onAppear {
                        guard !reduceMotion else { return }
                        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulsing = true }
                    }
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(alignment: .leading) {
        RunHeader(text: AttributedString(segments: [("Pinging ", false), ("1.1.1.1", true), (" · one.one.one.one · 56 bytes", false)]), isLive: true)
        RunHeader(text: AttributedString(segments: [("Resolving apple.com…", false)]), isLive: false, showsProgress: true)
        RunHeader(text: AttributedString(segments: [("Finished · 20 sent, 19 received", false)]), isLive: false)
    }
    .padding()
}
