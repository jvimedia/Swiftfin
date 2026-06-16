//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

extension VideoPlayer.PlaybackControls.Toolbar.ActionButtons {

    struct Subtitles: View {

        @Default(.VideoPlayer.Subtitle.subtitleSize)
        private var subtitleSize

        @Environment(\.subtitleOffset)
        private var subtitleOffset

        @EnvironmentObject
        private var manager: MediaPlayerManager

        @State
        private var selectedSubtitleStreamIndex: Int?

        private var systemImage: String {
            if selectedSubtitleStreamIndex == nil {
                VideoPlayerActionButton.subtitles.secondarySystemImage
            } else {
                VideoPlayerActionButton.subtitles.systemImage
            }
        }

        private var offsetLabel: String {
            let s = subtitleOffset.wrappedValue
            if s == .zero { return "0.0s" }
            return String(format: "%+.1fs", s.seconds)
        }

        @ViewBuilder
        private func trackPicker(playbackItem: MediaPlayerItem) -> some View {
            Picker(L10n.subtitles, selection: $selectedSubtitleStreamIndex) {
                ForEach(playbackItem.subtitleStreams.prepending(.none), id: \.index) { stream in
                    Text(stream.displayTitle ?? L10n.unknown)
                        .tag(stream.index as Int?)
                }
            }
        }

        @ViewBuilder
        private func sizeControls() -> some View {
            Button {
                subtitleSize = min(20, subtitleSize + 1)
            } label: {
                Label("Larger text", systemImage: "textformat.size.larger")
            }

            Button {
                subtitleSize = max(1, subtitleSize - 1)
            } label: {
                Label("Smaller text", systemImage: "textformat.size.smaller")
            }
        }

        @ViewBuilder
        private func syncControls() -> some View {
            Button {
                subtitleOffset.wrappedValue += .milliseconds(500)
            } label: {
                Label("+0.5s (\(offsetLabel))", systemImage: "clock.badge.plus")
            }

            Button {
                subtitleOffset.wrappedValue -= .milliseconds(500)
            } label: {
                Label("-0.5s (\(offsetLabel))", systemImage: "clock.badge.minus")
            }

            if subtitleOffset.wrappedValue != .zero {
                Button(role: .destructive) {
                    subtitleOffset.wrappedValue = .zero
                } label: {
                    Label("Reset sync", systemImage: "arrow.counterclockwise")
                }
            }
        }

        @ViewBuilder
        private func content(playbackItem: MediaPlayerItem) -> some View {
            Section("Size") {
                sizeControls()
            }
            Section("Sync") {
                syncControls()
            }
            if playbackItem.subtitleStreams.isNotEmpty {
                Section(L10n.subtitles) {
                    trackPicker(playbackItem: playbackItem)
                }
            }
        }

        var body: some View {
            if let playbackItem = manager.playbackItem {
                Menu(
                    L10n.subtitles,
                    systemImage: systemImage
                ) {
                    content(playbackItem: playbackItem)
                }
                .videoPlayerActionButtonTransition()
                .assign(playbackItem.$selectedSubtitleStreamIndex, to: $selectedSubtitleStreamIndex)
                .backport
                .onChange(of: selectedSubtitleStreamIndex) { _, newValue in
                    playbackItem.selectedSubtitleStreamIndex = newValue
                }
            }
        }
    }
}
