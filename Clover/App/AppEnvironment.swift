import Foundation

struct AppEnvironment {
    let fileProvider: any FileProvider
    let fileOperationService: FileOperationService

    static func live() -> AppEnvironment {
        let provider = LocalFileProvider()
        return AppEnvironment(fileProvider: provider, fileOperationService: FileOperationService(provider: provider))
    }
}
