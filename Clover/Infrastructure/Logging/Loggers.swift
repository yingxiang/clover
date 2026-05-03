import OSLog

extension Logger {
    private static let subsystem = "com.xiangying.Clover"

    static let fileProvider = Logger(subsystem: subsystem, category: "FileProvider")
    static let fileOperation = Logger(subsystem: subsystem, category: "FileOperation")
    static let workspace = Logger(subsystem: subsystem, category: "Workspace")
    static let ui = Logger(subsystem: subsystem, category: "UI")
    static let dragDrop = Logger(subsystem: subsystem, category: "DragDrop")
    static let security = Logger(subsystem: subsystem, category: "Security")
}
