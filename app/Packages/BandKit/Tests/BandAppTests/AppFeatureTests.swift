import BandFoundation
import BandPlayer
import BandServices
import ComposableArchitecture
import Foundation
import Testing
@testable import BandApp

/// Feature 사이의 연결 표. 각 연결이 한 줄씩 테스트로 고정돼 있어서, 연결을 바꾸면 여기가 먼저 알려 준다.
@MainActor
struct AppFeatureTests {
    private func makeStore(customize: (inout AppFeature.State) -> Void = { _ in }) -> TestStoreOf<AppFeature> {
        var state = AppFeature.State()
        customize(&state)
        let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
            $0.uuid = .incrementing
            $0.continuousClock = TestClock()   // 시계가 흘러가지 않으니 주기 작업(폴링·카운트인)은 멈춰 있다
            $0.date.now = Date(timeIntervalSince1970: 1_000)
            // 하위 Feature의 부수 효과는 이 테스트의 관심사가 아니라서 아무 일도 안 하게 둔다
            $0.audioClient = .previewValue
            $0.storageClient = .previewValue
            $0.syncClient = .previewValue
            $0.songCacheClient = .previewValue
            $0.separationClient = .previewValue
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        return store
    }

    private let pinRange: ClosedRange<TimeInterval> = 10...18

    // MARK: 시작과 역할

    @Test func 시작하면_역할을_읽어_Rehearsal에_내려준다() async {
        let store = makeStore()
        store.dependencies.roleClient.current = { .session("bass") }

        await store.send(.task) { $0.me = .session("bass") }
        await store.receive(\.rehearsal.meChanged) { $0.rehearsal.me = .session("bass") }
    }

    @Test func 역할을_바꾸면_저장하고_Rehearsal에_알린다() async {
        let saved = LockIsolated<Person?>(nil)
        let store = makeStore()
        store.dependencies.roleClient.set = { person in saved.setValue(person) }

        await store.send(.roleChanged(.session("drums"))) { $0.me = .session("drums") }
        await store.receive(\.rehearsal.meChanged) { $0.rehearsal.me = .session("drums") }
        #expect(saved.value == .session("drums"))
    }

    // MARK: 곡

    @Test func 곡이_열리면_Player와_Rehearsal이_함께_시작한다() async {
        let store = makeStore()
        let song = Song(id: "job-1", tracks: [SongTrack(id: "bass", fileURL: URL(fileURLWithPath: "/b.mp3"))])

        await store.send(.session(.delegate(.songReady(song))))
        await store.receive(\.player.songLoaded)
        await store.receive(\.rehearsal.songOpened) { $0.rehearsal.songID = "job-1" }
    }

    @Test func 서버_주소가_정해지면_Sync에_알린다() async {
        let url = URL(string: "http://192.168.0.5:8756")!
        let store = makeStore()

        await store.send(.session(.delegate(.serverChanged(url))))
        await store.receive(\.sync.configured) { $0.sync.serverURL = url }
    }

    @Test func 서버가_공유_곡을_바꾸면_Session에_알린다() async {
        let store = makeStore()
        await store.send(.sync(.delegate(.songJobChanged("job-7"))))
        await store.receive(\.session.sharedSongChanged) { $0.session.sharedSongJobID = "job-7" }
    }

    // MARK: Rehearsal ↔ Sync, Player

    @Test func Rehearsal의_변경은_동기화_큐로_간다() async {
        let store = makeStore()
        let op = SyncOp.feedbackDeleted(UUID())

        await store.send(.rehearsal(.delegate(.opProduced(op))))
        await store.receive(\.sync.enqueue) { $0.sync.queue = [op] }
    }

    @Test func 곡에_반영된_녹음은_Player가_켠다() async {
        let patch = Patch(sessionId: "bass", startTime: 10, endTime: 18, isAdopted: true)
        let store = makeStore {
            $0.player.tracks = [PlayerFeature.TrackState(id: "bass")]
        }

        await store.send(.rehearsal(.delegate(.adoptionChanged(patch, on: true))))
        await store.receive(\.player.patchAdoptionApplied)
        #expect(store.state.player.tracks[id: "bass"]?.activePatches == [patch])
    }

    @Test func 녹음_요청은_Player가_받고_결과는_Rehearsal이_받는다() async {
        let store = makeStore { $0.player.tracks = [PlayerFeature.TrackState(id: "bass")] }
        let file = URL(fileURLWithPath: "/tmp/take.caf")

        await store.send(.rehearsal(.delegate(.recordRequested(track: "bass", range: pinRange))))
        await store.receive(\.player.recordTapped)
        #expect(store.state.player.recording == .recording(track: "bass", range: pinRange))

        await store.send(.player(.delegate(.recordingFinished(file: file, track: "bass", range: pinRange))))
        await store.receive(\.rehearsal.recordingFinished)
    }

    // MARK: 연습

    @Test func 핀의_연습_요청은_핀의_종류가_정한_방법으로_시작한다() async {
        var pin = FeedbackItem(timeRange: pinRange, text: "박자가 빨라져요", targetSessionIds: ["bass"], kind: .tempo)
        pin.author = Person.leaderID
        let store = makeStore { $0.bpm = 100 }

        await store.send(.rehearsal(.delegate(.practiceRequested(pin))))
        await store.receive(\.practice.startTapped) {
            $0.practice.feedbackID = pin.id
            $0.practice.region = self.pinRange
            $0.practice.plan = pin.plan          // 박자: 카운트인 + 80·90·100% 사다리
            $0.practice.bpm = 100
            $0.practice.phase = .countIn(1)
        }
        #expect(store.state.practice.plan.ladder == [0.8, 0.9, 1.0])
        await store.send(.practice(.stopTapped))
    }

    @Test func 연습_명령은_Player가_받고_한_바퀴는_Practice가_센다() async {
        var state = AppFeature.State()
        state.practice.phase = .running
        state.practice.region = pinRange
        state.practice.plan = PracticePlan(countIn: false, ladder: [0.8, 1.0])
        let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
            $0.audioClient = .previewValue
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.practice(.delegate(.playback(.setRate(0.9)))))
        await store.receive(\.player.practiceCommand) { $0.player.rate = 0.9 }

        await store.send(.player(.delegate(.loopWrapped)))
        await store.receive(\.practice.loopWrapped) { $0.practice.loopsDone = 1 }
    }

    // MARK: 서버 상태

    @Test func 서버에서_받은_상태는_Rehearsal이_통째로_덮어쓴다() async {
        let pin = FeedbackItem(timeRange: pinRange, text: "후렴", targetSessionIds: ["bass"])
        let remote = RemoteState(version: 3, songJobId: nil, feedback: [pin], patches: [])
        let store = makeStore()

        await store.send(.sync(.delegate(.remoteReceived(remote))))
        await store.receive(\.rehearsal.remoteReplaced) { $0.rehearsal.pins = [pin] }
    }
}
