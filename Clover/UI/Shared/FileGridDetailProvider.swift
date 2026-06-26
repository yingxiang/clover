import AppKit
import ImageIO
import UniformTypeIdentifiers

enum FileGridDetailProvider {
    enum DisplayStyle: Hashable {
        case list
        case grid

        var separator: String {
            switch self {
            case .list:
                return " "
            case .grid:
                return "\n"
            }
        }
    }

    static func detail(for item: FileItem, displayStyle: DisplayStyle, directoryAccessStore: DirectoryAccessStore? = nil) async -> String {
        let securityScopeURL = directoryAccessStore?.securityScopeURL(for: item.url)
        if item.isBrowsableDirectory {
            let count = await directoryItemCount(at: item.url, securityScopeURL: securityScopeURL)
            return (count) == 1 ? String(format: String(localized: "item_count_single", defaultValue: "%lld item"), locale: .current, count) : String(format: String(localized: "item_count_plural", defaultValue: "%lld items"), locale: .current, count)
        }

        let size: Int64?
        if let itemSize = item.size {
            size = itemSize
        } else if item.isPackage || item.isApplication {
            size = await packageDirectorySize(at: item.url, securityScopeURL: securityScopeURL)
        } else {
            size = nil
        }
        guard let size else { return "" }
        let formattedSize = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)

        if let dimensions = imageDimensions(for: item, securityScopeURL: securityScopeURL) {
            return [
                formattedSize,
                "\(dimensions.width)×\(dimensions.height)"
            ].joined(separator: displayStyle.separator)
        }

        return formattedSize
    }

    private static func directoryItemCount(at url: URL, securityScopeURL: URL?) async -> Int {
        await Task.detached(priority: .userInitiated) {
            withSecurityScope(securityScopeURL) {
                (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]).count) ?? 0
            }
        }.value
    }

    private static func packageDirectorySize(at url: URL, securityScopeURL: URL?) async -> Int64? {
        await Task.detached(priority: .userInitiated) {
            withSecurityScope(securityScopeURL) {
                packageDirectorySizeSync(at: url)
            }
        }.value
    }

    private static func packageDirectorySizeSync(at url: URL) -> Int64? {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .fileSizeKey, .totalFileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            return nil
        }
        var total: Int64 = 0
        for case let childURL as URL in enumerator {
            guard !Task.isCancelled,
                  let values = try? childURL.resourceValues(forKeys: Set(keys)),
                  values.isDirectory != true else {
                continue
            }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.totalFileSize ?? values.fileSize ?? 0)
        }
        return total
    }

    private static func imageDimensions(for item: FileItem, securityScopeURL: URL?) -> (width: Int, height: Int)? {
        withSecurityScope(securityScopeURL) {
            guard isImage(item),
                  let source = CGImageSourceCreateWithURL(item.url as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int else {
                return nil
            }
            return (width, height)
        }
    }

    private static func withSecurityScope<T>(_ url: URL?, _ body: () -> T) -> T {
        let didStartAccessing = url?.startAccessingSecurityScopedResource() ?? false
        defer {
            if didStartAccessing {
                url?.stopAccessingSecurityScopedResource()
            }
        }
        return body()
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
