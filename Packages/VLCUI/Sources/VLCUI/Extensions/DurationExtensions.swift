//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(macOS)
import VLCKit
#elseif os(tvOS)
import TVVLCKit
#else
import MobileVLCKit
#endif

@available(iOS 16.0, macOS 13.0, tvOS 16.0, *)
extension Duration {

    var microseconds: Int64 {
        (components.attoseconds / 1_000_000_000_000) + components.seconds * 1_000_000
    }

    var milliseconds: Int64 {
        (components.attoseconds / 1_000_000_000_000_000) + components.seconds * 1000
    }

    var asVLCTime: VLCTime {
        VLCTime(int: Int32(milliseconds))
    }
}
