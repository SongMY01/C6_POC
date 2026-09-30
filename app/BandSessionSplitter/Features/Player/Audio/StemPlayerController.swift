import Foundation
import AVFoundation
import Combine

/// 분리된 세션(보컬/드럼/베이스/기타/피아노)을 하나의 타임라인으로
/// 동기 재생/뮤트/솔로할 수 있게 해주는 컨트롤러.
///
/// AVAudioEngine 기반: "재생하며 마이크로 재녹음"할 때 재생과 녹음이 같은 엔진의
/// 같은 시계를 공유해야 프레임 단위로 어긋나지 않는다.
///
/// 파일 구성
/// - 이 파일: 엔진 그래프, 재생 예약, 트랜스포트, 구간 반복, 솔로
/// - StemPlayerController+Editing.swift: 리전·패치 편집
/// - StemPlayerController+Recording.swift: 구간 재녹음
@MainActor
final class StemPlayerController: ObservableObject {
    @Published var tracks: [StemTrack] = []
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    /// solo 중인 트랙 id (nil이면 solo 없음)
    @Published var soloTrackId: String? {
        didSet { applySolo() }
    }

    /// 구간 반복(A-B loop) 구간. 어려운 마디를 계속 돌려 들으며 연습하기 위한 기능.
    @Published var loopRegion: ClosedRange<TimeInterval>?
    @Published var isLoopEnabled: Bool = false

    private(set) var engine = AVAudioEngine()
    private var displayTimer: Timer?
    private var audioSessionConfigured = false

    // 편집 저장 (+Editing)
    let regionStore = RegionStore()
    var regionSaveTask: Task<Void, Never>?

    // 재녹음 상태 (+Recording)
    @Published internal(set) var isRecording: Bool = false
    @Published internal(set) var pendingRecording: PendingPatchRecording?
    var recordingFile: AVAudioFile?
    var recordingTempURL: URL?
    var recordingMutedTrack: (track: StemTrack, wasMuted: Bool)?
    var recordingSessionConfigured = false
    var previewPlayer: AVAudioPlayer?

    /// 재생 시작 예약(at:)에 쓰는 여유 시간. 모든 트랙에 같은 목표 시각을 줘서 동기화 유지.
    private let startDelay: TimeInterval = 0.1

    /// 재생 기준점: "기기 시계(hostTime) anchorHostTime에 곡의 anchorSongTime 위치가 소리난다".
    /// 모든 노드를 이 기준으로 예약하므로, 현재 위치도 이 기준에서 바로 계산한다.
    private var anchorSongTime: TimeInterval = 0
    private var anchorHostTime: UInt64 = 0

    private func songTime(atHost host: UInt64) -> TimeInterval {
        guard host > anchorHostTime else { return anchorSongTime }
        return anchorSongTime + AVAudioTime.seconds(forHostTime: host - anchorHostTime)
    }

    // MARK: - 트랙 로드 / 엔진 그래프

    func load(tracks: [StemTrack]) {
        for old in self.tracks {
            detachNodes(of: old)
        }

        regionStore.restore(into: tracks)
        self.tracks = tracks
        recomputeDuration()
        currentTime = 0

        configureAudioSessionIfNeeded()
        for track in tracks {
            attachNodes(of: track)
        }
        if !engine.isRunning {
            engine.prepare()
            try? engine.start()
        }
    }

    private func attachNodes(of track: StemTrack) {
        for node in track.originalNodes {
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: track.file.processingFormat)
        }
        // 믹서에 연결된 입력이 하나도 없으면 engine.prepare()가 예외를 던진다 — 최소 하나는 미리 만든다.
        _ = originalNode(of: track, at: 0)
        for player in track.patchPlayers.values {
            attach(player)
        }
    }

    /// 패치 플레이어를 녹음 파일 형식 그대로 믹서에 연결한다.
    func attach(_ player: PatchPlayer) {
        engine.attach(player.node)
        engine.connect(player.node, to: engine.mainMixerNode, format: player.file.processingFormat)
    }

    func detach(_ player: PatchPlayer) {
        player.node.stop()
        if player.node.engine != nil { engine.detach(player.node) }
    }

    /// 원본 조각용 플레이어 i번째를 돌려준다. 모자라면 새로 만들어 엔진에 붙인다.
    private func originalNode(of track: StemTrack, at index: Int) -> AVAudioPlayerNode {
        while track.originalNodes.count <= index {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: track.file.processingFormat)
            track.originalNodes.append(node)
            track.applyVolume()
        }
        return track.originalNodes[index]
    }

    private func detachNodes(of track: StemTrack) {
        for node in track.allNodes {
            node.stop()
            if node.engine != nil { engine.detach(node) }
        }
    }

    /// 녹음(마이크 입력 노드가 그래프에 들어간 상태)이 끝나면 재생 전용 세션으로 되돌리는데,
    /// 입력 노드는 한 번 생기면 엔진에서 뺄 수 없고, 입력이 없는 .playback 세션에서
    /// 그 엔진을 다시 켜면 실패하거나 무음이 될 수 있다. 그래서 엔진을 새로 만들어 트랙을 다시 붙인다.
    func rebuildEngineForPlayback() {
        engine.stop()
        for track in tracks {
            detachNodes(of: track)
        }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)

        engine = AVAudioEngine()
        for track in tracks {
            attachNodes(of: track)
        }
        engine.prepare()
        try? engine.start()
        recordingSessionConfigured = false
    }

    private func configureAudioSessionIfNeeded() {
        guard !audioSessionConfigured else { return }
        audioSessionConfigured = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    // MARK: - 재생 예약

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard !tracks.isEmpty else { return }
        if !engine.isRunning {
            guard (try? engine.start()) != nil else { return }
        }

        // 출력 노드의 sampleTime으로 예약하면 출력 샘플레이트(실기기 48kHz)와 파일(44.1kHz)이
        // 다를 때 예약 시각이 먼 미래로 해석돼, 시간은 흐르는데 무음만 나온다(실기기에서 실제로 겪음).
        // 샘플레이트와 무관한 hostTime 기준으로 모든 트랙을 같은 순간에 시작시킨다.
        let startHost = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: startDelay)
        anchorSongTime = currentTime
        anchorHostTime = startHost

        for track in tracks {
            schedule(track: track, songTime: currentTime, hostTime: startHost)
        }
        isPlaying = true
        startDisplayTimer()
    }

    /// 한 트랙을 "기기 시계 hostTime에 곡의 songTime 위치가 소리나도록" 예약한다.
    /// 리전마다(패치가 켜져 있으면 패치 구간을 뺀 앞뒤 조각마다) 플레이어를 하나씩 배정하고,
    /// 각자 정확한 시각에 미리 예약해 둔다 — 조각 경계에서 아무것도 다시 시작하지 않으므로
    /// 편집·패치 전환을 해도 다른 트랙은 전혀 영향을 받지 않는다.
    private func schedule(track: StemTrack, songTime t: TimeInterval, hostTime h: UInt64) {
        track.stopAll()

        func host(at songT: TimeInterval) -> AVAudioTime {
            AVAudioTime(hostTime: h + AVAudioTime.hostTime(forSeconds: max(0, songT - t)))
        }

        let patches = track.activePatches.filter { track.patchPlayers[$0.id] != nil }

        // 원본 조각
        let file = track.file
        let rate = file.processingFormat.sampleRate
        var nodeIndex = 0
        for piece in track.regions.playbackPieces(excluding: patches.map(\.timeRange)) where piece.songEnd > t {
            let start = max(t, piece.songStart)
            let startFrame = AVAudioFramePosition((piece.sourceStart + (start - piece.songStart)) * rate)
            let endFrame = min(file.length, AVAudioFramePosition((piece.sourceStart + (piece.songEnd - piece.songStart)) * rate))
            guard endFrame > startFrame else { continue }
            let node = originalNode(of: track, at: nodeIndex)
            nodeIndex += 1
            node.scheduleSegment(file, startingFrame: startFrame, frameCount: AVAudioFrameCount(endFrame - startFrame), at: nil)
            node.play(at: host(at: start))
        }

        // 패치 조각: 녹음본의 sourceStart부터 구간 길이만큼만 (녹음 여백이 뒤 원본과 겹치지 않게)
        for patch in patches where t < patch.endTime {
            guard let player = track.patchPlayers[patch.id] else { continue }
            let patchFile = player.file
            let start = max(t, patch.startTime)
            let patchRate = patchFile.processingFormat.sampleRate
            let startFrame = AVAudioFramePosition((patch.sourceStart + start - patch.startTime) * patchRate)
            let endFrame = min(patchFile.length, AVAudioFramePosition((patch.sourceStart + patch.duration) * patchRate))
            if endFrame > startFrame {
                player.node.scheduleSegment(patchFile, startingFrame: startFrame,
                                            frameCount: AVAudioFrameCount(endFrame - startFrame), at: nil)
                player.node.play(at: host(at: start))
            }
        }
    }

    /// 재생 중이면 이 트랙만 지금 위치에 맞춰 다시 예약한다 — 다른 트랙은 건드리지 않는다.
    func rescheduleIfPlaying(_ track: StemTrack) {
        guard isPlaying else { return }
        let host = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.05)
        schedule(track: track, songTime: songTime(atHost: host), hostTime: host)
    }

    /// 곡 길이 = 원본 길이와 (옮겨서 뒤로 밀린) 리전 끝 중 가장 늦은 시점.
    func recomputeDuration() {
        duration = tracks.flatMap { t in [t.duration] + t.regions.map(\.timelineEnd) }.max() ?? 0
    }

    // MARK: - 트랜스포트

    func pause() {
        if isPlaying { currentTime = min(duration, songTime(atHost: mach_absolute_time())) }
        for track in tracks {
            track.stopAll()
        }
        isPlaying = false
        stopDisplayTimer()
    }

    func seek(to time: TimeInterval) {
        currentTime = max(0, min(time, duration))
        if isPlaying {
            // 재생 중 seek이면 새 위치 기준으로 동기화된 재생을 다시 예약.
            play()
        }
    }

    private func startDisplayTimer() {
        stopDisplayTimer()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncCurrentTime()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    private func stopDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    private func syncCurrentTime() {
        guard isPlaying else { return }
        currentTime = min(duration, songTime(atHost: mach_absolute_time()))

        if isLoopEnabled, let region = loopRegion, currentTime >= region.upperBound {
            // 구간 끝에 도달 -> 바로 구간 시작으로 되돌려 계속 재생
            seek(to: region.lowerBound)
            return
        }

        if duration > 0 && currentTime >= duration - 0.05 {
            isPlaying = false
            stopDisplayTimer()
            currentTime = 0
            for track in tracks {
                track.stopAll()
            }
        }
    }

    // MARK: - 구간 반복

    /// 현재 재생 위치를 구간 시작점으로 지정.
    func markLoopStart() {
        let start = currentTime
        let end = loopRegion?.upperBound ?? min(duration, start + 4)
        setLoopRegion(start: min(start, end), end: max(start, end))
    }

    /// 현재 재생 위치를 구간 끝점으로 지정.
    func markLoopEnd() {
        let end = currentTime
        let start = loopRegion?.lowerBound ?? max(0, end - 4)
        setLoopRegion(start: min(start, end), end: max(start, end))
    }

    private func setLoopRegion(start: TimeInterval, end: TimeInterval) {
        guard end > start else { return }
        loopRegion = start...end
    }

    /// 구간이 아직 없을 때 "구간 반복"을 켜면, 지금 위치 기준 4초짜리 기본 구간을 만든다.
    func ensureLoopRegion() {
        guard loopRegion == nil else { return }
        let start = currentTime
        let end = min(duration, start + 4)
        if end > start {
            loopRegion = start...end
        } else {
            loopRegion = max(0, duration - 4)...duration
        }
    }

    func clearLoop() {
        loopRegion = nil
        isLoopEnabled = false
    }

    // MARK: - 솔로

    func setSolo(_ trackId: String?) {
        soloTrackId = (soloTrackId == trackId) ? nil : trackId
    }

    private func applySolo() {
        for track in tracks {
            if let solo = soloTrackId {
                track.isMuted = (track.id != solo)
            } else {
                track.isMuted = false
            }
        }
    }

    deinit {
        displayTimer?.invalidate()
    }
}
