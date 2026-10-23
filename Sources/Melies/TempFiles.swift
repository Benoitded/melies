import Foundation

/// Exports made to copy, share or drag a video are written to the temporary folder. They hold the user's screen
/// recordings (possibly private), and nothing ever deleted them: macOS only cleans that folder after days.
enum TempFiles {
    /// Removes what Melies left in the temporary folder: at launch and at quit, anything older than `age` seconds.
    static func sweep(olderThan age: TimeInterval = 3600) {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory
        guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for item in items where item.lastPathComponent.hasPrefix("melies-") {
            let modified = (try? item.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if Date().timeIntervalSince(modified) > age { try? fm.removeItem(at: item) }
        }
    }
}
