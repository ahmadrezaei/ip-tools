// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SharedUI
import SwiftUI

public struct RootView: View {
    private let environment: AppEnvironment
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    public var body: some View {
        #if os(iOS)
        if sizeClass == .compact {
            PhoneTabsView(environment: environment)
        } else {
            SplitRootView(environment: environment)
        }
        #else
        SplitRootView(environment: environment)
        #endif
    }
}

#Preview {
    RootView(environment: .preview())
}
