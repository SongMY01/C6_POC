import Foundation

/// 내려받은 곡(스템 mp3)을 기기에 보관해서, 서버에 연결되지 않아도 곡을 열 수 있게 한다.
/// 같은 곡(job)의 스템은 바뀌지 않으므로 한 번 받은 파일은 그대로 다시 쓴다.
enum SongCache {
    private static let lastJobKey = "SongCache.lastJobId"
    private static let keepCount = 2

    private static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SongCache", isDirectory: true)
    }

    static func fileURL(jobId: String, stemKey: String) -> URL {
        root.appendingPathComponent(jobId, isDirectory: true).appendingPathComponent("\(stemKey).mp3")
    }

    /// 이미 완전히 받아 둔 스템 파일이면 그 경로, 아니면 nil.
    static func cachedURL(jobId: String, stemKey: String) -> URL? {
        let url = fileURL(jobId: jobId, stemKey: stemKey)
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return size > 0 ? url : nil
    }

    /// 내려받은 임시 파일을 보관 위치로 옮긴다.
    static func store(_ tempURL: URL, jobId: String, stemKey: String) throws -> URL {
        let dest = fileURL(jobId: jobId, stemKey: stemKey)
        let fm = FileManager.default
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.moveItem(at: tempURL, to: dest)
        return dest
    }

    static func isComplete(jobId: String) -> Bool {
        sessionStems.allSatisfy { cachedURL(jobId: jobId, stemKey: $0.key) != nil }
    }

    /// 마지막으로 열어 본 곡. 서버에 연결되지 않아도 이 곡은 열 수 있다.
    static var lastJobId: String? {
        get { UserDefaults.standard.string(forKey: lastJobKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastJobKey) }
    }

    /// 열어 본 곡으로 기록하고, 오래된 곡은 지워 저장 공간을 아낀다 (최근 2곡만 유지).
    static func markOpened(jobId: String) {
        var recent = UserDefaults.standard.stringArray(forKey: "SongCache.recentJobs") ?? []
        recent.removeAll { $0 == jobId }
        recent.insert(jobId, at: 0)
        let keep = Array(recent.prefix(keepCount))
        UserDefaults.standard.set(keep, forKey: "SongCache.recentJobs")
        lastJobId = jobId

        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for dir in dirs where !keep.contains(dir.lastPathComponent) {
            try? fm.removeItem(at: dir)
        }
    }
}
