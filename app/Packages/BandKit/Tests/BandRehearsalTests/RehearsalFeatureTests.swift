import BandFoundation
import ComposableArchitecture
import Foundation
import Testing
@testable import BandRehearsal

/// 핀 대화 규칙: 녹음 2번 제한, 결론 합의, 곡에 반영(채택).
/// 저장소는 가짜로 바꾸고, 서버 전송은 `delegate(.opProduced)`로 나가는 값을 확인한다.
@MainActor
struct RehearsalFeatureTests {
    let songID = "song-1"
    let range: ClosedRange<TimeInterval> = 10...18

    private func makePin(id: UUID = UUID(), author: String = "leader", targets: [String] = ["bass"]) -> FeedbackItem {
        var pin = FeedbackItem(id: id, timeRange: range, text: "후렴 들어갈 때 킥을 한 박 늦게", targetSessionIds: targets)
        pin.author = author
        return pin
    }

    private func makePatch(id: UUID = UUID(), session: String = "bass", range: ClosedRange<TimeInterval>? = nil, adopted: Bool = false) -> Patch {
        let r = range ?? self.range
        return Patch(id: id, sessionId: session, startTime: r.lowerBound, endTime: r.upperBound, isAdopted: adopted)
    }

    private func makeStore(me: Person, pins: [FeedbackItem] = [], patches: [Patch] = []) -> TestStoreOf<RehearsalFeature> {
        var state = RehearsalFeature.State()
        state.me = me
        state.songID = songID
        state.pins = IdentifiedArray(uniqueElements: pins)
        state.patches = IdentifiedArray(uniqueElements: patches)
        let store = TestStore(initialState: state) { RehearsalFeature() } withDependencies: {
            $0.uuid = .incrementing
            $0.date.now = Date(timeIntervalSince1970: 1_000)
            $0.storageClient.saveFeedback = { _, _ in }
            $0.storageClient.savePatches = { _, _ in }
            $0.storageClient.savePatchFile = { file, _, _ in file }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        return store
    }

    private func attempt(patch: Patch) -> FeedbackAttempt {
        FeedbackAttempt(sessionId: patch.sessionId, patchId: patch.id)
    }

    // MARK: 녹음으로 답하기는 최대 2번

    @Test func 녹음으로_답하기를_누르면_내_트랙_녹음을_요청한다() async {
        let pin = makePin()
        let store = makeStore(me: .session("bass"), pins: [pin])

        await store.send(.replyByRecordingTapped(pin: pin.id)) { $0.replyingTo = pin.id }
        await store.receive(\.delegate.recordRequested)
    }

    @Test func 녹음으로_두_번_답한_핀은_세_번째_요청을_무시한다() async {
        var pin = makePin()
        pin.attempts = [attempt(patch: makePatch()), attempt(patch: makePatch())]
        let store = makeStore(me: .session("bass"), pins: [pin])

        store.exhaustivity = .on
        await store.send(.replyByRecordingTapped(pin: pin.id))   // 상태 변화도 delegate도 없다
    }

    @Test func 저장된_녹음은_시도로_붙고_서버로_보낼_변경이_나간다() async {
        let pin = makePin()
        let store = makeStore(me: .session("bass"), pins: [pin])
        await store.send(.replyByRecordingTapped(pin: pin.id)) { $0.replyingTo = pin.id }
        await store.receive(\.delegate.recordRequested)

        await store.send(.recordingFinished(file: URL(fileURLWithPath: "/tmp/take.caf"), track: "bass", range: range))
        await store.receive(\.recordingSaved.success)
        await store.receive(\.delegate.opProduced)   // patchUpserted
        await store.receive(\.delegate.opProduced)   // attemptAdded

        #expect(store.state.pins[id: pin.id]?.attempts.count == 1)
        #expect(store.state.patches.count == 1)
        #expect(store.state.replyingTo == nil)
    }

    @Test func 그_사이_두_번을_채웠으면_세_번째_녹음은_시도로_붙지_않는다() async {
        var pin = makePin()
        pin.attempts = [attempt(patch: makePatch()), attempt(patch: makePatch())]
        var state = RehearsalFeature.State()
        state.me = .session("bass")
        state.pins = [pin]
        state.replyingTo = pin.id          // 요청한 시점에는 아직 1번이었다고 가정
        let store = TestStore(initialState: state) { RehearsalFeature() } withDependencies: {
            $0.uuid = .incrementing
            $0.date.now = Date(timeIntervalSince1970: 1_000)
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.recordingSaved(.success(makePatch())))
        #expect(store.state.pins[id: pin.id]?.attempts.count == 2)   // 늘어나지 않는다
    }

    // MARK: 결론은 관련자 전원이 동의해야 정리된다

    @Test func 결론을_제안하면_제안자만_동의한_상태이고_아직_반영되지_않는다() async {
        let patch = makePatch()
        var pin = makePin()
        pin.attempts = [attempt(patch: patch)]
        let store = makeStore(me: .leader, pins: [pin], patches: [patch])

        await store.send(.conclusionProposed(pin: pin.id, text: "이 녹음처럼 하자", kind: .tempo,
                                             attempt: pin.attempts[0].id, tool: nil))
        await store.receive(\.delegate.opProduced)

        let updated = store.state.pins[id: pin.id]!
        #expect(updated.status == .proposed)
        #expect(updated.conclusion?.agreedBy == ["leader"])
        #expect(store.state.patches[id: patch.id]?.isAdopted == false)
    }

    @Test func 마지막_관련자가_동의하면_그_녹음이_곡에_반영된다() async {
        let patch = makePatch()
        var pin = makePin()
        pin.attempts = [attempt(patch: patch)]
        pin.conclusion = FeedbackConclusion(text: "이 녹음처럼 하자", kind: .tempo, attemptId: pin.attempts[0].id,
                                            proposer: "leader")
        let store = makeStore(me: .session("bass"), pins: [pin], patches: [patch])

        await store.send(.conclusionAgreed(pin: pin.id, conclusion: pin.conclusion!.id))
        await store.receive(\.delegate.opProduced)        // conclusionAgreed
        await store.receive(\.delegate.opProduced)        // patchUpserted(채택)
        await store.receive(\.delegate.adoptionChanged)

        #expect(store.state.pins[id: pin.id]?.status == .concluded)
        #expect(store.state.patches[id: patch.id]?.isAdopted == true)
    }

    @Test func 관련자가_아닌_사람의_동의는_무시한다() async {
        var pin = makePin(targets: ["bass"])
        pin.conclusion = FeedbackConclusion(text: "킥을 한 박 늦게", kind: nil, attemptId: nil, proposer: "leader")
        let store = makeStore(me: .session("drums"), pins: [pin])

        store.exhaustivity = .on
        await store.send(.conclusionAgreed(pin: pin.id, conclusion: pin.conclusion!.id))
    }

    @Test func 이미_동의한_사람이_또_동의해도_무시한다() async {
        var pin = makePin(targets: ["bass"])
        pin.conclusion = FeedbackConclusion(text: "킥을 한 박 늦게", kind: nil, attemptId: nil, proposer: "leader")
        let store = makeStore(me: .leader, pins: [pin])   // 제안자는 이미 동의한 상태

        store.exhaustivity = .on
        await store.send(.conclusionAgreed(pin: pin.id, conclusion: pin.conclusion!.id))
    }

    @Test func 새_결론을_제안하면_기존_동의가_지워진다() async {
        var pin = makePin(targets: ["bass"])
        var old = FeedbackConclusion(text: "예전 결론", kind: nil, attemptId: nil, proposer: "leader")
        old.agreedBy.append("bass")
        pin.conclusion = old
        let store = makeStore(me: .leader, pins: [pin])

        await store.send(.conclusionProposed(pin: pin.id, text: "새 결론", kind: nil, attempt: nil, tool: nil))
        await store.receive(\.delegate.opProduced)

        #expect(store.state.pins[id: pin.id]?.conclusion?.agreedBy == ["leader"])
        #expect(store.state.pins[id: pin.id]?.status == .proposed)
    }

    @Test func 결론을_거두면_곡에_반영한_녹음이_해제된다() async {
        let patch = makePatch(adopted: true)
        var pin = makePin()
        pin.attempts = [attempt(patch: patch)]
        var conclusion = FeedbackConclusion(text: "이 녹음처럼 하자", kind: nil, attemptId: pin.attempts[0].id, proposer: "leader")
        conclusion.agreedBy.append("bass")
        pin.conclusion = conclusion
        let store = makeStore(me: .leader, pins: [pin], patches: [patch])

        await store.send(.conclusionCleared(pin: pin.id))
        await store.receive(\.delegate.opProduced)        // conclusionCleared
        await store.receive(\.delegate.opProduced)        // patchUpserted(해제)
        await store.receive(\.delegate.adoptionChanged)

        #expect(store.state.pins[id: pin.id]?.status == .discussing)
        #expect(store.state.patches[id: patch.id]?.isAdopted == false)
    }

    // MARK: 곡에 반영(채택)은 같은 세션·같은 구간에 하나만

    @Test func 겹치는_구간을_새로_반영하면_기존_반영은_해제된다() async {
        let old = makePatch(range: 10...18, adopted: true)
        let new = makePatch(range: 14...22)
        let store = makeStore(me: .leader, patches: [old, new])

        await store.send(.adoptToggled(new.id))

        #expect(store.state.patches[id: new.id]?.isAdopted == true)
        #expect(store.state.patches[id: old.id]?.isAdopted == false)
    }

    @Test func 다른_세션의_채택은_겹쳐도_그대로다() async {
        let drums = makePatch(session: "drums", range: 10...18, adopted: true)
        let bass = makePatch(session: "bass", range: 10...18)
        let store = makeStore(me: .leader, patches: [drums, bass])

        await store.send(.adoptToggled(bass.id))

        #expect(store.state.patches[id: bass.id]?.isAdopted == true)
        #expect(store.state.patches[id: drums.id]?.isAdopted == true)
    }

    // MARK: 서버 상태

    @Test func 서버_상태에서_채택이_달라진_패치만_Player에_알린다() async {
        let unchanged = makePatch(session: "drums", range: 0...4, adopted: true)
        let before = makePatch(adopted: false)
        var after = before
        after.isAdopted = true
        let store = makeStore(me: .leader, patches: [unchanged, before])

        await store.send(.remoteReplaced(feedback: [], patches: [unchanged, after]))
        await store.receive(\.delegate.adoptionChanged)   // 새로 반영된 것만

        #expect(store.state.patches[id: before.id]?.isAdopted == true)
    }

    // MARK: 연습

    @Test func 연습_시작은_Practice에_요청한다() async {
        var pin = makePin()
        pin.kind = .tempo
        let store = makeStore(me: .session("bass"), pins: [pin])

        await store.send(.practiceTapped(pin: pin.id))
        await store.receive(\.delegate.practiceRequested)
    }
}
