import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

@MainActor
enum FileThumbnailProvider {
    private static var cache: [URL: NSImage] = [:]

    static func thumbnail(for item: FileItem, size: CGFloat) async -> NSImage? {
        guard !item.isDirectory else { return nil }
        let url = item.url
        if let image = cache[url] {
            return image
        }

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: NSSize(width: size, height: size),
            scale: scale,
            representationTypes: .thumbnail
        )

        let image = await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.nsImage)
            }
        }

        if let image {
            cache[url] = image
        }
        return image
    }
}
