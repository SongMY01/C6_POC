import Foundation

/// 트랙별 리전 편집 결과(옮기기·자르기·분할·삭제)를 곡 단위로 저장한다.
///
/// PatchStore와 같은 곡 폴더 규칙을 쓴다. 원본 스템은 분리할 때마다 새로 받지만
/// 리전은 "원본 파일의 어느 부분을 타임라인 어디에 놓는지"만 담고 있어서 다시 적용할 수 있다.
/// 원본 길이가 저장 당시와 다르면(다른 곡을 분리한 경우) 그 트랙의 편집은 적용하지 않는다.
struct RegionStore {
    private struct SavedTrack: Codable {
        var fileDuration: TimeInterval
        var regions: [TrackRegion]
    }

    private let fileURL: URL

    init(songTitle: String = "항해") {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("regions", isDirectory: true)
            .appendingPathComponent(songTitle, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("regions.json")
    }

    private func loadAll() -> [String: SavedTrack] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: SavedTrack].self, from: data) else { return [:] }
        return decoded
    }

    /// 저장된 리전을 트랙에 적용한다. 적용 가능한 저장본이 없으면 트랙은 그대로 둔다.
    func restore(into tracks: [StemTrack]) {
        let saved = loadAll()
        for track in tracks {
            guard let entry = saved[track.id],
                  abs(entry.fileDuration - track.duration) < 0.5 else { continue }
            let valid = entry.regions.filter {
                $0.duration > 0 && $0.sourceStart >= 0 && $0.sourceStart + $0.duration <= track.duration + 0.05
            }
            track.regions = valid.sorted { $0.timelineStart < $1.timelineStart }
        }
    }

    func save(_ tracks: [StemTrack]) {
        var all = loadAll()
        for track in tracks {
            all[track.id] = SavedTrack(fileDuration: track.duration, regions: track.regions)
        }
        guard let data = try? JSONEncoder().encode(all) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
