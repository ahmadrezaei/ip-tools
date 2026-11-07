// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Testing
@testable import NetCore

@Suite struct IPAddressTests {
    @Test func parsesAndFormats() {
        #expect(IPAddress("1.1.1.1")?.description == "1.1.1.1")
        #expect(IPAddress("[2606:4700:4700::1111]")?.description == "2606:4700:4700::1111")
        #expect(IPAddress("not an ip") == nil)
    }

    @Test func checksum() {
        #expect(ICMPCodec.checksum([0x08, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01]) != 0)
    }
}
