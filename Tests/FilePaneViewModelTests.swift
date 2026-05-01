import XCTest
@testable import Clover

@MainActor
final class FilePaneViewModelTests: XCTestCase {
    func testLoadSortsAndFiltersHiddenItems() async throws {
        let root = URL(fileURLWithPath: "/tmp/CloverPane")
        let provider = MockFileProvider(itemsByURL: [
            root: [
                makeItem(name: ".hidden", parent: root, isHidden: true),
                makeItem(name: "Z.txt", parent: root),
                makeItem(name: "Folder", parent: root, isDirectory: true)
            ]
        ])
        let viewModel = FilePaneViewModel(currentURL: root, provider: provider)

        viewModel.load()
        try await waitForItems(in: viewModel, count: 2)

        XCTAssertEqual(viewModel.items.map(\.name), ["Folder", "Z.txt"])
        XCTAssertEqual(provider.listedURLs, [root])
    }

    func testLoadCanIncludeHiddenItems() async throws {
        let root = URL(fileURLWithPath: "/tmp/CloverPane")
        let provider = MockFileProvider(itemsByURL: [
            root: [
                makeItem(name: ".hidden", parent: root, isHidden: true),
                makeItem(name: "visible.txt", parent: root)
            ]
        ])
        let viewModel = FilePaneViewModel(currentURL: root, provider: provider)
        viewModel.showHiddenFiles = true

        viewModel.load()
        try await waitForItems(in: viewModel, count: 2)

        XCTAssertEqual(viewModel.items.map(\.name), [".hidden", "visible.txt"])
    }

    func testRefreshLoadsCurrentURLAgain() async throws {
        let root = URL(fileURLWithPath: "/tmp/CloverPane")
        let provider = MockFileProvider(itemsByURL: [
            root: [makeItem(name: "visible.txt", parent: root)]
        ])
        let viewModel = FilePaneViewModel(currentURL: root, provider: provider)

        viewModel.load()
        try await waitForItems(in: viewModel, count: 1)
        viewModel.refresh()
        try await waitForListCount(in: provider, count: 2)

        XCTAssertEqual(provider.listedURLs, [root, root])
    }

    func testOpenItemDelegatesToProvider() async throws {
        let root = URL(fileURLWithPath: "/tmp/CloverPane")
        let fileURL = root.appendingPathComponent("visible.txt")
        let provider = MockFileProvider(itemsByURL: [:])
        let viewModel = FilePaneViewModel(currentURL: root, provider: provider)

        try await viewModel.openItem(fileURL)

        XCTAssertEqual(provider.openedURLs, [fileURL])
    }

    func testFailedNavigationKeepsCurrentURL() async throws {
        let root = URL(fileURLWithPath: "/tmp/CloverPane")
        let missing = URL(fileURLWithPath: "/tmp/CloverMissing")
        let provider = MockFileProvider(
            itemsByURL: [root: [makeItem(name: "visible.txt", parent: root)]],
            errorsByURL: [missing: CloverError.directoryNotFound(missing)]
        )
        let viewModel = FilePaneViewModel(currentURL: root, provider: provider)

        viewModel.load()
        try await waitForItems(in: viewModel, count: 1)
        viewModel.load(url: missing)
        try await waitForListCount(in: provider, count: 2)

        XCTAssertEqual(viewModel.currentURL, root)
        XCTAssertTrue(viewModel.items.isEmpty)
    }

    func testSearchFiltersLoadedItemsByNameWithoutReloadingDirectory() async throws {
        let root = URL(fileURLWithPath: "/tmp/CloverPane")
        let provider = MockFileProvider(itemsByURL: [
            root: [
                makeItem(name: "Invoice.pdf", parent: root),
                makeItem(name: "Notes.txt", parent: root),
                makeItem(name: "Images", parent: root, isDirectory: true)
            ]
        ])
        let viewModel = FilePaneViewModel(currentURL: root, provider: provider)

        viewModel.load()
        try await waitForItems(in: viewModel, count: 3)
        viewModel.setSearchQuery("i")

        XCTAssertEqual(viewModel.items.map(\.name), ["Images", "Invoice.pdf"])
        XCTAssertEqual(provider.listedURLs, [root])
    }

    func testClearingSearchRestoresLoadedItems() async throws {
        let root = URL(fileURLWithPath: "/tmp/CloverPane")
        let provider = MockFileProvider(itemsByURL: [
            root: [
                makeItem(name: "Archive.zip", parent: root),
                makeItem(name: "Readme.md", parent: root)
            ]
        ])
        let viewModel = FilePaneViewModel(currentURL: root, provider: provider)

        viewModel.load()
        try await waitForItems(in: viewModel, count: 2)
        viewModel.setSearchQuery("read")
        XCTAssertEqual(viewModel.items.map(\.name), ["Readme.md"])

        viewModel.setSearchQuery("")

        XCTAssertEqual(viewModel.items.map(\.name), ["Archive.zip", "Readme.md"])
        XCTAssertEqual(provider.listedURLs, [root])
    }

    func testSearchMatchesChineseNameByFullPinyinAndInitials() async throws {
        let root = URL(fileURLWithPath: "/tmp/CloverPane")
        let provider = MockFileProvider(itemsByURL: [
            root: [
                makeItem(name: "下载", parent: root, isDirectory: true),
                makeItem(name: "文档.txt", parent: root)
            ]
        ])
        let viewModel = FilePaneViewModel(currentURL: root, provider: provider)

        viewModel.load()
        try await waitForItems(in: viewModel, count: 2)
        viewModel.setSearchQuery("xiazai")
        XCTAssertEqual(viewModel.items.map(\.name), ["下载"])

        viewModel.setSearchQuery("xz")
        XCTAssertEqual(viewModel.items.map(\.name), ["下载"])
        XCTAssertEqual(provider.listedURLs, [root])
    }

    private func waitForItems(in viewModel: FilePaneViewModel, count: Int) async throws {
        let deadline = Date().addingTimeInterval(2)
        while viewModel.items.count != count {
            if Date() > deadline {
                XCTFail("Timed out waiting for \(count) items, found \(viewModel.items.count).")
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func waitForListCount(in provider: MockFileProvider, count: Int) async throws {
        let deadline = Date().addingTimeInterval(2)
        while provider.listedURLs.count != count {
            if Date() > deadline {
                XCTFail("Timed out waiting for \(count) list calls, found \(provider.listedURLs.count).")
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func makeItem(name: String, parent: URL, isDirectory: Bool = false, isHidden: Bool = false) -> FileItem {
        FileItem(
            url: parent.appendingPathComponent(name, isDirectory: isDirectory),
            name: name,
            isDirectory: isDirectory,
            size: isDirectory ? nil : 10,
            modificationDate: nil,
            creationDate: nil,
            typeIdentifier: isDirectory ? "public.folder" : "public.data",
            isHidden: isHidden
        )
    }
}

private final class MockFileProvider: FileProvider, @unchecked Sendable {
    let providerID = "mock"
    let displayName = "Mock"

    private let itemsByURL: [URL: [FileItem]]
    private let errorsByURL: [URL: Error]
    private let lock = NSLock()
    private var storedListedURLs: [URL] = []
    private var storedOpenedURLs: [URL] = []

    var listedURLs: [URL] {
        lock.withLock { storedListedURLs }
    }

    var openedURLs: [URL] {
        lock.withLock { storedOpenedURLs }
    }

    init(itemsByURL: [URL: [FileItem]], errorsByURL: [URL: Error] = [:]) {
        self.itemsByURL = itemsByURL
        self.errorsByURL = errorsByURL
    }

    func listDirectory(at url: URL) async throws -> [FileItem] {
        lock.withLock {
            storedListedURLs.append(url)
        }
        if let error = errorsByURL[url] {
            throw error
        }
        return itemsByURL[url] ?? []
    }

    func createFolder(at parentURL: URL, name: String) async throws -> URL {
        throw CloverError.unsupportedOperation
    }

    func createFile(at parentURL: URL, name: String, contents: Data) async throws -> URL {
        throw CloverError.unsupportedOperation
    }

    func renameItem(at url: URL, to newName: String) async throws -> URL {
        throw CloverError.unsupportedOperation
    }

    func moveItem(at url: URL, to destinationURL: URL) async throws {
        throw CloverError.unsupportedOperation
    }

    func copyItem(at url: URL, to destinationURL: URL) async throws {
        throw CloverError.unsupportedOperation
    }

    func moveItems(_ urls: [URL], to destinationURL: URL) async throws {
        throw CloverError.unsupportedOperation
    }

    func copyItems(_ urls: [URL], to destinationURL: URL) async throws {
        throw CloverError.unsupportedOperation
    }

    func trashItems(_ urls: [URL]) async throws {
        throw CloverError.unsupportedOperation
    }

    func deleteItemsPermanently(_ urls: [URL]) async throws {
        throw CloverError.unsupportedOperation
    }

    func setLabelNumber(_ labelNumber: Int?, for urls: [URL]) async throws {
        throw CloverError.unsupportedOperation
    }

    func openItem(_ url: URL) async throws {
        lock.withLock {
            storedOpenedURLs.append(url)
        }
    }
}
