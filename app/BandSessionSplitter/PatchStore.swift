import Foundation

/// 패치 하나 = "이 세션(예: 기타)의 이 구간(시작~끝)을 다시 녹음한 대체 버전".
///
/// 원본 스템 파일은 절대 건드리지 않는다 — 재녹음본은 별도 파일로 저장하고,
/// 재생할 때 "원본 / 패치" 중 뭘 들을지만 고른다. 같은 구간을 여러 번
/// 재녹음하면 버전이 계속 쌓이므로 언제든 이전 버전으로 되돌아갈 수 있다.
struct Patch: Identifiable, Codable, Equatable {
    let id: UUID
    var sessionId: String
    var startTime: TimeInterval
    var endTime: TimeInterval
    var createdAt: Date
    /// 녹음 파일의 몇 초 지점부터 startTime에 재생할지. 패치 왼쪽 끝을 잘라내면 늘어난다.
    var sourceStart: TimeInterval = 0

    var timeRange: ClosedRange<TimeInterval> {
        startTime...endTime
    }
    var duration: TimeInterval { endTime - startTime }
}

extension Patch {
    /// sourceStart가 없던 예전 manifest도 읽을 수 있게 한다.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        sessionId = try c.decode(String.self, forKey: .sessionId)
        startTime = try c.decode(TimeInterval.self, forKey: .startTime)
        endTime = try c.decode(TimeInterval.self, forKey: .endTime)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        sourceStart = try c.decodeIfPresent(TimeInterval.self, forKey: .sourceStart) ?? 0
    }
}

@MainActor
final class PatchStore: ObservableObject {
    @Published private(set) var patches: [Patch] = []

    private let baseDir: URL
    private let manifestURL: URL

    init(songTitle: String = "항해") {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("patches", isDirectory: true)
            .appendingPathComponent(songTitle, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.baseDir = dir
        self.manifestURL = dir.appendingPathComponent("patch_manifest.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONDecoder().decode([Patch].self, from: data) else { return }
        patches = decoded.sorted { $0.createdAt > $1.createdAt }
    }

    private func persistManifest() {
        guard let data = try? JSONEncoder().encode(patches) else { return }
        try? data.write(to: manifestURL)
    }

    func fileURL(for patch: Patch) -> URL {
        baseDir.appendingPathComponent("patch_\(patch.id.uuidString).caf")
    }

    /// 임시로 녹음된 파일을 관리 위치로 옮기고 목록에 등록한다.
    @discardableResult
    func addPatch(sessionId: String, timeRange: ClosedRange<TimeInterval>, tempFileURL: URL) throws -> Patch {
        let patch = Patch(
            id: UUID(),
            sessionId: sessionId,
            startTime: timeRange.lowerBound,
            endTime: timeRange.upperBound,
            createdAt: Date()
        )
        let dest = fileURL(for: patch)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tempFileURL, to: dest)
        patches.insert(patch, at: 0)
        persistManifest()
        return patch
    }

    /// 옮기기·자르기로 바뀐 위치를 저장한다 (녹음 파일은 그대로).
    func update(_ patch: Patch) {
        guard let i = patches.firstIndex(where: { $0.id == patch.id }) else { return }
        patches[i] = patch
        persistManifest()
    }

    func delete(_ patch: Patch) {
        try? FileManager.default.removeItem(at: fileURL(for: patch))
        patches.removeAll { $0.id == patch.id }
        persistManifest()
    }

    /// 특정 세션의 모든 패치 (최신 순) — 타임라인 레인에 블록으로 그릴 때 쓴다.
    func patches(sessionId: String) -> [Patch] {
        patches.filter { $0.sessionId == sessionId }
    }

    /// 같은 세션·같은 구간 안에서의 버전 번호 (가장 오래된 것이 v1).
    func versionNumber(of patch: Patch) -> Int {
        let siblings = patches(sessionId: patch.sessionId, region: patch.timeRange)
        guard let index = siblings.firstIndex(where: { $0.id == patch.id }) else { return 1 }
        return siblings.count - index
    }

    /// 특정 세션에서, 주어진 구간과 정확히 일치하는 패치들 (최신 순).
    func patches(sessionId: String, region: ClosedRange<TimeInterval>) -> [Patch] {
        patches.filter {
            $0.sessionId == sessionId &&
            abs($0.startTime - region.lowerBound) < 0.05 &&
            abs($0.endTime - region.upperBound) < 0.05
        }
    }
}
