// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Observation

public struct ToolRequest: Equatable, Sendable {
    public let target: String
    public let autostart: Bool
    public init(target: String, autostart: Bool) {
        self.target = target
        self.autostart = autostart
    }
}

@MainActor @Observable public final class AppRouter {
    public var selectedTool: Tool
    /// Incremented by every `open`; tool views watch it to pick up a pending request.
    public private(set) var requestTick = 0
    /// Incremented by `focusTarget()` (⌘L); injected as `\.targetFocusToken`.
    public private(set) var focusToken = 0
    private var pending: [Tool: ToolRequest] = [:]

    public init(selectedTool: Tool = .ping) {
        self.selectedTool = selectedTool
    }

    public func open(_ tool: Tool, target: String, autostart: Bool) {
        pending[tool] = ToolRequest(target: target, autostart: autostart)
        requestTick += 1
        selectedTool = tool
    }

    /// Consumed by the tool's view on appear/change.
    public func takeRequest(for tool: Tool) -> ToolRequest? {
        pending.removeValue(forKey: tool)
    }

    public func focusTarget() {
        focusToken += 1
    }
}
