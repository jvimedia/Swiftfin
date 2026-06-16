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

extension CGSize {

    static func aspectFill(aspectRatio: CGSize, minimumSize: CGSize) -> CGSize {
        var minimumSize = minimumSize
        let widthRatio = minimumSize.width / aspectRatio.width
        let heightRatio = minimumSize.height / aspectRatio.height

        if heightRatio > widthRatio {
            minimumSize.width = minimumSize.height / aspectRatio.height * aspectRatio.width
        } else if widthRatio > heightRatio {
            minimumSize.height = minimumSize.width / aspectRatio.width * aspectRatio.height
        }

        return minimumSize
    }

    func scale(other: CGSize) -> CGFloat {
        if height > other.height {
            return height / other.height
        } else {
            return width / other.width
        }
    }
}
