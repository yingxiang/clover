import Foundation

enum CloverError: LocalizedError {
    case directoryNotFound(URL)
    case permissionDenied(URL)
    case fileAlreadyExists(URL)
    case operationCancelled
    case unsupportedOperation
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .directoryNotFound(let url):
            return "Directory not found: \(url.path)"
        case .permissionDenied(let url):
            return "Permission denied: \(url.path)"
        case .fileAlreadyExists(let url):
            return "File already exists: \(url.path)"
        case .operationCancelled:
            return "Operation cancelled."
        case .unsupportedOperation:
            return "This operation is not supported yet."
        case .unknown(let error):
            return error.localizedDescription
        }
    }
}
