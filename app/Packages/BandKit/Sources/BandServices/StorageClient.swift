import BandFoundation
import Dependencies
import DependenciesMacros
import Foundation

/// 기기에 저장하는 데이터(핀, 재녹음, 구간 편집). 담당: Rehearsal(핀·패치), Player(구간)
@DependencyClient
public struct StorageClient: Sendable {
    public var loadFeedback: @Sendable (_ songID: String) async throws -> [FeedbackItem] = { _ in [] }
    public var saveFeedback: @Sendable (_ songID: String, _ items: [FeedbackItem]) async throws -> Void
    public var loadPatches: @Sendable (_ songID: String) async throws -> [Patch] = { _ in [] }
    public var savePatches: @Sendable (_ songID: String, _ patches: [Patch]) async throws -> Void
    /// 방금 녹음한 임시 파일을 패치 파일로 옮긴다 — 저장된 위치
    public var savePatchFile: @Sendable (_ tempFile: URL, _ patchID: Patch.ID, _ songID: String) async throws -> URL
    public var patchFileURL: @Sendable (_ patchID: Patch.ID, _ songID: String) -> URL = { _, _ in URL(fileURLWithPath: "/dev/null") }
    public var loadRegions: @Sendable (_ songID: String) async throws -> [String: [TrackRegion]] = { _ in [:] }
    public var saveRegions: @Sendable (_ songID: String, _ regions: [String: [TrackRegion]]) async throws -> Void
}

extension StorageClient: DependencyKey {
    // TODO(Rehearsal·Player 담당): 기존 FeedbackStore/PatchStore/RegionStore의 파일 저장 부분을 감싸서 구현한다.
    public static let liveValue = StorageClient()
    public static let testValue = StorageClient()
    public static let previewValue = StorageClient(
        loadFeedback: { _ in [] },
        saveFeedback: { _, _ in },
        loadPatches: { _ in [] },
        savePatches: { _, _ in },
        savePatchFile: { tempFile, _, _ in tempFile },
        patchFileURL: { _, _ in URL(fileURLWithPath: "/dev/null") },
        loadRegions: { _ in [:] },
        saveRegions: { _, _ in }
    )
}

extension DependencyValues {
    public var storageClient: StorageClient {
        get { self[StorageClient.self] }
        set { self[StorageClient.self] = newValue }
    }
}
