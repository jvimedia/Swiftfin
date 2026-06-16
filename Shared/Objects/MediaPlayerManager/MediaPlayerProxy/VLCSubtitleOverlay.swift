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
    @Published
    private(set) var previewText: String? = nil

    private var cues: [Cue] = []
    private var loadTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
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
                let request: Request<Data> = .init(url: deliveryURL)
                let response = try await client.send(request)
                srtString = Self.decode(data: response.value)
            } else if let index = stream.index, !itemID.isEmpty, !mediaSourceID.isEmpty {
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

    func showSizePreview(size: Int) {
        previewTask?.cancel()
        previewText = "Size: \(size)"
        previewTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(2))
                self?.previewText = nil
            } catch {}
        }
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
        else { return nil }

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
        else { return nil }

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

// MARK: - Subtitle style parsing

private struct SubtitleStyle {
    var bold: Bool = false
    var italic: Bool = false
    var underline: Bool = false
    var color: Color?
}

private func parseHTMLTag(_ tag: String, stack: inout [SubtitleStyle]) {
    let t = tag.trimmingCharacters(in: .whitespaces).lowercased()
    switch true {
    case t == "b":
        var s = stack.last ?? SubtitleStyle()
        s.bold = true
        stack.append(s)
    case t == "/b":
        if stack.count > 1 { stack.removeLast() }
    case t == "i":
        var s = stack.last ?? SubtitleStyle()
        s.italic = true
        stack.append(s)
    case t == "/i":
        if stack.count > 1 { stack.removeLast() }
    case t == "u":
        var s = stack.last ?? SubtitleStyle()
        s.underline = true
        stack.append(s)
    case t == "/u":
        if stack.count > 1 { stack.removeLast() }
    case t.hasPrefix("font"):
        var s = stack.last ?? SubtitleStyle()
        if let colorVal = extractHTMLAttribute("color", from: tag) {
            s.color = parseHTMLColor(colorVal)
        }
        stack.append(s)
    case t == "/font":
        if stack.count > 1 { stack.removeLast() }
    default:
        break
    }
}

private func extractHTMLAttribute(_ name: String, from tag: String) -> String? {
    var i = tag.startIndex
    let lname = name.lowercased()
    let ltag = tag.lowercased()
    while i < ltag.endIndex {
        guard let found = ltag[i...].range(of: lname) else { break }
        var j = ltag.index(found.upperBound, offsetBy: 0)
        while j < ltag.endIndex, ltag[j] == " " {
            j = ltag.index(after: j)
        }
        guard j < ltag.endIndex, ltag[j] == "=" else { i = found.upperBound
            continue
        }
        j = ltag.index(after: j)
        while j < ltag.endIndex, ltag[j] == " " {
            j = ltag.index(after: j)
        }
        guard j < ltag.endIndex else { break }
        let quote = ltag[j]
        if quote == "\"" || quote == "'" {
            let start = tag.index(after: j)
            if let end = tag[start...].firstIndex(of: Character(String(quote))) {
                return String(tag[start ..< end])
            }
        } else {
            // Unquoted value
            let start = j
            var end = j
            while end < tag.endIndex, tag[end] != " ", tag[end] != ">" {
                end = tag.index(after: end)
            }
            return String(tag[start ..< end])
        }
        break
    }
    return nil
}

private func parseHTMLColor(_ value: String) -> Color? {
    let v = value.trimmingCharacters(in: .whitespaces)
    if v.hasPrefix("#") { return Color(hex: v) }
    switch v.lowercased() {
    case "white": return .white
    case "black": return .black
    case "red": return .red
    case "green": return .green
    case "blue": return .blue
    case "yellow": return .yellow
    case "cyan": return .cyan
    case "magenta": return Color(red: 1, green: 0, blue: 1)
    case "gray", "grey": return .gray
    default: return nil
    }
}

// Parses ASS override block content (the part inside {}) and modifies the top style.
private func parseASSBlock(_ block: String, stack: inout [SubtitleStyle]) {
    guard !block.isEmpty else { return }
    var s = stack.last ?? SubtitleStyle()
    var modified = false
    var remaining = Substring(block)

    while let slash = remaining.firstIndex(of: "\\") {
        remaining = remaining[remaining.index(after: slash)...]

        if remaining.hasPrefix("b1") {
            s.bold = true
            modified = true
            remaining = remaining.dropFirst(2)
        } else if remaining.hasPrefix("b0") {
            s.bold = false
            modified = true
            remaining = remaining.dropFirst(2)
        } else if remaining.hasPrefix("b") && !(remaining.dropFirst().first?.isNumber ?? false) {
            // \b with no value treated as bold on
            s.bold = true
            modified = true
            remaining = remaining.dropFirst(1)
        } else if remaining.hasPrefix("i1") {
            s.italic = true
            modified = true
            remaining = remaining.dropFirst(2)
        } else if remaining.hasPrefix("i0") {
            s.italic = false
            modified = true
            remaining = remaining.dropFirst(2)
        } else if remaining.hasPrefix("u1") {
            s.underline = true
            modified = true
            remaining = remaining.dropFirst(2)
        } else if remaining.hasPrefix("u0") {
            s.underline = false
            modified = true
            remaining = remaining.dropFirst(2)
        } else if remaining.hasPrefix("r") {
            s = SubtitleStyle()
            modified = true
            remaining = remaining.dropFirst(1)
        } else if remaining.lowercased().hasPrefix("1c&h") {
            remaining = remaining.dropFirst(4)
            if let end = remaining.firstIndex(of: "&") {
                s.color = parseASSColorHex(String(remaining[..<end]))
                modified = true
                remaining = remaining[remaining.index(after: end)...]
            }
        } else if remaining.lowercased().hasPrefix("c&h") {
            remaining = remaining.dropFirst(3)
            if let end = remaining.firstIndex(of: "&") {
                s.color = parseASSColorHex(String(remaining[..<end]))
                modified = true
                remaining = remaining[remaining.index(after: end)...]
            }
        } else {
            // Skip unknown tag — advance past its "value" to the next backslash
            remaining = remaining.dropFirst(1)
        }
    }

    guard modified else { return }
    if stack.isEmpty {
        stack = [s]
    } else {
        stack[stack.count - 1] = s
    }
}

// ASS color hex is in BGR order: BBGGRR or AABBGGRR
private func parseASSColorHex(_ hex: String) -> Color? {
    var h = hex.uppercased()
    if h.count == 8 { h = String(h.dropFirst(2)) } // Strip AA
    guard h.count == 6, let value = UInt32(h, radix: 16) else { return nil }
    let b = Double((value >> 16) & 0xFF) / 255
    let g = Double((value >> 8) & 0xFF) / 255
    let r = Double(value & 0xFF) / 255
    return Color(red: r, green: g, blue: b)
}

// MARK: - VLCSubtitleOverlayView

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

    private var baseUIFont: UIFont {
        let size = CGFloat(14 + subtitleSize)
        if !subtitleFontName.hasPrefix("."),
           let font = UIFont(name: subtitleFontName, size: size)
        {
            return font
        }
        return .systemFont(ofSize: size, weight: .semibold)
    }

    private func uiFont(bold: Bool, italic: Bool) -> UIFont {
        let base = baseUIFont
        var traits: UIFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        guard !traits.isEmpty,
              let desc = base.fontDescriptor.withSymbolicTraits(traits)
        else { return base }
        return UIFont(descriptor: desc, size: base.pointSize)
    }

    private func styledText(_ raw: String) -> AttributedString {
        // Pre-process ASS line-break codes
        let normalized = raw
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\h", with: "\u{00A0}")

        var result = AttributedString()
        var styleStack: [SubtitleStyle] = [SubtitleStyle()]
        var buf = ""
        var i = normalized.startIndex

        func flush() {
            guard !buf.isEmpty else { return }
            let decoded = buf
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&nbsp;", with: "\u{00A0}")
            let s = styleStack.last ?? SubtitleStyle()
            var container = AttributeContainer()
            container.swiftUI.font = Font(uiFont(bold: s.bold, italic: s.italic))
            container.swiftUI.foregroundColor = s.color ?? subtitleColor
            if s.underline { container.swiftUI.underlineStyle = Text.LineStyle(pattern: .solid) }
            result += AttributedString(decoded, attributes: container)
            buf = ""
        }

        while i < normalized.endIndex {
            let ch = normalized[i]
            if ch == "{" {
                flush()
                if let end = normalized[i...].firstIndex(of: "}") {
                    let block = String(normalized[normalized.index(after: i) ..< end])
                    parseASSBlock(block, stack: &styleStack)
                    i = normalized.index(after: end)
                } else {
                    buf.append(ch)
                    i = normalized.index(after: i)
                }
            } else if ch == "<" {
                flush()
                if let end = normalized[i...].firstIndex(of: ">") {
                    let tag = String(normalized[normalized.index(after: i) ..< end])
                    parseHTMLTag(tag, stack: &styleStack)
                    i = normalized.index(after: end)
                } else {
                    buf.append(ch)
                    i = normalized.index(after: i)
                }
            } else {
                buf.append(ch)
                i = normalized.index(after: i)
            }
        }

        flush()
        return result
    }

    var body: some View {
        Group {
            if let display = model.previewText ?? model.text {
                Text(styledText(display))
                    .multilineTextAlignment(.center)
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
        .onChange(of: subtitleSize) { _, newSize in
            model.showSizePreview(size: newSize)
        }
    }
}
