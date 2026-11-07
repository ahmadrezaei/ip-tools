// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

public enum NetError: Error, Sendable, Hashable {
    case invalidTarget(String)
    case resolutionFailed(host: String, reason: String)
    case noAddress(host: String, family: IPAddress.Family)
    case socketUnavailable(errno: Int32)
    case networkUnreachable(family: IPAddress.Family)   // ENETUNREACH / no v6 route
    case localNetworkDenied
    case sendFailed(errno: Int32)
}
