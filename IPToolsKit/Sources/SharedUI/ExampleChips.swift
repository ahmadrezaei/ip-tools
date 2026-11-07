// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SwiftUI

public struct ExampleChips: View {
    private let examples: [String]
    private let onTap: (String) -> Void

    public init(_ examples: [String], onTap: @escaping (String) -> Void) {
        self.examples = examples
        self.onTap = onTap
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(examples, id: \.self) { example in
                    Button(example) { onTap(example) }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                }
            }
            .padding(.horizontal)
        }
    }
}
