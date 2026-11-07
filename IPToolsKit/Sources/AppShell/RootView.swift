// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import BGPFeature
import SharedUI
import SwiftUI

/// Compact width: tab bar. Regular width: split view with a sidebar. All state lives in `AppEnvironment`
/// (above the layout switch), so rotating or resizing the window loses nothing.
public struct RootView: View {
    private let environment: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    public var body: some View {
        layout
            .environment(\.isOnline, environment.network.isOnline)
            .environment(\.targetFocusToken, environment.router.focusToken)
            .environment(\.aboutSection, AnyView(AboutSections(environment: environment)))
            .background(shortcuts)
            .onChange(of: scenePhase) {
                if scenePhase == .background {
                    environment.ping.stopForBackground()
                    environment.trace.stopForBackground()
                }
            }
    }

    @ViewBuilder private var layout: some View {
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

    /// Hardware-keyboard shortcuts (DESIGN §2.4): ⌘1/2/3 tool, ⌘L focus, ⌘R start, ⌘. stop, ⌘⇧C copy results.
    private var shortcuts: some View {
        let router = environment.router
        return Group {
            Button("Ping") { router.selectedTool = .ping }.keyboardShortcut("1", modifiers: .command)
            Button("Traceroute") { router.selectedTool = .traceroute }.keyboardShortcut("2", modifiers: .command)
            Button("BGP Map") { router.selectedTool = .bgp }.keyboardShortcut("3", modifiers: .command)
            Button("Focus Target") { router.focusTarget() }.keyboardShortcut("l", modifiers: .command)
            Button("Start") { startCurrent() }.keyboardShortcut("r", modifiers: .command)
            Button("Stop") { stopCurrent() }.keyboardShortcut(".", modifiers: .command)
            Button("Copy Results") { copyCurrent() }.keyboardShortcut("c", modifiers: [.command, .shift])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func startCurrent() {
        guard environment.network.isOnline else { return }
        switch environment.router.selectedTool {
        case .ping: environment.ping.start()
        case .traceroute: environment.trace.start()
        case .bgp: environment.bgp.map()
        }
    }

    private func stopCurrent() {
        switch environment.router.selectedTool {
        case .ping: environment.ping.stop()
        case .traceroute: environment.trace.stop()
        case .bgp: environment.bgp.cancel()
        }
    }

    private func copyCurrent() {
        let text = switch environment.router.selectedTool {
        case .ping: environment.ping.exportText
        case .traceroute: environment.trace.exportText
        case .bgp: environment.bgp.exportText
        }
        if !text.isEmpty { Clipboard.copy(text) }
    }
}

#Preview {
    RootView(environment: .preview())
}
