// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

public enum ErrorAction: Sendable { case retry, openSettings }

public protocol DisplayableError: Error {
    var title: String { get }
    var message: String { get }
    var systemImage: String { get }
    var action: ErrorAction? { get }                                // .retry, .openSettings
}
