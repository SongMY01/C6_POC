import BandFoundation
import BandPlayer
import BandPractice
import BandRehearsal
import BandServices
import BandSession
import BandSync
import ComposableArchitecture
import Foundation

/// Super Reducer. Feature 5개를 `Scope`로 조립하고, **Feature 사이의 연결은 여기서만** 한다.
///
/// Feature끼리는 서로 import하지 않는다(`Package.swift`가 컴파일러로 막는다).
/// 그래서 각 Feature는 "무슨 일이 일어났다"를 `delegate` 액션으로만 알리고,
/// 그걸 누구에게 어떻게 이어 줄지는 이 파일의 연결 표(`body`의 `Reduce`)가 정한다.
/// 새 연결이 필요하면 이 표와 `docs/architecture`의 연결 표를 함께 고친다.
@Reducer
public struct AppFeature {
    @ObservableState
    public struct State: Equatable {
        /// 이 기기의 사람(역할). 권한 판단에 필요한 값은 여기서 각 Feature로 내려준다.
        public var me: Person = .leader
        /// 카운트인 클릭 간격을 정하는 곡의 BPM
        public var bpm: Double = 120

        public var session = SessionFeature.State()
        public var player = PlayerFeature.State()
        public var rehearsal = RehearsalFeature.State()
        public var practice = PracticeFeature.State()
        public var sync = SyncFeature.State()

        public init() {}
    }

    public enum Action: Sendable {
        /// 앱이 시작될 때: 역할 읽기, 각 Feature의 시작 작업
        case task
        case roleChanged(Person)

        case session(SessionFeature.Action)
        case player(PlayerFeature.Action)
        case rehearsal(RehearsalFeature.Action)
        case practice(PracticeFeature.Action)
        case sync(SyncFeature.Action)
    }

    @Dependency(\.roleClient) var roleClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.session, action: \.session) { SessionFeature() }
        Scope(state: \.player, action: \.player) { PlayerFeature() }
        Scope(state: \.rehearsal, action: \.rehearsal) { RehearsalFeature() }
        Scope(state: \.practice, action: \.practice) { PracticeFeature() }
        Scope(state: \.sync, action: \.sync) { SyncFeature() }

        Reduce { state, action in
            switch action {
            // MARK: 시작과 역할
            case .task:
                state.me = roleClient.current()
                return .merge(
                    .send(.rehearsal(.meChanged(state.me))),
                    .send(.session(.task)),
                    .send(.player(.task)),
                    .send(.sync(.task))
                )

            case let .roleChanged(person):
                state.me = person
                roleClient.set(person)
                return .send(.rehearsal(.meChanged(person)))

            // MARK: 곡이 열리면 플레이어와 리허설이 함께 시작한다
            case let .session(.delegate(.songReady(song))):
                return .merge(
                    .send(.player(.songLoaded(song))),
                    .send(.rehearsal(.songOpened(song.id)))
                )

            case let .session(.delegate(.serverChanged(url))):
                return .send(.sync(.configured(url)))

            // MARK: Rehearsal ↔ Sync, Player
            case let .rehearsal(.delegate(.opProduced(op))):
                return .send(.sync(.enqueue(op)))                       // 로컬 변경은 전부 동기화 큐로

            case let .rehearsal(.delegate(.adoptionChanged(patch, on))):
                return .send(.player(.patchAdoptionApplied(patch, on: on)))   // 곡에 반영된 녹음을 재생에 켜고 끈다

            case let .rehearsal(.delegate(.recordRequested(track, range))):
                return .send(.player(.recordTapped(track: track, range: range)))   // 녹음은 오디오를 가진 Player가 한다

            case let .player(.delegate(.recordingFinished(file, track, range))):
                return .send(.rehearsal(.recordingFinished(file: file, track: track, range: range)))

            // MARK: 연습
            case let .rehearsal(.delegate(.practiceRequested(pin))):
                // 핀의 종류가 정한 연습 방법으로 시작한다
                return .send(.practice(.startTapped(feedbackID: pin.id, region: pin.timeRange, plan: pin.plan, bpm: state.bpm)))

            case let .practice(.delegate(.playback(command))):
                return .send(.player(.practiceCommand(command)))        // 구간 반복과 재생 속도

            case .player(.delegate(.loopWrapped)):
                return .send(.practice(.loopWrapped))                   // 사다리 단계가 넘어간다

            // MARK: 서버 상태
            case let .sync(.delegate(.remoteReceived(remote))):
                return .send(.rehearsal(.remoteReplaced(feedback: remote.feedback ?? [], patches: remote.patches ?? [])))

            case let .sync(.delegate(.songJobChanged(jobID))):
                return .send(.session(.sharedSongChanged(jobID)))       // 리더가 곡을 바꿨다는 알림

            default:
                return .none
            }
        }
    }
}
