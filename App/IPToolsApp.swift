// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import AppShell
import SwiftUI

@main
struct IPToolsApp: App {
    @State private var environment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            RootView(environment: environment)
        }
    }
}
