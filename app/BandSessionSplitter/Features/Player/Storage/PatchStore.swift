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
    /// 곡에 반영된(채택된) 버전인지. 피드백에서 "통과"한 시도의 패치가 채택되고,
    /// 채택된 패치는 곡을 열 때 기본으로 켜진다. 같은 세션에서 구간이 겹치는 채택 패치는 하나뿐.
    var isAdopted: Bool = false

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
        isAdopted = try c.decodeIfPresent(Bool.self, forKey: .isAdopted) ?? false
    }
}

/// 재녹음 패치 저장소. 녹음 파일과 목록을 로컬에 두고, 바뀐 내용은 SyncClient로 서버에 보낸다
/// (새 녹음은 파일까지 업로드). 다른 기기의 변경은 replaceAll로 들어온다.
@MainActor
final class PatchStore: ObservableObject {
    private var sync: SyncClient { .shared }

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

    /// 서버에서 받은 최신 목록으로 교체. 목록에서 빠진 패치의 녹음 파일은 지운다.
    func replaceAll(_ newPatches: [Patch]) {
        let sorted = newPatches.sorted { $0.createdAt > $1.createdAt }
        guard sorted != patches else { return }
        let keep = Set(sorted.map(\.id))
        for old in patches where !keep.contains(old.id) {
            try? FileManager.default.removeItem(at: fileURL(for: old))
        }
        patches = sorted
        persistManifest()
    }

    private func pushUpsert(_ patch: Patch) {
        sync.send("patch.upsert", ["patch": SyncClient.json(patch)])
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
        sync.uploadAudio(patchId: patch.id, fileURL: dest)
        pushUpsert(patch)
        return patch
    }

    /// 옮기기·자르기로 바뀐 위치만 저장한다 (녹음 파일·채택 여부는 그대로).
    func updatePlacement(_ patch: Patch) {
        guard let i = patches.firstIndex(where: { $0.id == patch.id }) else { return }
        patches[i].startTime = patch.startTime
        patches[i].endTime = patch.endTime
        patches[i].sourceStart = patch.sourceStart
        persistManifest()
        pushUpsert(patches[i])
    }

    func patch(id: UUID) -> Patch? {
        patches.first { $0.id == id }
    }

    /// 곡에 반영(채택)하거나 해제한다. 채택하면 같은 세션에서 구간이 겹치는 다른 채택 패치는 해제된다.
    func setAdopted(_ adopted: Bool, patchId: UUID) {
        guard let i = patches.firstIndex(where: { $0.id == patchId }) else { return }
        if adopted {
            let target = patches[i]
            for j in patches.indices where j != i && patches[j].isAdopted
                && patches[j].sessionId == target.sessionId
                && patches[j].startTime < target.endTime && patches[j].endTime > target.startTime {
                patches[j].isAdopted = false
                pushUpsert(patches[j])
            }
        }
        patches[i].isAdopted = adopted
        persistManifest()
        pushUpsert(patches[i])
    }

    /// 세션별 채택된 패치들.
    func adoptedPatches(sessionId: String) -> [Patch] {
        patches.filter { $0.sessionId == sessionId && $0.isAdopted }
    }

    func delete(_ patch: Patch) {
        try? FileManager.default.removeItem(at: fileURL(for: patch))
        patches.removeAll { $0.id == patch.id }
        persistManifest()
        sync.send("patch.delete", ["id": patch.id.uuidString])
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
