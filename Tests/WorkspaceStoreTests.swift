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
            isSidebarCollapsed: true,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        try store.saveDefaultWorkspace(workspace)
        let loaded = try XCTUnwrap(store.loadDefaultWorkspace())

        XCTAssertEqual(loaded.name, workspace.name)
        XCTAssertEqual(loaded.layout, .twoVertical)
        XCTAssertEqual(loaded.panes.map(\.id), [pane.id])
        XCTAssertEqual(loaded.sidebarWidth, 220)
        XCTAssertTrue(loaded.isSidebarCollapsed)
    }

    func testLoadLegacyWorkspaceDefaultsSidebarToExpanded() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("default.json", isDirectory: false)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let json = """
        {
          "createdAt" : "1970-01-01T00:00:10Z",
          "id" : "\(UUID().uuidString)",
          "layout" : "single",
          "name" : "Default",
          "panes" : [],
          "sidebarWidth" : 220,
          "updatedAt" : "1970-01-01T00:00:20Z",
          "windowFrame" : "{{0, 0}, {800, 600}}"
        }
        """
        try json.data(using: .utf8)?.write(to: url)
        let store = try WorkspaceStore(workspaceURL: url)

        let loaded = try XCTUnwrap(store.loadDefaultWorkspace())

        XCTAssertFalse(loaded.isSidebarCollapsed)
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

        XCTAssertEqual(store.resolvedURL(for: missingState), UserDirectories.homeURL)
    }
}
