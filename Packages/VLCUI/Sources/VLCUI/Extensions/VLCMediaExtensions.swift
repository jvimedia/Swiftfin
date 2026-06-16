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
extension VLCMedia {

    var duration: Duration {
        Duration.milliseconds(length.intValue)
    }
}
