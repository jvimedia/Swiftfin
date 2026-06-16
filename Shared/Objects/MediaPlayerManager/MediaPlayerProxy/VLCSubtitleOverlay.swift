//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import Factory
import Foundation
import Get
import JellyfinAPI
import SwiftUI

@MainActor
final class VLCSubtitleOverlayModel: ObservableObject {

    struct Cue: Equatable {
        let start: Duration
        let end: Duration
        let text: String
    }

    @Published
    private(set) var status: String = "idle"
    @Published
    private(set) var text: String?

    private var cues: [Cue] = []
    private var loadTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    func bind(to playbackItem: MediaPlayerItem) {
        loadTask?.cancel()
        loadTask = nil
        cancellables.removeAll()
        cues = []
        text = nil
        status = "idle"

        let itemID = playbackItem.baseItem.id ?? ""
        let mediaSourceID = playbackItem.mediaSource.id ?? ""

        let initialStream = playbackItem.subtitleStreams.first {
            $0.index == playbackItem.selectedSubtitleStreamIndex
        }
        scheduleLoad(from: initialStream, itemID: itemID, mediaSourceID: mediaSourceID)

        playbackItem.$selectedSubtitleStreamIndex
            .sink { [weak self, weak playbackItem] newIndex in
                guard let self, let playbackItem else { return }
                let stream = playbackItem.subtitleStreams.first { $0.index == newIndex }
                self.scheduleLoad(
                    from: stream,
                    itemID: playbackItem.baseItem.id ?? "",
                    mediaSourceID: playbackItem.mediaSource.id ?? ""
                )
            }
            .store(in: &cancellables)
    }

    private func scheduleLoad(from stream: MediaStream?, itemID: String, mediaSourceID: String) {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.load(from: stream, itemID: itemID, mediaSourceID: mediaSourceID)
        }
    }

    private func load(from stream: MediaStream?, itemID: String, mediaSourceID: String) async {
        guard let stream else {
            cues = []
            text = nil
            status = "inactive(no-stream)"
            return
        }
        guard stream.isTextSubtitleStream == true else {
            cues = []
            text = nil
            status = "inactive(not-text:\(stream.codec ?? "?"))"
            return
        }

        guard let client = Container.shared.currentUserSession()?.client else {
            cues = []
            text = nil
            status = "missing-client"
            return
        }

        status = "loading"

        do {
            let srtString: String

            if let deliveryURL = stream.resolvedDeliveryURL {
                // External sidecar file — fetch raw data and decode
                let request: Request<Data> = .init(url: deliveryURL)
                let response = try await client.send(request)
                srtString = Self.decode(data: response.value)
            } else if let index = stream.index, !itemID.isEmpty, !mediaSourceID.isEmpty {
                // Embedded subtitle — ask Jellyfin to convert it to SRT
                let request = Paths.getSubtitleWithTicks(
                    routeItemID: itemID,
                    routeMediaSourceID: mediaSourceID,
                    routeIndex: index,
                    routeStartPositionTicks: 0,
                    routeFormat: "srt"
                )
                srtString = try await client.send(request).value
            } else {
                cues = []
                text = nil
                status = "inactive(no-url)"
                return
            }

            cues = Self.parseSubRip(from: srtString)
            status = cues.isEmpty ? "no-cues" : "ready"
        } catch {
            cues = []
            status = "load-failed(\(error.localizedDescription))"
        }

        text = nil
    }

    func update(seconds: Duration, offset: Duration) {
        let target = seconds + offset
        text = cues.first(where: { $0.start <= target && target <= $0.end })?.text
    }

    private static func decode(data: Data) -> String {
        if let string = String(data: data, encoding: .utf8) {
            return string.removingBOMPrefix()
        }

        if let string = String(data: data, encoding: .utf16) {
            return string.removingBOMPrefix()
        }

        if let string = String(data: data, encoding: .unicode) {
            return string.removingBOMPrefix()
        }

        if let string = String(data: data, encoding: .isoLatin1) {
            return string.removingBOMPrefix()
        }

        return String(decoding: data, as: UTF8.self).removingBOMPrefix()
    }

    private static func parseSubRip(from string: String) -> [Cue] {
        let normalized = string
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        return normalized
            .components(separatedBy: "\n\n")
            .compactMap(parseCue)
    }

    private static func parseCue(from block: String) -> Cue? {
        let lines = block
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        guard lines.count >= 2 else { return nil }

        let timingLineIndex = lines[0].contains("-->") ? 0 : 1
        guard lines.indices.contains(timingLineIndex) else { return nil }

        let timingParts = lines[timingLineIndex]
            .components(separatedBy: "-->")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        guard timingParts.count == 2,
              let start = parseTimestamp(timingParts[0]),
              let end = parseTimestamp(timingParts[1])
        else {
            return nil
        }

        let textLines = lines.dropFirst(timingLineIndex + 1)
        guard !textLines.isEmpty else { return nil }

        let text = textLines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { return nil }

        return Cue(start: start, end: end, text: text)
    }

    private static func parseTimestamp(_ string: String) -> Duration? {
        let sanitized = string
            .split(separator: " ")
            .first.map(String.init) ?? string
        let parts = sanitized.split(separator: ":")
        guard parts.count == 3 else { return nil }

        let secondsParts = parts[2].split(whereSeparator: { $0 == "," || $0 == "." })
        guard secondsParts.count == 2,
              let hours = Int(parts[0]),
              let minutes = Int(parts[1]),
              let seconds = Int(secondsParts[0]),
              let milliseconds = Int(secondsParts[1])
        else {
            return nil
        }

        let totalMilliseconds =
            (((hours * 60) + minutes) * 60 + seconds) * 1000 + milliseconds

        return .milliseconds(totalMilliseconds)
    }
}

private extension String {

    func removingBOMPrefix() -> String {
        hasPrefix("\u{FEFF}") ? String(dropFirst()) : self
    }
}

struct VLCSubtitleOverlayView: View {

    var playbackItem: MediaPlayerItem

    @EnvironmentObject
    private var manager: MediaPlayerManager
    @Environment(\.subtitleOffset)
    private var subtitleOffset

    @Default(.VideoPlayer.Subtitle.subtitleColor)
    private var subtitleColor
    @Default(.VideoPlayer.Subtitle.subtitleFontName)
    private var subtitleFontName
    @Default(.VideoPlayer.Subtitle.subtitleSize)
    private var subtitleSize

    @StateObject
    private var model = VLCSubtitleOverlayModel()

    private var subtitleFont: Font {
        if !subtitleFontName.hasPrefix("."),
           let uiFont = UIFont(name: subtitleFontName, size: CGFloat(14 + subtitleSize))
        {
            return Font(uiFont)
        }
        return .system(size: CGFloat(14 + subtitleSize), weight: .semibold)
    }

    var body: some View {
        Group {
            if let text = model.text {
                Text(text)
                    .font(subtitleFont)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(subtitleColor)
                    .padding(.horizontal, 48)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.8), radius: 10, y: 2)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 36)
                    .padding(.bottom, 54)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            model.bind(to: playbackItem)
        }
        .onChange(of: ObjectIdentifier(playbackItem)) { _ in
            model.bind(to: playbackItem)
        }
        .onReceive(manager.secondsBox.$value) { seconds in
            model.update(seconds: seconds, offset: subtitleOffset.wrappedValue)
        }
        .onChange(of: subtitleOffset.wrappedValue) { _, newValue in
            model.update(seconds: manager.seconds, offset: newValue)
        }
    }
}
