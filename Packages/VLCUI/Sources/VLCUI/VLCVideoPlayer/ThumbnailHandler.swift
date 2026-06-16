//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(macOS)
import VLCKit
#elseif os(tvOS)
import TVVLCKit
#else
import MobileVLCKit
#endif

extension VLCVideoPlayer {

    @MainActor
    class ThumbnailHandler: NSObject, VLCMediaThumbnailerDelegate {

        private var continuation: CheckedContinuation<Result<_PlatformImage, ThumbnailError>, Never>?
        private var onCleanup: (ThumbnailHandler) -> Void

        private let instance = UUID()

        init(
            continuation: CheckedContinuation<Result<_PlatformImage, ThumbnailError>, Never>,
            onCleanup: @escaping (ThumbnailHandler) -> Void
        ) {
            self.continuation = continuation
            self.onCleanup = onCleanup
            super.init()
        }

        nonisolated func mediaThumbnailer(
            _ mediaThumbnailer: VLCMediaThumbnailer,
            didFinishThumbnail thumbnail: CGImage
        ) {
            #if os(macOS)
            let image = _PlatformImage(
                cgImage: thumbnail,
                size: NSSize(width: thumbnail.width, height: thumbnail.height)
            )
            #else
            let image = _PlatformImage(cgImage: thumbnail)
            #endif

            Task { @MainActor in
                complete(with: .success(image))
            }
        }

        nonisolated func mediaThumbnailerDidTimeOut(
            _ mediaThumbnailer: VLCMediaThumbnailer
        ) {
            Task { @MainActor in
                complete(with: .failure(.timeout))
            }
        }

        @MainActor
        private func complete(with result: Result<_PlatformImage, ThumbnailError>) {
            continuation?.resume(with: .success(result))
            continuation = nil
            onCleanup(self)
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? ThumbnailHandler else { return false }
            return self.instance == other.instance
        }

        override var hash: Int {
            instance.hashValue
        }
    }
}
