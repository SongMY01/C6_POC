import Foundation
import AVFoundation
import Combine

/// 트랙 위의 오디오 조각(GarageBand의 "리전"). 원본 스템 파일의 [sourceStart, sourceStart+duration]
/// 부분을 곡 타임라인의 timelineStart 위치에서 재생한다. 옮기기·양끝 자르기·분할은 이 값만 바꾼다
/// (원본 파일은 건드리지 않음).
struct TrackRegion: Identifiable, Equatable, Codable {
    var id = UUID()
    var timelineStart: TimeInterval
    var sourceStart: TimeInterval
    var duration: TimeInterval
    var timelineEnd: TimeInterval { timelineStart + duration }

    /// 파일 전체를 0초부터 놓은 편집 전 상태.
    static func whole(duration: TimeInterval) -> TrackRegion {
        TrackRegion(timelineStart: 0, sourceStart: 0, duration: duration)
    }
}

/// 분리된 세션 하나(보컬/드럼/…). 원본 파일, 리전 편집 상태, 볼륨, 켜진 패치와
/// 이 트랙을 재생하는 플레이어 노드들을 가진다. 노드를 엔진에 붙이고 예약하는 건 컨트롤러 몫.
final class StemTrack: ObservableObject, Identifiable {
    let id: String
    let displayName: String
    let colorName: String
    let file: AVAudioFile
    let fileURL: URL
    let duration: TimeInterval

    /// 원본 조각을 재생하는 플레이어들. 리전(과 패치 앞뒤 조각)마다 하나씩 필요해서 필요한 만큼 늘린다.
    /// 조각마다 따로 두고 "기기 시계의 정확한 시각"으로 미리 예약해 두면, 조각 경계에서
    /// 아무것도 다시 시작할 필요가 없어 다른 트랙에 영향이 없다.
    var originalNodes: [AVAudioPlayerNode] = []
    /// 켜진 패치마다 하나씩 두는 전용 플레이어. 패치(마이크 녹음)는 원본 스템과 채널 수·샘플레이트가
    /// 달라서 원본 플레이어에 그대로 넣으면 형식이 안 맞는다. 패치 파일 형식으로 따로 연결하고 볼륨도 따로 둔다.
    var patchPlayers: [UUID: PatchPlayer] = [:]
    var allNodes: [AVAudioPlayerNode] { originalNodes + patchPlayers.values.map(\.node) }

    /// 편집 가능한 리전 목록 (타임라인 순). 처음엔 파일 전체 하나.
    @Published var regions: [TrackRegion]
    /// 트랙 레인에 그릴 파형 (0~1로 정규화된 구간별 피크). 화면에서 비동기로 채운다.
    @Published var waveform: [Float] = []

    @Published var isMuted: Bool = false {
        didSet { applyVolume() }
    }
    @Published var volume: Float = 1.0 {
        didSet { applyVolume() }
    }
    /// 패치 구간에서 나오는 재녹음 소리의 볼륨 (원본 볼륨과 별개).
    @Published var patchVolume: Float = 1.0 {
        didSet { applyVolume() }
    }

    /// 지금 켜져서 들리는 패치들 (시간 순). 비어 있으면 원본만 재생.
    /// 서로 다른 구간의 패치는 함께 켤 수 있고(예: 통과한 수정 여러 개), 구간이 겹치는 패치는
    /// 동시에 켤 수 없다 — 하나를 켜면 겹치는 쪽이 꺼진다.
    @Published var activePatches: [Patch] = []

    func activePatch(id: UUID) -> Patch? {
        activePatches.first { $0.id == id }
    }

    func isActive(_ patchId: UUID) -> Bool {
        activePatch(id: patchId) != nil
    }

    init?(definition: StemDefinition, fileURL: URL) {
        guard let file = try? AVAudioFile(forReading: fileURL) else { return nil }
        self.id = definition.key
        self.displayName = definition.displayName
        self.colorName = definition.colorName
        self.file = file
        self.fileURL = fileURL
        self.duration = file.durationSeconds
        self.regions = [.whole(duration: duration)]
        applyVolume()
    }

    func applyVolume() {
        for node in originalNodes { node.volume = isMuted ? 0 : volume }
        for player in patchPlayers.values { player.node.volume = isMuted ? 0 : patchVolume }
    }

    func stopAll() {
        allNodes.forEach { $0.stop() }
    }
}

/// 켜진 패치 하나를 재생하는 자원: 녹음 파일 + 전용 플레이어.
final class PatchPlayer {
    let file: AVAudioFile
    let node = AVAudioPlayerNode()

    init(file: AVAudioFile) {
        self.file = file
    }
}

extension AVAudioFile {
    var durationSeconds: TimeInterval {
        let rate = processingFormat.sampleRate
        return rate > 0 ? Double(length) / rate : 0
    }
}
