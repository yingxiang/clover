import Foundation

extension Notification.Name {
    static let cloverFileOperationCompleted = Notification.Name("CloverFileOperationCompleted")
}

enum FileOperationNotificationKey {
    static let affectedDirectories = "affectedDirectories"
}

extension Notification {
    var cloverAffectedDirectories: [URL] {
        (userInfo?[FileOperationNotificationKey.affectedDirectories] as? [URL])?.map(\.standardizedFileURL) ?? []
    }
}

extension NotificationCenter {
    func postCloverFileOperationCompleted(affectedDirectories: [URL]) {
        let standardizedDirectories = Array(Set(affectedDirectories.map(\.standardizedFileURL)))
        post(
            name: .cloverFileOperationCompleted,
            object: nil,
            userInfo: [FileOperationNotificationKey.affectedDirectories: standardizedDirectories]
        )
    }
}
