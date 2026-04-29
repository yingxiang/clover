import AppKit
import ImageIO
import UniformTypeIdentifiers

enum FileGridDetailProvider {
    static func detail(for item: FileItem) async -> String {
        if item.isDirectory {
            let count = await directoryItemCount(at: item.url)
            return "\(count) items"
        }

        if let dimensions = imageDimensions(for: item) {
            return "\(dimensions.width)x\(dimensions.height)"
        }

        guard let size = item.size else { return "" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private static func directoryItemCount(at url: URL) async -> Int {
        await Task.detached(priority: .utility) {
            (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]).count) ?? 0
        }.value
    }

    private static func imageDimensions(for item: FileItem) -> (width: Int, height: Int)? {
        guard isImage(item),
              let source = CGImageSourceCreateWithURL(item.url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        return (width, height)
    }

    private static func isImage(_ item: FileItem) -> Bool {
        if let identifier = item.typeIdentifier,
           let type = UTType(identifier),
           type.conforms(to: .image) {
            return true
        }
        return UTType(filenameExtension: item.url.pathExtension)?.conforms(to: .image) == true
    }
}
