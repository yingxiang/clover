import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

@MainActor
enum FileThumbnailProvider {
    private static var cache: [URL: NSImage] = [:]

    static func thumbnail(for item: FileItem, size: CGFloat, directoryAccessStore: DirectoryAccessStore? = nil) async -> NSImage? {
        guard !item.isDirectory else { return nil }
        let url = item.url
        if let image = cache[url] {
            return image
        }

        let securityScopeURL = directoryAccessStore?.securityScopeURL(for: url)
        let didStartAccessing = (securityScopeURL ?? url).startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                (securityScopeURL ?? url).stopAccessingSecurityScopedResource()
            }
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
        } ?? svgImage(for: item, size: size)

        if let image {
            cache[url] = image
        }
        return image
    }

    private static func svgImage(for item: FileItem, size: CGFloat) -> NSImage? {
        guard item.url.pathExtension.localizedCaseInsensitiveCompare("svg") == .orderedSame,
              let image = NSImage(contentsOf: item.url) else {
            return nil
        }
        image.size = NSSize(width: size, height: size)
        return image
    }
}
