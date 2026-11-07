// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SwiftUI

public struct ErrorStateView: View {
    private let error: any DisplayableError
    private let retry: () -> Void

    public init(_ error: any DisplayableError, retry: @escaping () -> Void) {
        self.error = error
        self.retry = retry
    }

    public var body: some View {
        ContentUnavailableView {
            Label(error.title, systemImage: error.systemImage)
        } description: {
            Text(error.message)
        } actions: {
            switch error.action {
            case .retry: Button("Try Again", action: retry)
            case .openSettings: Button("Open Settings") { SystemSettings.open() }
            case nil: EmptyView()
            }
        }
    }
}
