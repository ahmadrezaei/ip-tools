// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

#if DEBUG
import Foundation
import SharedUI

/// DEBUG-only launch-argument driver for App Store screenshots (no taps needed):
/// `-screenshotTool ping|traceroute|bgp -screenshotTarget <text> [-screenshotExpandHeader YES] [-screenshotPingCount <n>]`
struct ScreenshotMode: Equatable {
    var tool: Tool
    var target: String?
    var expandHeader: Bool
    var pingCount: Int?

    /// `nil` unless `-screenshotTool` names a valid tool.
    init?(arguments: [String]) {
        func value(_ flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), arguments.indices.contains(i + 1) else { return nil }
            return arguments[i + 1]
        }
        guard let name = value("-screenshotTool") else { return nil }
        switch name.lowercased() {
        case "ping": tool = .ping
        case "traceroute", "trace": tool = .traceroute
        case "bgp": tool = .bgp
        default: return nil
        }
        target = value("-screenshotTarget").flatMap { $0.isEmpty ? nil : $0 }
        expandHeader = ["YES", "TRUE", "1"].contains(value("-screenshotExpandHeader")?.uppercased() ?? "")
        pingCount = value("-screenshotPingCount").flatMap(Int.init).flatMap { $0 > 0 ? $0 : nil }
    }

    static var current: ScreenshotMode? { ScreenshotMode(arguments: ProcessInfo.processInfo.arguments) }

    /// Throwaway defaults so screenshot runs neither read nor wipe the user's recents/settings.
    static func isolatedDefaults() -> UserDefaults {
        let name = "com.ahmadrezaei.iptools.screenshot"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @MainActor func apply(to env: AppEnvironment) {
        if let pingCount { env.settings.ping.count = pingCount }
        if expandHeader { env.bgp.headerExpanded = true }
        env.router.open(tool, target: target ?? "", autostart: target != nil)
    }
}
#endif
