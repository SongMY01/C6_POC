import BandFoundation
import BandServices
import ComposableArchitecture
import Foundation

/// 여러 iPad가 공유하는 서버와 동기화한다. 지금의 `SyncClient.shared`(싱글톤)가 하던 일이다.
///
/// - 로컬 변경은 큐에 쌓아 순서대로 보낸다. 연결이 끊기면 큐를 보존했다가 다시 보낸다.
/// - 3초마다 서버 상태를 받는다. 아직 보내지 못한 내 변경이 있으면 받은 상태를 적용하지 않는다.
@Reducer
public struct SyncFeature {
    @ObservableState
    public struct State: Equatable {
        public enum Status: Equatable, Sendable {
            case offline
            case syncing
            case synced(Date)
            case failed(String)
        }

        public var status: Status = .offline
        public var serverURL: URL?
        public var lastVersion = -1
        /// 아직 서버에 못 보낸 변경 (보낸 순서대로)
        public var queue: [SyncOp] = []
        public var isFlushing = false
        public var songJobID: String?

        public var pendingCount: Int { queue.count }

        public init() {}
    }

    public enum Action: Sendable {
        /// 화면이 나타날 때: 폴링 시작
        case task
        /// 화면이 사라질 때: 폴링 취소
        case teardown
        case configured(URL)
        /// Rehearsal이 만든 변경 하나 (부모가 `delegate(.opProduced)`를 이쪽으로 이어 준다)
        case enqueue(SyncOp)
        case pollTick
        case flushResponse(Result<Int, any Error>)
        case pullResponse(Result<RemoteState?, any Error>)
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Equatable, Sendable {
            case remoteReceived(RemoteState)
            case songJobChanged(String?)
        }
    }

    enum CancelID { case poll }

    @Dependency(\.syncClient) var sync
    @Dependency(\.continuousClock) var clock
    @Dependency(\.date.now) var now

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                return .run { [clock] send in
                    for await _ in clock.timer(interval: .seconds(3)) { await send(.pollTick) }
                }
                .cancellable(id: CancelID.poll, cancelInFlight: true)

            case .teardown:
                return .cancel(id: CancelID.poll)

            case let .configured(url):
                state.serverURL = url
                state.lastVersion = -1
                return .send(.pollTick)

            case let .enqueue(op):
                state.queue.append(op)
                return flush(&state)   // 폴링을 기다리지 않고 바로 한 번 보낸다

            case .pollTick:
                guard state.serverURL != nil else { return .none }
                if !state.queue.isEmpty { return flush(&state) }
                guard let url = state.serverURL else { return .none }
                let since = state.lastVersion
                return .run { [sync] send in
                    do { await send(.pullResponse(.success(try await sync.pull(url, since)))) }
                    catch { await send(.pullResponse(.failure(error))) }
                }

            case let .flushResponse(.success(sent)):
                state.isFlushing = false
                state.queue.removeFirst(min(sent, state.queue.count))
                state.status = .synced(now)
                // 보내는 사이 새로 쌓인 변경이 있으면 이어서 보낸다
                return flush(&state)

            case .flushResponse(.failure):
                // 연결이 안 되면 큐를 그대로 두고 다음 주기에 다시 보낸다 (실패가 아니라 오프라인)
                state.isFlushing = false
                state.status = .offline
                return .none

            case let .pullResponse(.success(remote)):
                guard let remote else {
                    state.status = .synced(now)
                    return .none
                }
                // 아직 못 보낸 내 변경이 있으면 서버 상태를 적용하지 않는다 (내 변경이 깜빡이며 사라지는 것을 막는다)
                guard state.queue.isEmpty, remote.version != state.lastVersion else { return .none }
                state.lastVersion = remote.version
                state.status = .synced(now)
                var effects: [Effect<Action>] = [.send(.delegate(.remoteReceived(remote)))]
                if remote.songJobId != state.songJobID {
                    state.songJobID = remote.songJobId
                    effects.append(.send(.delegate(.songJobChanged(remote.songJobId))))
                }
                return .concatenate(effects)

            case .pullResponse(.failure):
                state.status = .offline
                return .none

            case .delegate:
                return .none
            }
        }
    }

    /// 큐 앞에서부터 한 번에 보낸다. 이미 보내는 중이거나 보낼 게 없으면 아무것도 하지 않는다.
    private func flush(_ state: inout State) -> Effect<Action> {
        guard let url = state.serverURL, !state.queue.isEmpty, !state.isFlushing else { return .none }
        state.isFlushing = true
        state.status = .syncing
        let ops = state.queue
        return .run { [sync] send in
            do {
                try await sync.send(ops, url)
                await send(.flushResponse(.success(ops.count)))
            } catch {
                await send(.flushResponse(.failure(error)))
            }
        }
    }
}
