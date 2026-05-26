import Foundation

extension Notification.Name {
    static let cloverFileOperationCompleted = Notification.Name("CloverFileOperationCompleted")
}

enum FileOperationNotificationKey {
    static let affectedDirectories = "affectedDirectories"
    static let movedItemURLs = "movedItemURLs"
}

extension Notification {
    var cloverAffectedDirectories: [URL] {
        (userInfo?[FileOperationNotificationKey.affectedDirectories] as? [URL])?.map(\.standardizedFileURL) ?? []
    }

    var cloverMovedItemURLs: [URL] {
        (userInfo?[FileOperationNotificationKey.movedItemURLs] as? [URL])?.map(\.standardizedFileURL) ?? []
    }
}

extension NotificationCenter {
    func postCloverFileOperationCompleted(affectedDirectories: [URL], movedItemURLs: [URL] = []) {
        let standardizedDirectories = Array(Set(affectedDirectories.map(\.standardizedFileURL)))
        let standardizedMovedItemURLs = Array(Set(movedItemURLs.map(\.standardizedFileURL)))
        post(
            name: .cloverFileOperationCompleted,
            object: nil,
            userInfo: [
                FileOperationNotificationKey.affectedDirectories: standardizedDirectories,
                FileOperationNotificationKey.movedItemURLs: standardizedMovedItemURLs
            ]
        )
    }
}
