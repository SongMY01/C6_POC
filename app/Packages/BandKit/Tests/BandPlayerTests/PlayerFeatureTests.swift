import BandFoundation
import BandServices
import ComposableArchitecture
import Foundation
import Testing
@testable import BandPlayer

/// 재생 상태와 구간·믹스·녹음 규칙. 오디오 엔진은 호출 기록을 남기는 가짜로 바꾼다.
@MainActor
struct PlayerFeatureTests {
    /// 엔진에 어떤 명령이 갔는지 순서대로 기록한다
    final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ item: String) { lock.lock(); items.append(item); lock.unlock() }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
    }

    private func audio(_ calls: Calls) -> AudioClient {
        AudioClient(
            load: { _ in 240 },
            play: { calls.add("play") },
            pause: { calls.add("pause") },
            seek: { calls.add("seek \($0)") },
            setRate: { calls.add("rate \($0)") },
            setLoop: { calls.add("loop \($0.map { "\($0.lowerBound)-\($0.upperBound)" } ?? "off")") },
            setVolume: { calls.add("volume \($0) \($1)") },
            setMuted: { calls.add("mute \($0) \($1)") },
            setSolo: { calls.add("solo \($0 ?? "off")") },
            regionsChanged: { track, _ in calls.add("regions \(track)") },
            activatePatch: { patch, _ in calls.add("activate \(patch.sessionId)"); return true },
            deactivatePatch: { _, track in calls.add("deactivate \(track)") },
            startRecording: { track, _ in calls.add("record \(track)") },
            stopRecording: { calls.add("stopRecording") },
            click: { _ in },
            events: { .finished },
            position: { .finished }
        )
    }

    private func makeStore(calls: Calls, tracks: [String] = ["vocals", "bass"], customize: (inout PlayerFeature.State) -> Void = { _ in },
                           dependencies: (inout DependencyValues) -> Void = { _ in }) -> TestStoreOf<PlayerFeature> {
        var state = PlayerFeature.State()
        state.songID = "song-1"
        state.duration = 240
        state.tracks = IdentifiedArray(uniqueElements: tracks.map {
            var track = PlayerFeature.TrackState(id: $0)
            track.duration = 240
            track.regions = [.whole(duration: 240)]
            return track
        })
        customize(&state)
        let store = TestStore(initialState: state) { PlayerFeature() } withDependencies: {
            $0.audioClient = self.audio(calls)
            $0.storageClient.patchFileURL = { _, _ in URL(fileURLWithPath: "/tmp/patch.caf") }
            dependencies(&$0)
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        return store
    }

    private func patch(session: String = "bass", range: ClosedRange<TimeInterval>) -> Patch {
        Patch(sessionId: session, startTime: range.lowerBound, endTime: range.upperBound)
    }

    // MARK: 곡 불러오기

    @Test func 곡을_열면_길이와_구간이_채워진다() async {
        let calls = Calls()
        var state = PlayerFeature.State()
        state.songID = nil
        let store = TestStore(initialState: state) { PlayerFeature() } withDependencies: {
            $0.audioClient = self.audio(calls)
            $0.storageClient.loadRegions = { _ in [:] }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        let song = Song(id: "song-1", tracks: [SongTrack(id: "vocals", fileURL: URL(fileURLWithPath: "/a.mp3")),
                                              SongTrack(id: "bass", fileURL: URL(fileURLWithPath: "/b.mp3"))])

        await store.send(.songLoaded(song))
        await store.receive(\.loaded.success)

        #expect(store.state.duration == 240)
        #expect(store.state.tracks.count == 2)
        let regions = store.state.tracks[id: "bass"]?.regions
        #expect(regions?.count == 1)
        #expect(regions?.first?.timelineStart == 0)
        #expect(regions?.first?.duration == 240)   // 저장된 편집이 없으면 파일 전체 한 덩어리
    }

    // MARK: 재생

    @Test func 재생과_정지를_오간다() async {
        let calls = Calls()
        let store = makeStore(calls: calls)

        await store.send(.playPauseTapped) { $0.isPlaying = true }
        await store.send(.playPauseTapped) { $0.isPlaying = false }
        #expect(calls.all == ["play", "pause"])
    }

    @Test func 오디오가_끝났다고_알리면_재생_상태가_꺼진다() async {
        let store = makeStore(calls: Calls(), customize: { $0.isPlaying = true })
        await store.send(.audioEvent(.ended)) { $0.isPlaying = false }
    }

    // MARK: 녹음은 항상 원래 속도

    @Test func 녹음을_시작하면_속도를_원래대로_돌린다() async {
        let calls = Calls()
        let store = makeStore(calls: calls, customize: { $0.rate = 0.8 })

        await store.send(.recordTapped(track: "bass", range: 10...18)) {
            $0.rate = 1
            $0.recording = .recording(track: "bass", range: 10...18)
        }
        #expect(calls.all == ["rate 1.0", "record bass"])
    }

    @Test func 녹음이_끝나면_Rehearsal에_넘길_delegate가_나간다() async {
        let store = makeStore(calls: Calls(), customize: { $0.recording = .recording(track: "bass", range: 10...18) })
        let file = URL(fileURLWithPath: "/tmp/take.caf")

        await store.send(.audioEvent(.recordingFinished(file: file, track: "bass", range: 10...18))) { $0.recording = .idle }
        await store.receive(\.delegate.recordingFinished)
    }

    // MARK: 채택된 재녹음 켜기

    @Test func 같은_세션에서_구간이_겹치는_재녹음은_하나만_켜진다() async {
        let calls = Calls()
        let old = patch(range: 10...18)
        let new = patch(range: 14...22)
        let store = makeStore(calls: calls, customize: { $0.tracks[id: "bass"]?.activePatches = [old] })

        await store.send(.patchAdoptionApplied(new, on: true))

        #expect(store.state.tracks[id: "bass"]?.activePatches == [new])
        #expect(calls.all == ["deactivate bass", "activate bass"])   // 겹치던 것을 끄고 새로 켠다
    }

    @Test func 겹치지_않는_재녹음은_함께_켜진다() async {
        let first = patch(range: 10...18)
        let second = patch(range: 30...38)
        let store = makeStore(calls: Calls(), customize: { $0.tracks[id: "bass"]?.activePatches = [first] })

        await store.send(.patchAdoptionApplied(second, on: true))
        #expect(store.state.tracks[id: "bass"]?.activePatches.count == 2)
    }

    @Test func 재녹음을_해제하면_끄고_상태에서_뺀다() async {
        let calls = Calls()
        let on = patch(range: 10...18)
        let store = makeStore(calls: calls, customize: { $0.tracks[id: "bass"]?.activePatches = [on] })

        await store.send(.patchAdoptionApplied(on, on: false))
        #expect(store.state.tracks[id: "bass"]?.activePatches.isEmpty == true)
        #expect(calls.all == ["deactivate bass"])
    }

    // MARK: 믹스 듣기는 원래 볼륨을 저장했다가 복원

    @Test func 제안된_믹스를_듣고_끝내면_원래_볼륨으로_돌아간다() async {
        let calls = Calls()
        let store = makeStore(calls: calls, customize: { $0.tracks[id: "bass"]?.volume = 0.9 })
        let source = UUID()

        await store.send(.mixHeard(["bass": 0.4], sourceID: source))
        #expect(store.state.tracks[id: "bass"]?.volume == 0.4)
        #expect(store.state.heardMix?.savedVolumes["bass"] == 0.9)

        await store.send(.mixHeard(["bass": 0.2], sourceID: UUID()))   // 믹스를 바꿔 들어도 원래 볼륨은 그대로
        #expect(store.state.heardMix?.savedVolumes["bass"] == 0.9)

        await store.send(.mixRestored)
        #expect(store.state.tracks[id: "bass"]?.volume == 0.9)
        #expect(store.state.heardMix == nil)
    }

    // MARK: 구간 반복과 연습 명령

    @Test func 연습_시작_명령은_구간_반복과_속도를_함께_바꾼다() async {
        let calls = Calls()
        let store = makeStore(calls: calls)

        await store.send(.practiceCommand(.start(10...18, rate: 0.8)))
        #expect(store.state.rate == 0.8)
        #expect(store.state.loop == PlayerFeature.Loop(range: 10...18, isEnabled: true))
        #expect(store.state.isPlaying)
        #expect(calls.all == ["pause", "rate 0.8", "loop 10.0-18.0", "seek 10.0", "play"])
    }

    @Test func 연습_정지_명령은_속도를_원래대로_돌린다() async {
        let calls = Calls()
        let store = makeStore(calls: calls, customize: { $0.rate = 0.8; $0.isPlaying = true })

        await store.send(.practiceCommand(.stop))
        #expect(store.state.rate == 1)
        #expect(!store.state.isPlaying)
        #expect(calls.all == ["pause", "rate 1.0"])
    }

    @Test func 구간_한_바퀴_이벤트는_Practice로_이어진다() async {
        let store = makeStore(calls: Calls())
        await store.send(.audioEvent(.loopWrapped))
        await store.receive(\.delegate.loopWrapped)
    }

    // MARK: 구간 편집은 멈추고 0.5초 뒤 한 번만 저장

    @Test func 구간을_연속으로_옮겨도_저장은_한_번만_한다() async {
        let clock = TestClock()
        let saves = LockIsolated(0)
        let calls = Calls()
        let region = TrackRegion.whole(duration: 240)
        let store = makeStore(calls: calls, customize: { $0.tracks[id: "bass"]?.regions = [region] }, dependencies: {
            $0.continuousClock = clock
            $0.storageClient.saveRegions = { _, _ in saves.withValue { $0 += 1 } }
        })

        await store.send(.regionTrimmed(track: "bass", region: region.id, edge: .end, to: 200))
        await clock.advance(by: .milliseconds(300))
        await store.send(.regionTrimmed(track: "bass", region: region.id, edge: .end, to: 180))   // 이전 저장은 취소된다
        await clock.advance(by: .milliseconds(500))
        await store.finish()

        #expect(saves.value == 1)
        #expect(store.state.tracks[id: "bass"]?.regions.first?.duration == 180)
    }
}
