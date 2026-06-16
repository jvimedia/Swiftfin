//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension _PlatformView {

    func apply(transform: CGAffineTransform) {
        #if !os(macOS)
        self.transform = transform
        #endif
    }

    func scale(x: CGFloat, y: CGFloat) {
        let transform = CGAffineTransform(scaleX: x, y: y)

        #if !os(macOS)
        self.transform = transform
        #endif
    }
}

extension View {

    func copy<Value>(modifying keyPath: WritableKeyPath<Self, Value>, with newValue: Value) -> Self {
        var copy = self
        copy[keyPath: keyPath] = newValue
        return copy
    }
}
