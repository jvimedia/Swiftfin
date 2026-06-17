//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(iOS)
import AVKit
import SwiftUI

extension VideoPlayer.PlaybackControls.Toolbar.ActionButtons {

    struct PictureInPicture: View {

        @EnvironmentObject
        private var containerState: VideoPlayerContainerState

        private var systemImage: String {
            if containerState.isPiPActive {
                VideoPlayerActionButton.pip.secondarySystemImage
            } else {
                VideoPlayerActionButton.pip.systemImage
            }
        }

        var body: some View {
            Button(
                "Picture in Picture",
                systemImage: systemImage
            ) {
                containerState.containerView?.startPiP()
            }
            .videoPlayerActionButtonTransition()
            .disabled(containerState.containerView?.pipController == nil)
        }
    }
}
#endif
