// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import CoreGraphics

struct ZoomPanState: Equatable {
    var scale: CGFloat = 1
    var offset: CGSize = .zero
}
