import Foundation

enum LatestRecording {
    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v"]

    /// Newest video file in the watched folder (Desktop by default).
    static func find() -> URL? {
        let folder = watchedFolder()
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return nil }

        return files
            .filter { videoExtensions.contains($0.pathExtension.lowercased()) }
            .filter { !$0.lastPathComponent.contains("-twitter") && !$0.lastPathComponent.contains("-optimized") }
            .max { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
                return l < r
            }
    }

    static func watchedFolder() -> URL {
        if let path = UserDefaults.standard.string(forKey: "watchedFolder"), !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }
}
