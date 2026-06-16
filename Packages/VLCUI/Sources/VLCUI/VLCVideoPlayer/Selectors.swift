//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

public extension VLCVideoPlayer {

    enum ValueSelector<ValueType> {
        /// Automatically determine a value
        case auto

        /// Set given an absolute value
        case absolute(ValueType)
    }

    @available(iOS, deprecated: 16.0, message: "Use `Duration` typed functions and properties instead")
    @available(tvOS, deprecated: 16.0, message: "Use `Duration` typed functions and properties instead")
    @available(macOS, deprecated: 13.0, message: "Use `Duration` typed functions and properties instead")
    enum TimeSelector {
        /// Set the time in ticks
        case ticks(Int)

        /// Set the time in seconds
        case seconds(Int)

        var asTicks: Int {
            switch self {
            case let .ticks(ticks):
                return ticks
            case let .seconds(seconds):
                return seconds * 1000
            }
        }
    }
}
