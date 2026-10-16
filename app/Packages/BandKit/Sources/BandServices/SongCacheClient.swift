import Dependencies
import DependenciesMacros
import Foundation

/// 받은 곡(스템 mp3)을 기기에 보관해서 서버 없이도 곡을 열 수 있게 한다. 담당: Session
@DependencyClient
public struct SongCacheClient: Sendable {
    public var cachedURL: @Sendable (_ jobID: String, _ stem: String) -> URL? = { _, _ in nil }
    public var isComplete: @Sendable (_ jobID: String) -> Bool = { _ in false }
    public var store: @Sendable (_ tempFile: URL, _ jobID: String, _ stem: String) throws -> URL
    public var lastJobID: @Sendable () -> String? = { nil }
    /// 열어 본 곡으로 기록하고 오래된 곡은 지운다 (최근 2곡 유지)
    public var markOpened: @Sendable (_ jobID: String) -> Void
}

extension SongCacheClient: DependencyKey {
    // TODO(Session 담당): 기존 SongCache(static enum)를 감싸서 구현한다.
    public static let liveValue = SongCacheClient()
    public static let testValue = SongCacheClient()
    public static let previewValue = SongCacheClient(
        cachedURL: { _, _ in nil },
        isComplete: { _ in false },
        store: { tempFile, _, _ in tempFile },
        lastJobID: { nil },
        markOpened: { _ in }
    )
}

extension DependencyValues {
    public var songCacheClient: SongCacheClient {
        get { self[SongCacheClient.self] }
        set { self[SongCacheClient.self] = newValue }
    }
}
