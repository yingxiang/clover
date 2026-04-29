import XCTest
@testable import Clover

@MainActor
final class PaneLayoutControllerTests: XCTestCase {
    func testSetLayoutCreatesExpectedPaneCounts() {
        let controller = makeController()
        controller.loadViewIfNeeded()

        XCTAssertEqual(controller.layout, .single)
        XCTAssertEqual(controller.paneCount, 1)

        controller.setLayout(.twoVertical)
        XCTAssertEqual(controller.layout, .twoVertical)
        XCTAssertEqual(controller.paneCount, 2)

        controller.setLayout(.twoHorizontal)
        XCTAssertEqual(controller.layout, .twoHorizontal)
        XCTAssertEqual(controller.paneCount, 2)

        controller.setLayout(.fourGrid)
        XCTAssertEqual(controller.layout, .fourGrid)
        XCTAssertEqual(controller.paneCount, 4)
    }

    func testReducingLayoutPreservesActivePane() {
        let controller = makeController()
        controller.loadViewIfNeeded()
        controller.setLayout(.fourGrid)
        controller.activatePane(at: 3)
        let activePaneID = controller.activePaneID

        controller.setLayout(.single)

        XCTAssertEqual(controller.paneCount, 1)
        XCTAssertEqual(controller.activePaneID, activePaneID)
    }

    private func makeController() -> PaneLayoutController {
        let provider = PaneLayoutMockProvider()
        let environment = AppEnvironment(
            fileProvider: provider,
            fileOperationService: FileOperationService(provider: provider)
        )
        return PaneLayoutController(environment: environment)
    }
}

private final class PaneLayoutMockProvider: FileProvider, @unchecked Sendable {
    let providerID = "pane-layout-mock"
    let displayName = "Pane Layout Mock"

    func listDirectory(at url: URL) async throws -> [FileItem] {
        []
    }

    func createFolder(at parentURL: URL, name: String) async throws -> URL {
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

    func openItem(_ url: URL) async throws {}
}
