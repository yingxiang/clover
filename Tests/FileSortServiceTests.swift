import XCTest
@testable import Clover

final class FileSortServiceTests: XCTestCase {
    func testDirectoriesSortBeforeFilesByName() {
        let folder = makeItem(name: "Folder", isDirectory: true)
        let file = makeItem(name: "A.txt", size: 10, typeIdentifier: "public.text")

        let sorted = FileSortService.sort([file, folder], by: .nameAscending)

        XCTAssertEqual(sorted.map(\.name), ["Folder", "A.txt"])
    }

    func testNameDescendingKeepsDirectoriesBeforeFiles() {
        let folderA = makeItem(name: "A Folder", isDirectory: true)
        let folderZ = makeItem(name: "Z Folder", isDirectory: true)
        let fileA = makeItem(name: "A.txt")
        let fileZ = makeItem(name: "Z.txt")

        let sorted = FileSortService.sort([fileA, folderA, fileZ, folderZ], by: .nameDescending)

        XCTAssertEqual(sorted.map(\.name), ["Z Folder", "A Folder", "Z.txt", "A.txt"])
    }

    func testSortsByModificationDate() {
        let older = makeItem(name: "older.txt", modificationDate: Date(timeIntervalSince1970: 100))
        let newer = makeItem(name: "newer.txt", modificationDate: Date(timeIntervalSince1970: 200))

        XCTAssertEqual(FileSortService.sort([newer, older], by: .dateAscending).map(\.name), ["older.txt", "newer.txt"])
        XCTAssertEqual(FileSortService.sort([older, newer], by: .dateDescending).map(\.name), ["newer.txt", "older.txt"])
    }

    func testSortsBySize() {
        let small = makeItem(name: "small.txt", size: 10)
        let large = makeItem(name: "large.txt", size: 100)

        XCTAssertEqual(FileSortService.sort([large, small], by: .sizeAscending).map(\.name), ["small.txt", "large.txt"])
        XCTAssertEqual(FileSortService.sort([small, large], by: .sizeDescending).map(\.name), ["large.txt", "small.txt"])
    }

    func testSortsByType() {
        let archive = makeItem(name: "archive.zip", typeIdentifier: "public.zip-archive")
        let text = makeItem(name: "text.txt", typeIdentifier: "public.plain-text")

        XCTAssertEqual(FileSortService.sort([archive, text], by: .typeAscending).map(\.name), ["text.txt", "archive.zip"])
        XCTAssertEqual(FileSortService.sort([text, archive], by: .typeDescending).map(\.name), ["archive.zip", "text.txt"])
    }

    private func makeItem(
        name: String,
        isDirectory: Bool = false,
        size: Int64? = nil,
        modificationDate: Date? = nil,
        typeIdentifier: String? = nil
    ) -> FileItem {
        FileItem(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            name: name,
            isDirectory: isDirectory,
            size: size,
            modificationDate: modificationDate,
            creationDate: nil,
            typeIdentifier: typeIdentifier,
            isHidden: name.hasPrefix(".")
        )
    }
}
