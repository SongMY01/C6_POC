import BandFoundation
import Dependencies
import DependenciesMacros
import Foundation

/// 여러 iPad가 공유하는 서버(`server/sync.py`)와 통신한다. 담당: Sync
@DependencyClient
public struct SyncClient: Sendable {
    /// 쌓인 변경을 서버로 보낸다 (순서대로)
    public var send: @Sendable (_ ops: [SyncOp], _ baseURL: URL) async throws -> Void
    /// 서버 상태를 받는다. 버전이 같으면 nil.
    public var pull: @Sendable (_ baseURL: URL, _ sinceVersion: Int) async throws -> RemoteState?
    public var uploadAudio: @Sendable (_ patchID: Patch.ID, _ file: URL, _ baseURL: URL) async throws -> Void
    /// 다른 기기가 올린 재녹음 파일을 받는다
    public var downloadAudio: @Sendable (_ patchID: Patch.ID, _ baseURL: URL) async throws -> URL
}

extension SyncClient: DependencyKey {
    // TODO(Sync 담당): 기존 SyncClient(싱글톤)의 flush/pull/uploadAudio/downloadMissingAudio를 감싸서 구현한다.
    public static let liveValue = SyncClient()
    public static let testValue = SyncClient()
    public static let previewValue = SyncClient(
        send: { _, _ in },
        pull: { _, _ in nil },
        uploadAudio: { _, _, _ in },
        downloadAudio: { _, _ in URL(fileURLWithPath: "/dev/null") }
    )
}

extension DependencyValues {
    public var syncClient: SyncClient {
        get { self[SyncClient.self] }
        set { self[SyncClient.self] = newValue }
    }
}
