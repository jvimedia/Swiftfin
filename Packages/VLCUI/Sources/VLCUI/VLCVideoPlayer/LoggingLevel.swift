//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

public extension VLCVideoPlayer {

    enum LoggingLevel: Int {
        case info
        case error
        case warning
        case debug

        public init?(rawValue: Int) {
            switch rawValue {
            case 0:
                self = .info
            case 1:
                self = .error
            case 2:
                self = .warning
            case 3, 4:
                self = .debug
            default:
                return nil
            }
        }
    }
}
