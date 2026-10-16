import BandFoundation
import BandServices
import ComposableArchitecture
import Foundation

/// 트랙 믹스 · 구간 반복 · 구간 편집 · 재생 상태 · 녹음. 지금의 `StemPlayerController` 중 "화면이 그리는 값"이다.
///
/// 오디오 엔진, 노드, 파일은 `AudioClient` 안에 있다.
/// **재생 위치(`currentTime`)는 State에 없다** — 화면의 재생헤드가 `AudioClient.position` 스트림을 직접 구독한다.
/// (초당 수십 번 오는 값을 Action으로 흘리면 부담이 커서다.)
@Reducer
public struct PlayerFeature {
    public struct TrackState: Equatable, Identifiable, Sendable {
        /// 세션 ID ("vocals", "bass" ...)
        public let id: String
        public var duration: TimeInterval = 0
        public var volume: Float = 1
        public var isMuted = false
        public var regions: [TrackRegion] = []
        /// 지금 켜져 있는(곡에 반영된) 재녹음. 같은 세션에서 구간이 겹치는 것은 하나만 켜진다.
        public var activePatches: [Patch] = []

        public init(id: String) { self.id = id }
    }

    public struct Loop: Equatable, Sendable {
        public var range: ClosedRange<TimeInterval>
        public var isEnabled = true
    }

    /// 제안된 믹스를 듣는 중: 끝나면 원래 볼륨으로 돌린다.
    public struct HeardMix: Equatable, Sendable {
        public var sourceID: UUID
        public var savedVolumes: [String: Float]
    }

    public enum Recording: Equatable, Sendable {
        case idle
        case recording(track: String, range: ClosedRange<TimeInterval>)
    }

    public enum Edge: Equatable, Sendable { case start, end }

    @ObservableState
    public struct State: Equatable {
        public var songID: String?
        public var tracks: IdentifiedArrayOf<TrackState> = []
        public var duration: TimeInterval = 0
        public var isPlaying = false
        public var loop: Loop?
        public var soloTrackID: String?
        /// 재생 속도 (연습 사다리가 바꾸는 값). 녹음은 항상 1.
        public var rate: Float = 1
        public var heardMix: HeardMix?
        public var recording: Recording = .idle
        public var errorMessage: String?

        public init() {}
    }

    public enum Action: Sendable {
        /// 화면이 나타날 때: 오디오 이벤트 구독 시작
        case task
        case teardown
        case songLoaded(Song)
        case loaded(Result<Loaded, any Error>)

        case playPauseTapped
        case playbackFailed(String)
        case seeked(TimeInterval)
        case loopMarked(Edge, at: TimeInterval)
        case loopToggled
        case loopCleared
        case soloTapped(String)
        case muteTapped(String)
        case volumeChanged(String, Float)

        case regionMoved(track: String, region: TrackRegion.ID, to: TimeInterval)
        case regionTrimmed(track: String, region: TrackRegion.ID, edge: Edge, to: TimeInterval)
        case regionSplit(track: String, at: TimeInterval)
        case regionDeleted(track: String, region: TrackRegion.ID)
        case regionsReset(track: String)

        /// Rehearsal의 채택 결과를 재생에 반영한다
        case patchAdoptionApplied(Patch, on: Bool)
        case patchActivationFailed(Patch.ID, track: String)
        case patchPlacementChanged(Patch)

        case mixHeard([String: Float], sourceID: UUID)
        case mixRestored

        case recordTapped(track: String, range: ClosedRange<TimeInterval>)
        case stopRecordingTapped
        case recordingFailed(String)

        /// Practice가 보내는 명령 (구간 반복 + 속도)
        case practiceCommand(PracticeCommand)
        case audioEvent(AudioEvent)
        case delegate(Delegate)

        public struct Loaded: Sendable {
            public var duration: TimeInterval
            public var regions: [String: [TrackRegion]]
            public init(duration: TimeInterval, regions: [String: [TrackRegion]]) {
                self.duration = duration
                self.regions = regions
            }
        }

        @CasePathable
        public enum Delegate: Equatable, Sendable {
            /// 구간 한 바퀴가 끝났다 (Practice가 사다리 단계를 센다)
            case loopWrapped
            case recordingFinished(file: URL, track: String, range: ClosedRange<TimeInterval>)
        }
    }

    enum CancelID { case events, saveRegions }

    @Dependency(\.audioClient) var audio
    @Dependency(\.storageClient) var storage
    @Dependency(\.continuousClock) var clock

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            // MARK: 오디오 이벤트 구독
            case .task:
                return .run { [audio] send in
                    for await event in audio.events() { await send(.audioEvent(event)) }
                }
                .cancellable(id: CancelID.events, cancelInFlight: true)

            case .teardown:
                return .merge(.cancel(id: CancelID.events), .cancel(id: CancelID.saveRegions))

            case let .audioEvent(event):
                switch event {
                case .ended, .interrupted:
                    state.isPlaying = false
                    return .none
                case .loopWrapped:
                    return .send(.delegate(.loopWrapped))
                case let .recordingFinished(file, track, range):
                    state.recording = .idle
                    return .send(.delegate(.recordingFinished(file: file, track: track, range: range)))
                }

            // MARK: 곡 불러오기
            case let .songLoaded(song):
                state.songID = song.id
                state.tracks = IdentifiedArray(uniqueElements: song.tracks.map { TrackState(id: $0.id) })
                state.isPlaying = false
                state.loop = nil
                state.rate = 1
                return .run { [audio, storage] send in
                    do {
                        let duration = try await audio.load(song.tracks)
                        let regions = try await storage.loadRegions(song.id)
                        await send(.loaded(.success(.init(duration: duration, regions: regions))))
                    } catch {
                        await send(.loaded(.failure(error)))
                    }
                }

            case let .loaded(.success(loaded)):
                state.duration = loaded.duration
                for id in state.tracks.ids {
                    state.tracks[id: id]?.duration = loaded.duration
                    state.tracks[id: id]?.regions = loaded.regions[id] ?? [.whole(duration: loaded.duration)]
                }
                return .none

            case let .loaded(.failure(error)):
                state.errorMessage = error.localizedDescription
                return .none

            // MARK: 재생
            case .playPauseTapped:
                guard !state.tracks.isEmpty else { return .none }
                if state.isPlaying {
                    state.isPlaying = false
                    return .run { [audio] _ in await audio.pause() }
                }
                state.isPlaying = true
                return .run { [audio] send in
                    do { try await audio.play() } catch { await send(.playbackFailed(error.localizedDescription)) }
                }

            case let .playbackFailed(message):
                state.isPlaying = false
                state.errorMessage = message
                return .none

            case let .seeked(time):
                return .run { [audio] _ in await audio.seek(time) }

            // MARK: 구간 반복
            case let .loopMarked(edge, time):
                let minLength = TimelineEditing.minLength
                let current = state.loop?.range
                var lower = current?.lowerBound ?? 0
                var upper = current?.upperBound ?? state.duration
                switch edge {
                case .start:
                    lower = max(0, min(time, state.duration))
                    if upper < lower + minLength { upper = min(state.duration, lower + minLength) }
                case .end:
                    upper = max(0, min(time, state.duration))
                    if lower > upper - minLength { lower = max(0, upper - minLength) }
                }
                guard lower <= upper else { return .none }
                state.loop = Loop(range: lower...upper, isEnabled: true)
                let range = lower...upper
                return .run { [audio] _ in await audio.setLoop(range) }

            case .loopToggled:
                guard var loop = state.loop else { return .none }
                loop.isEnabled.toggle()
                state.loop = loop
                let range = loop.isEnabled ? loop.range : nil
                return .run { [audio] _ in await audio.setLoop(range) }

            case .loopCleared:
                state.loop = nil
                return .run { [audio] _ in await audio.setLoop(nil) }

            // MARK: 믹스
            case let .soloTapped(id):
                state.soloTrackID = state.soloTrackID == id ? nil : id
                let solo = state.soloTrackID
                return .run { [audio] _ in await audio.setSolo(solo) }

            case let .muteTapped(id):
                guard state.tracks[id: id] != nil else { return .none }
                state.tracks[id: id]?.isMuted.toggle()
                let muted = state.tracks[id: id]?.isMuted ?? false
                return .run { [audio] _ in await audio.setMuted(id, muted) }

            case let .volumeChanged(id, volume):
                guard state.tracks[id: id] != nil else { return .none }
                state.tracks[id: id]?.volume = volume
                return .run { [audio] _ in await audio.setVolume(id, volume) }

            case let .mixHeard(mix, sourceID):
                // 처음 들을 때만 원래 볼륨을 저장한다 (믹스를 바꿔 가며 들어도 원래 볼륨은 그대로)
                if state.heardMix == nil {
                    state.heardMix = HeardMix(
                        sourceID: sourceID,
                        savedVolumes: Dictionary(uniqueKeysWithValues: state.tracks.map { ($0.id, $0.volume) })
                    )
                } else {
                    state.heardMix?.sourceID = sourceID
                }
                var applied: [String: Float] = [:]
                for (id, volume) in mix where state.tracks[id: id] != nil {
                    state.tracks[id: id]?.volume = volume
                    applied[id] = volume
                }
                let volumes = applied
                return .run { [audio] _ in
                    for (id, volume) in volumes { await audio.setVolume(id, volume) }
                }

            case .mixRestored:
                guard let saved = state.heardMix?.savedVolumes else { return .none }
                state.heardMix = nil
                for (id, volume) in saved where state.tracks[id: id] != nil { state.tracks[id: id]?.volume = volume }
                return .run { [audio] _ in
                    for (id, volume) in saved { await audio.setVolume(id, volume) }
                }

            // MARK: 구간 편집 (계산 규칙은 BandFoundation의 TimelineEditing)
            case let .regionMoved(track, region, newStart):
                return editRegions(&state, track: track) { $0.moveRegion(region, to: newStart) }

            case let .regionTrimmed(track, region, edge, time):
                let fileDuration = state.tracks[id: track]?.duration ?? 0
                return editRegions(&state, track: track) {
                    switch edge {
                    case .start: $0.trimRegionStart(region, to: time)
                    case .end: $0.trimRegionEnd(region, to: time, fileDuration: fileDuration)
                    }
                }

            case let .regionSplit(track, time):
                guard state.tracks[id: track]?.regions.regionSplittable(at: time) != nil else { return .none }
                return editRegions(&state, track: track) { _ = $0.splitRegion(at: time) }

            case let .regionDeleted(track, region):
                return editRegions(&state, track: track) { $0.removeAll { $0.id == region } }

            case let .regionsReset(track):
                let duration = state.tracks[id: track]?.duration ?? 0
                return editRegions(&state, track: track) { $0 = [.whole(duration: duration)] }

            // MARK: 재녹음(패치) 반영
            case let .patchAdoptionApplied(patch, on):
                guard state.tracks[id: patch.sessionId] != nil else { return .none }
                let track = patch.sessionId
                if on {
                    // 같은 세션에서 구간이 겹치는 패치는 동시에 켤 수 없다 → 겹치는 것은 끈다
                    let overlapping = state.tracks[id: track]?.activePatches.filter {
                        $0.id != patch.id && $0.startTime < patch.endTime && $0.endTime > patch.startTime
                    } ?? []
                    state.tracks[id: track]?.activePatches.removeAll { old in overlapping.contains { $0.id == old.id } || old.id == patch.id }
                    state.tracks[id: track]?.activePatches.append(patch)
                    let storage = self.storage
                    let songID = state.songID ?? ""
                    return .run { [audio] send in
                        for old in overlapping { await audio.deactivatePatch(old.id, track) }
                        let file = storage.patchFileURL(patch.id, songID)
                        if await !audio.activatePatch(patch, file) {
                            await send(.patchActivationFailed(patch.id, track: track))
                        }
                    }
                } else {
                    state.tracks[id: track]?.activePatches.removeAll { $0.id == patch.id }
                    return .run { [audio] _ in await audio.deactivatePatch(patch.id, track) }
                }

            case let .patchActivationFailed(patchID, track):
                state.tracks[id: track]?.activePatches.removeAll { $0.id == patchID }
                state.errorMessage = "재녹음을 켜지 못했어요"
                return .none

            case let .patchPlacementChanged(patch):
                guard let index = state.tracks[id: patch.sessionId]?.activePatches.firstIndex(where: { $0.id == patch.id }) else { return .none }
                state.tracks[id: patch.sessionId]?.activePatches[index] = patch
                let storage = self.storage
                let songID = state.songID ?? ""
                return .run { [audio] _ in
                    await audio.deactivatePatch(patch.id, patch.sessionId)
                    _ = await audio.activatePatch(patch, storage.patchFileURL(patch.id, songID))
                }

            // MARK: 녹음 (항상 원래 속도)
            case let .recordTapped(track, range):
                guard state.recording == .idle, state.tracks[id: track] != nil else { return .none }
                state.recording = .recording(track: track, range: range)
                state.rate = 1
                return .run { [audio] send in
                    await audio.setRate(1)
                    do { try await audio.startRecording(track, range) } catch { await send(.recordingFailed(error.localizedDescription)) }
                }

            case .stopRecordingTapped:
                guard case .recording = state.recording else { return .none }
                return .run { [audio] _ in await audio.stopRecording() }   // 결과는 audioEvent(.recordingFinished)로 온다

            case let .recordingFailed(message):
                state.recording = .idle
                state.errorMessage = message
                return .none

            // MARK: 연습 명령
            case let .practiceCommand(command):
                switch command {
                case let .start(range, rate):
                    state.rate = rate
                    state.loop = Loop(range: range, isEnabled: true)
                    state.isPlaying = true
                    return .run { [audio] send in
                        await audio.pause()
                        await audio.setRate(rate)
                        await audio.setLoop(range)
                        await audio.seek(range.lowerBound)
                        do { try await audio.play() } catch { await send(.playbackFailed(error.localizedDescription)) }
                    }
                case let .setRate(rate):
                    state.rate = rate
                    return .run { [audio] _ in await audio.setRate(rate) }
                case .stop:
                    state.rate = 1
                    state.isPlaying = false
                    return .run { [audio] _ in
                        await audio.pause()
                        await audio.setRate(1)
                    }
                }

            case .delegate:
                return .none
            }
        }
    }

    /// 구간 편집을 적용한 뒤: 곡 길이를 다시 계산하고, 엔진에 알리고, 멈추고 0.5초 뒤에 한 번만 저장한다.
    /// (드래그 중에는 변경이 초당 수십 번 일어나서 디바운스한다.)
    private func editRegions(_ state: inout State, track: String, _ change: (inout [TrackRegion]) -> Void) -> Effect<Action> {
        guard state.tracks[id: track] != nil else { return .none }
        change(&state.tracks[id: track]!.regions)
        state.duration = state.tracks.flatMap(\.regions).map(\.timelineEnd).max() ?? state.duration
        let regions = state.tracks[id: track]?.regions ?? []
        let all = Dictionary(uniqueKeysWithValues: state.tracks.map { ($0.id, $0.regions) })
        let songID = state.songID
        return .merge(
            .run { [audio] _ in await audio.regionsChanged(track, regions) },
            .run { [storage, clock] _ in
                try await clock.sleep(for: .milliseconds(500))
                if let songID { try? await storage.saveRegions(songID, all) }
            }
            .cancellable(id: CancelID.saveRegions, cancelInFlight: true)
        )
    }
}
