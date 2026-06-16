//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

extension Optional {

    func chaining(_ value: Wrapped) -> Wrapped {
        switch self {
        case .none:
            return value
        case let .some(wrapped):
            return wrapped
        }
    }
}
