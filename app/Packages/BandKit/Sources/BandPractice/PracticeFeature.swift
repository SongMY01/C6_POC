import BandFoundation
import BandServices
import ComposableArchitecture
import Foundation

/// 핀 하나를 "바로 시작해서" 연습하는 흐름: (카운트인) → (템포 사다리) → 끝.
///
/// 어떻게 연습할지는 핀의 종류가 정한다(`PracticePlan`). 재생을 직접 조작하지 않고
/// Player에게 `PracticeCommand`만 보낸다 (연결은 부모 `AppFeature`가 한다).
@Reducer
public struct PracticeFeature {
    @ObservableState
    public struct State: Equatable {
        public enum Phase: Equatable, Sendable {
            case idle
            case countIn(Int)   // 1...4
            case running
            case finished
        }

        /// 느린 단계는 두 바퀴, 마지막(100%)은 한 바퀴
        public static let loopsPerSlowRung = 2

        public var phase: Phase = .idle
        public var feedbackID: UUID?
        public var region: ClosedRange<TimeInterval>?
        public var plan = PracticePlan()
        /// 카운트인 클릭 간격을 정하는 곡의 BPM
        public var bpm: Double = 120
        public var rungIndex = 0
        /// 지금 단계에서 돈 바퀴 수
        public var loopsDone = 0

        public var isActive: Bool { phase != .idle }
        public var hasLadder: Bool { !plan.ladder.isEmpty }
        public var currentRate: Float { hasLadder ? plan.ladder[rungIndex] : 1 }
        public var loopsNeeded: Int { rungIndex == plan.ladder.count - 1 ? 1 : Self.loopsPerSlowRung }

        public init() {}
    }

    public enum Action: Equatable, Sendable {
        case startTapped(feedbackID: UUID?, region: ClosedRange<TimeInterval>, plan: PracticePlan, bpm: Double)
        case countInTicked(Int)
        case countInFinished
        /// Player가 "구간 한 바퀴가 끝났다"고 알려 준다
        case loopWrapped
        case rungTapped(Int)
        case restartTapped
        case stopTapped
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Equatable, Sendable {
            case playback(PracticeCommand)
            case finished(feedbackID: UUID?)
        }
    }

    enum CancelID { case countIn }

    @Dependency(\.audioClient) var audio
    @Dependency(\.continuousClock) var clock

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .startTapped(feedbackID, region, plan, bpm):
                state.feedbackID = feedbackID
                state.region = region
                state.plan = plan
                state.bpm = bpm
                state.rungIndex = 0
                state.loopsDone = 0
                return begin(&state)

            case let .countInTicked(beat):
                guard case .countIn = state.phase else { return .none }
                state.phase = .countIn(beat)
                return .none

            case .countInFinished:
                guard case .countIn = state.phase, let region = state.region else { return .none }
                state.phase = .running
                return .send(.delegate(.playback(.start(region, rate: state.currentRate))))

            case .loopWrapped:
                guard state.phase == .running else { return .none }
                state.loopsDone += 1
                guard state.loopsDone >= state.loopsNeeded else { return .none }
                if state.hasLadder, state.rungIndex < state.plan.ladder.count - 1 {
                    state.rungIndex += 1
                    state.loopsDone = 0
                    return .send(.delegate(.playback(.setRate(state.currentRate))))
                } else if state.hasLadder {
                    state.phase = .finished
                    return .concatenate(
                        .send(.delegate(.playback(.stop))),
                        .send(.delegate(.finished(feedbackID: state.feedbackID)))
                    )
                }
                // 사다리가 없으면 "그만"을 누를 때까지 반복한다.
                return .none

            case let .rungTapped(index):
                guard state.hasLadder, state.plan.ladder.indices.contains(index), state.region != nil else { return .none }
                state.rungIndex = index
                state.loopsDone = 0
                return begin(&state)

            case .restartTapped:
                guard state.region != nil else { return .none }
                state.rungIndex = 0
                state.loopsDone = 0
                return begin(&state)

            case .stopTapped:
                let wasActive = state.isActive
                state = State()
                return .concatenate(
                    .cancel(id: CancelID.countIn),
                    wasActive ? .send(.delegate(.playback(.stop))) : .none
                )

            case .delegate:
                return .none
            }
        }
    }

    /// 카운트인(켜져 있으면) 뒤 재생을 시작한다.
    private func begin(_ state: inout State) -> Effect<Action> {
        guard let region = state.region else { return .none }
        guard state.plan.countIn else {
            state.phase = .running
            return .concatenate(
                .cancel(id: CancelID.countIn),
                .send(.delegate(.playback(.start(region, rate: state.currentRate))))
            )
        }
        state.phase = .countIn(1)
        let interval = max(0.45, 60.0 / state.bpm / Double(state.currentRate))
        return .run { [audio, clock] send in
            for beat in 1...4 {
                if beat > 1 { await send(.countInTicked(beat)) }
                await audio.click(beat == 1)
                try await clock.sleep(for: .seconds(interval))
            }
            await send(.countInFinished)
        }
        .cancellable(id: CancelID.countIn, cancelInFlight: true)
    }
}
