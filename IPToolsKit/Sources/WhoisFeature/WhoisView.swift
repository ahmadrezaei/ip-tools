// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import NetCore
import SharedUI
import SwiftUI

public struct WhoisView: View {
    @Bindable private var model: WhoisModel

    @Environment(\.isOnline) private var isOnline
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase

    public init(model: WhoisModel) {
        self.model = model
    }

    private var isRegular: Bool { sizeClass == .regular }
    private var parsedOK: Bool { WhoisModel.classify(model.targetText) != nil }

    public var body: some View {
        VStack(spacing: 0) {
            TargetInputBar(
                text: $model.targetText, placeholder: "IP, prefix, ASN or hostname",
                systemImage: Tool.whois.systemImage, mode: .bgp, primaryTitle: "Look Up",
                isRunning: model.isLookingUp, isEnabled: parsedOK && isOnline, recents: model.recentsStore,
                onSubmit: { model.lookUp() }, onStop: { model.cancel() })
            layout
        }
        .navigationTitle("Whois")
        .modifier(WhoisTitleMode(large: model.isMyIPMode))
        .toolbar { toolbarContent }
        .background { shortcuts }
        .task {
            model.consumeRouterRequest()
            model.appeared()
        }
        .onDisappear { model.disappeared() }
        .onChange(of: model.router.selectedTool) { _, tool in
            if tool == .whois {
                model.consumeRouterRequest()
                model.appeared()
            }
        }
        .onChange(of: model.router.requestTick) { model.consumeRouterRequest() }
        .onChange(of: model.pathGeneration) { model.pathGenerationChanged() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.resumeFromBackground() } }
        .onChange(of: model.phase) { _, phase in announce(phase) }
        .onChange(of: model.myIP) { _, snapshot in
            if let snapshot, !snapshot.isChecking, model.isMyIPMode, snapshot.foundAny {
                post(IPSpeech.myIP(snapshot))
            }
        }
    }

    @ViewBuilder private var layout: some View {
        if isRegular {
            WhoisPadLayout(model: model)
        } else {
            WhoisPhoneLayout(model: model)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if model.isMyIPMode {
                Button { model.refreshMyIP() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .disabled(!isOnline)
            }
            Menu {
                ShareLink(item: model.exportText) { Label("Share Summary", systemImage: "text.alignleft") }
                ShareLink(item: model.exportFullText) { Label("Share Full Record", systemImage: "doc.text") }
                Button { Clipboard.copy(model.exportText) } label: { Label("Copy Summary", systemImage: "doc.on.doc") }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .disabled(model.exportText.isEmpty)
            if isRegular {
                Button { model.inspectorShown.toggle() } label: { Label("Raw Records", systemImage: "sidebar.right") }
            }
        }
    }

    /// ⌘⇧M returns to My IP (⌘⇧C is the shell's Copy Results).
    private var shortcuts: some View {
        VStack {
            Button("My IP") { model.showMyIP() }
                .keyboardShortcut("m", modifiers: [.command, .shift])
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Announcements

    private func announce(_ phase: WhoisModel.Phase) {
        switch phase {
        case let .loaded(result): post(IPSpeech.loaded(result))
        case let .failed(failure): post(failure.title)
        default: break
        }
    }

    private func post(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }
}

/// Large title in My IP mode, inline once a lookup is shown.
private struct WhoisTitleMode: ViewModifier {
    let large: Bool

    func body(content: Content) -> some View {
        #if os(iOS)
        content.navigationBarTitleDisplayMode(large ? .large : .inline)
        #else
        content
        #endif
    }
}

#Preview("My IP") { WhoisPreviewData.view(.myIP) }
#Preview("My IP, checking") { WhoisPreviewData.view(.checking) }
#Preview("My IP, IPv4 only") { WhoisPreviewData.view(.v4Only) }
#Preview("My IP, IPv6 only") { WhoisPreviewData.view(.v6Only) }
#Preview("My IP, mismatch") { WhoisPreviewData.view(.mismatch) }
#Preview("My IP, one failed") { WhoisPreviewData.view(.oneFailed) }
#Preview("My IP, both failed") { WhoisPreviewData.view(.bothFailed) }
#Preview("My IP, offline") { WhoisPreviewData.view(.offline).environment(\.isOnline, false) }
#Preview("Result: ARIN") { WhoisPreviewData.view(.google) }
#Preview("Result: operator provenance") { WhoisPreviewData.view(.operator) }
#Preview("Result: LACNIC") { WhoisPreviewData.view(.lacnic) }
#Preview("Result: not announced") { WhoisPreviewData.view(.notAnnounced) }
#Preview("Result: AS") { WhoisPreviewData.view(.autonomousSystem) }
#Preview("Result: partial") { WhoisPreviewData.view(.partial) }
#Preview("Resolving") { WhoisPreviewData.view(.resolving) }
#Preview("Loading") { WhoisPreviewData.view(.loading) }
#Preview("Private address") { WhoisPreviewData.view(.privateAddress) }
#Preview("Mapped IPv6") { WhoisPreviewData.view(.mapped) }
#Preview("Not found") { WhoisPreviewData.view(.notFound) }
#Preview("Busy") { WhoisPreviewData.view(.busy) }
#Preview("Timeout") { WhoisPreviewData.view(.timeout) }
#Preview("Resolve failed") { WhoisPreviewData.view(.unresolved) }
#Preview("Stopped in background") { WhoisPreviewData.view(.backgrounded) }
#Preview("iPad", traits: .landscapeLeft) { WhoisPreviewData.view(.google).environment(\.horizontalSizeClass, .regular) }
#Preview("Dark, large type") {
    WhoisPreviewData.view(.myIP).preferredColorScheme(.dark).environment(\.dynamicTypeSize, .accessibility3)
}
