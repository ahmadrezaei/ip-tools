// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation

public enum ASChainBuilder {
    /// DESIGN 6.11.6. Pure; call on every update.
    public static func fromTrace(_ hops: [ChainHop], myASN: UInt32?, origins: [UInt32], finished: Bool,
                                 source: ASChain.Source) -> ASChain {
        fatalError("TODO")
    }

    /// DESIGN 6.11.4. nil when no cleaned path contains myASN.
    public static func fromBGP(_ cleanedPaths: [ObservedPath], myASN: UInt32, origins: [UInt32]) -> ASChain? {
        fatalError("TODO")
    }

    /// DESIGN 6.11.7. Returns `chain` unchanged unless completion == .gap and a suffix exists.
    public static func stitch(_ chain: ASChain, cleanedPaths: [ObservedPath], origins: [UInt32]) -> ASChain {
        fatalError("TODO")
    }
}
