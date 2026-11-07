// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SharedUI
import SwiftUI

struct Sidebar: View {
    @Binding var selection: Tool

    var body: some View {
        List(Tool.allCases, selection: Binding<Tool?>(get: { selection }, set: { if let tool = $0 { selection = tool } })) { tool in
            Label(tool.title, systemImage: tool.systemImage).tag(tool)
        }
        .navigationTitle("IP Tools")
    }
}
