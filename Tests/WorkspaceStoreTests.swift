import XCTest
@testable import Clover

final class WorkspaceStoreTests: XCTestCase {
    func testSaveAndLoadDefaultWorkspace() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("default.json", isDirectory: false)
        let store = try WorkspaceStore(workspaceURL: url)
        let pane = PaneState.home()
        let workspace = Workspace(
            id: UUID(),
            name: "Default",
            layout: .twoVertical,
            panes: [pane],
            windowFrame: "{{0, 0}, {800, 600}}",
            sidebarWidth: 220,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        try store.saveDefaultWorkspace(workspace)
        let loaded = try XCTUnwrap(store.loadDefaultWorkspace())

        XCTAssertEqual(loaded.name, workspace.name)
        XCTAssertEqual(loaded.layout, .twoVertical)
        XCTAssertEqual(loaded.panes.map(\.id), [pane.id])
        XCTAssertEqual(loaded.sidebarWidth, 220)
    }

    func testResolvedURLFallsBackToHomeWhenPathIsMissing() throws {
        let store = try WorkspaceStore(workspaceURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let missingState = PaneState(
            id: UUID(),
            currentURLBookmark: nil,
            currentPath: "/tmp/CloverMissing-\(UUID().uuidString)",
            viewMode: .grid,
            sortOption: .nameAscending,
            selectedFileNames: [],
            backHistory: [],
            forwardHistory: []
        )

        XCTAssertEqual(store.resolvedURL(for: missingState), FileManager.default.homeDirectoryForCurrentUser)
    }
}
