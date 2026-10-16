import BandFoundation
import ComposableArchitecture
import Foundation
import Testing
@testable import BandPractice

/// 연습 흐름 테스트. 오디오와 시간은 가짜로 바꿔서 검증한다.
@MainActor
struct PracticeFeatureTests {
    let region: ClosedRange<TimeInterval> = 10...18
    let ladderPlan = PracticePlan(countIn: false, ladder: [0.8, 0.9, 1.0])

    @Test func 사다리는_느린_단계_두_바퀴_마지막_한_바퀴() async {
        let store = TestStore(initialState: PracticeFeature.State()) { PracticeFeature() }

        await store.send(.startTapped(feedbackID: nil, region: region, plan: ladderPlan, bpm: 120)) {
            $0.region = self.region
            $0.plan = self.ladderPlan
            $0.phase = .running
        }
        await store.receive(\.delegate.playback) // 80%로 시작

        await store.send(.loopWrapped) { $0.loopsDone = 1 }
        await store.send(.loopWrapped) { $0.rungIndex = 1; $0.loopsDone = 0 }   // 두 바퀴 → 90%
        await store.receive(\.delegate.playback)

        await store.send(.loopWrapped) { $0.loopsDone = 1 }
        await store.send(.loopWrapped) { $0.rungIndex = 2; $0.loopsDone = 0 }   // 두 바퀴 → 100%
        await store.receive(\.delegate.playback)

        await store.send(.loopWrapped) { $0.loopsDone = 1; $0.phase = .finished }   // 한 바퀴 → 끝
        await store.receive(\.delegate.playback)
        await store.receive(\.delegate.finished)
    }

    @Test func 사다리가_없으면_그만을_누를_때까지_반복한다() async {
        let store = TestStore(initialState: PracticeFeature.State()) { PracticeFeature() }
        await store.send(.startTapped(feedbackID: nil, region: region, plan: PracticePlan(), bpm: 120)) {
            $0.region = self.region
            $0.phase = .running
        }
        await store.receive(\.delegate.playback)

        for _ in 0..<5 { await store.send(.loopWrapped) { $0.loopsDone += 1 } }
        #expect(store.state.phase == .running)

        await store.send(.stopTapped) { $0 = PracticeFeature.State() }
        await store.receive(\.delegate.playback)
    }

    @Test func 카운트인은_클릭_네_번_뒤_재생을_시작한다() async {
        let clock = TestClock()
        let clicks = LockIsolated<[Bool]>([])
        let store = TestStore(initialState: PracticeFeature.State()) { PracticeFeature() } withDependencies: {
            $0.continuousClock = clock
            $0.audioClient.click = { accent in clicks.withValue { $0.append(accent) } }
        }
        let plan = PracticePlan(countIn: true, ladder: [])

        await store.send(.startTapped(feedbackID: nil, region: region, plan: plan, bpm: 185)) {
            $0.region = self.region
            $0.plan = plan
            $0.bpm = 185
            $0.phase = .countIn(1)
        }
        // 185 BPM은 한 박이 0.32초라서 최소 간격 0.45초가 적용된다
        await clock.advance(by: .milliseconds(450))
        await store.receive(\.countInTicked) { $0.phase = .countIn(2) }
        await clock.advance(by: .milliseconds(450))
        await store.receive(\.countInTicked) { $0.phase = .countIn(3) }
        await clock.advance(by: .milliseconds(450))
        await store.receive(\.countInTicked) { $0.phase = .countIn(4) }
        await clock.advance(by: .milliseconds(450))
        await store.receive(\.countInFinished) { $0.phase = .running }
        await store.receive(\.delegate.playback)

        #expect(clicks.value == [true, false, false, false])   // 첫 박만 강세
    }

    @Test func 연습_중에_그만을_누르면_카운트인이_취소된다() async {
        let clock = TestClock()
        let store = TestStore(initialState: PracticeFeature.State()) { PracticeFeature() } withDependencies: {
            $0.continuousClock = clock
            $0.audioClient.click = { _ in }
        }
        let plan = PracticePlan(countIn: true, ladder: [])
        await store.send(.startTapped(feedbackID: nil, region: region, plan: plan, bpm: 120)) {
            $0.region = self.region
            $0.plan = plan
            $0.phase = .countIn(1)
        }
        await store.send(.stopTapped) { $0 = PracticeFeature.State() }
        await store.receive(\.delegate.playback)
        await clock.advance(by: .seconds(5))   // 취소됐으므로 아무 일도 일어나지 않는다
    }
}
