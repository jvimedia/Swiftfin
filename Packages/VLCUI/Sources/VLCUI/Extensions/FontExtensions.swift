//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension _PlatformFont {

    static let defaultSubtitleFont = _PlatformFont.systemFont(ofSize: 14)
}
