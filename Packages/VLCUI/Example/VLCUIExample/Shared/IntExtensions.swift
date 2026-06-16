//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

struct RuntimeFormatStyle: FormatStyle {

    func format(_ value: Int) -> String {
        guard value >= 0 else {
            return "--:--"
        }

        let minutes = (value / 60).formatted(.number.precision(.integerLength(2)))
        let seconds = (value % 60).formatted(.number.precision(.integerLength(2)))
        return "\(minutes):\(seconds)"
    }
}

extension FormatStyle where Self == RuntimeFormatStyle {

    static var runtime: RuntimeFormatStyle {
        RuntimeFormatStyle()
    }
}
