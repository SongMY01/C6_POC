import BandFoundation
import BandServices
import ComposableArchitecture
import Foundation

/// 곡 분리와 곡 열기: 녹음 파일 선택 → 업로드 → 분리 → 스템 다운로드 → 곡이 열림.
/// 이미 분리된 공유 곡이나 기기에 저장된 곡은 서버 없이(저장본 우선) 바로 연다.
/// 지금의 `SessionViewModel`이 하던 일이다.
@Reducer
public struct SessionFeature {
    @ObservableState
    public struct State: Equatable {
        public enum Flow: Equatable, Sendable {
            case idle
            case fileSelected(name: String)
            case uploading
            case separating
            case downloadingStems(done: Int, total: Int)
            case ready
            case failed(String)
        }

        public var flow: Flow = .idle
        /// 지금 쓰는 서버 주소
        public var serverURL = URL(string: "http://127.0.0.1:8756")!
        /// 자동으로 찾을 서버 후보들 (앱이 시작할 때 부모가 채운다)
        public var serverCandidates: [URL] = []
        public var serverStatus: String?
        /// 사용자가 주소를 직접 입력했으면 자동 선택을 하지 않는다
        public var isManualServer = false
        public var pickedFile: URL?
        /// 이번에 분리한 작업
        public var jobID: String?
        /// 서버가 알려 준 공유 곡 (SyncFeature가 부모를 거쳐 전달)
        public var sharedSongJobID: String?
        /// 기기에 저장된 마지막 곡
        public var cachedSongJobID: String?
        var downloaded: [SongTrack] = []

        /// 서버를 못 찾아도 저장된 곡은 열린다
        public var openableJobID: String? { sharedSongJobID ?? cachedSongJobID }

        public init() {}
    }

    public enum Action: Sendable {
        /// 화면이 나타날 때: 저장된 곡 확인, 서버 찾기
        case task
        case cachedSongChecked(String?)
        case serverDetected(URL?)
        case serverURLEntered(URL)

        case fileSelected(URL)
        case startSeparationTapped
        case uploadResponse(Result<String, any Error>)
        case pollRequested
        case statusPolled(Result<JobStatus, any Error>)
        case stemDownloaded(index: Int, Result<SongTrack, any Error>)
        case downloadFinished

        /// 공유 곡 또는 저장된 곡 열기 (분리를 다시 하지 않는다)
        case loadSongTapped
        case sharedSongChanged(String?)
        case resetTapped
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Equatable, Sendable {
            case songReady(Song)
            /// 서버 주소가 정해졌다 → 부모가 Sync에 알려 준다
            case serverChanged(URL)
        }
    }

    enum CancelID { case detect, separation }

    @Dependency(\.separationClient) var separation
    @Dependency(\.songCacheClient) var songCache
    @Dependency(\.continuousClock) var clock

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            // MARK: 시작
            case .task:
                let candidates = state.serverCandidates
                return .merge(
                    .run { [songCache] send in
                        let last = songCache.lastJobID()
                        await send(.cachedSongChecked(last.flatMap { songCache.isComplete($0) ? $0 : nil }))
                    },
                    detectServer(candidates, isManual: state.isManualServer)
                )

            case let .cachedSongChecked(jobID):
                state.cachedSongJobID = jobID
                return .none

            case let .serverDetected(url):
                guard !state.isManualServer else { return .none }
                guard let url else {
                    state.serverStatus = "응답하는 서버 없음"
                    return .none
                }
                state.serverURL = url
                state.serverStatus = "서버 연결됨"
                return .send(.delegate(.serverChanged(url)))

            case let .serverURLEntered(url):
                state.serverURL = url
                state.isManualServer = true
                state.serverStatus = "직접 입력한 주소 사용"
                return .send(.delegate(.serverChanged(url)))

            // MARK: 분리
            case let .fileSelected(url):
                state.pickedFile = url
                state.flow = .fileSelected(name: url.lastPathComponent)
                return .none

            case .startSeparationTapped:
                guard let file = state.pickedFile else { return .none }
                state.flow = .uploading
                let baseURL = state.serverURL
                return .run { [separation] send in
                    do { await send(.uploadResponse(.success(try await separation.upload(file, baseURL)))) }
                    catch { await send(.uploadResponse(.failure(error))) }
                }
                .cancellable(id: CancelID.separation, cancelInFlight: true)

            case let .uploadResponse(.success(jobID)):
                state.jobID = jobID
                state.flow = .separating
                return .send(.pollRequested)

            case let .uploadResponse(.failure(error)):
                state.flow = .failed(error.localizedDescription)
                return .none

            case .pollRequested:
                guard let jobID = state.jobID else { return .none }
                let baseURL = state.serverURL
                return .run { [separation] send in
                    do { await send(.statusPolled(.success(try await separation.status(jobID, baseURL)))) }
                    catch { await send(.statusPolled(.failure(error))) }
                }
                .cancellable(id: CancelID.separation)

            case let .statusPolled(.success(status)):
                guard state.flow == .separating, let jobID = state.jobID else { return .none }
                switch status.state {
                case .queued, .processing:
                    return .run { [clock] send in
                        try await clock.sleep(for: .seconds(1.5))
                        await send(.pollRequested)
                    }
                    .cancellable(id: CancelID.separation)
                case .done:
                    return download(&state, jobID: jobID)
                case .error:
                    state.flow = .failed(status.error ?? "알 수 없는 오류")
                    return .none
                }

            case let .statusPolled(.failure(error)):
                state.flow = .failed(error.localizedDescription)
                return .none

            // MARK: 곡 열기 (저장본 우선)
            case .loadSongTapped:
                guard let jobID = state.openableJobID else { return .none }
                return download(&state, jobID: jobID)

            case let .stemDownloaded(index, .success(track)):
                state.downloaded.append(track)
                state.flow = .downloadingStems(done: index, total: Song.stemKeys.count)
                return .none

            case let .stemDownloaded(_, .failure(error)):
                state.flow = .failed(error.localizedDescription)
                state.downloaded = []
                return .cancel(id: CancelID.separation)

            case .downloadFinished:
                guard let jobID = state.jobID ?? state.openableJobID,
                      state.downloaded.count == Song.stemKeys.count else { return .none }
                let song = Song(id: jobID, tracks: state.downloaded)
                state.flow = .ready
                state.cachedSongJobID = jobID
                state.downloaded = []
                return .concatenate(
                    .run { [songCache] _ in songCache.markOpened(jobID) },
                    .send(.delegate(.songReady(song)))
                )

            case let .sharedSongChanged(jobID):
                state.sharedSongJobID = jobID
                return .none

            case .resetTapped:
                let candidates = state.serverCandidates
                let url = state.serverURL
                let manual = state.isManualServer
                let shared = state.sharedSongJobID
                let cached = state.cachedSongJobID
                state = State()
                state.serverCandidates = candidates
                state.serverURL = url
                state.isManualServer = manual
                state.sharedSongJobID = shared
                state.cachedSongJobID = cached
                return .cancel(id: CancelID.separation)

            case .delegate:
                return .none
            }
        }
    }

    /// 후보 주소 전부에 동시에 물어보고 가장 먼저 응답한 곳을 쓴다.
    private func detectServer(_ candidates: [URL], isManual: Bool) -> Effect<Action> {
        guard !isManual, !candidates.isEmpty else { return .none }
        return .run { [separation] send in
            let found = await withTaskGroup(of: URL?.self, returning: URL?.self) { group in
                for url in candidates {
                    group.addTask { await separation.health(url) ? url : nil }
                }
                for await result in group {
                    if let result { group.cancelAll(); return result }
                }
                return nil
            }
            await send(.serverDetected(found))
        }
        .cancellable(id: CancelID.detect, cancelInFlight: true)
    }

    /// 스템 5개를 받는다. 기기에 저장된 것은 서버에 묻지 않고 그대로 쓴다.
    private func download(_ state: inout State, jobID: String) -> Effect<Action> {
        state.downloaded = []
        state.flow = .downloadingStems(done: 0, total: Song.stemKeys.count)
        let baseURL = state.serverURL
        return .run { [separation, songCache] send in
            for (offset, stem) in Song.stemKeys.enumerated() {
                do {
                    let url: URL
                    if let cached = songCache.cachedURL(jobID, stem) {
                        url = cached
                    } else {
                        let temp = try await separation.downloadStem(jobID, stem, baseURL)
                        url = try songCache.store(temp, jobID, stem)
                    }
                    await send(.stemDownloaded(index: offset + 1, .success(SongTrack(id: stem, fileURL: url))))
                } catch {
                    await send(.stemDownloaded(index: offset + 1, .failure(error)))
                    return
                }
            }
            await send(.downloadFinished)
        }
        .cancellable(id: CancelID.separation, cancelInFlight: true)
    }
}
