import AppKit

enum FileIconProvider {
    static func icon(for item: FileItem, size: CGFloat = 18) -> NSImage {
        let image = NSWorkspace.shared.icon(forFile: item.url.path)
        image.size = NSSize(width: size, height: size)
        return image
    }
}
