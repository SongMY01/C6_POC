import Dependencies
import DependenciesMacros
import Foundation

/// 분리 작업 상태 (서버 `/jobs/{id}` 응답)
public struct JobStatus: Equatable, Sendable {
    public enum State: String, Sendable { case queued, processing, done, error }
    public var state: State
    public var stems: [String]
    public var error: String?

    public init(state: State, stems: [String] = [], error: String? = nil) {
        self.state = state
        self.stems = stems
        self.error = error
    }
}

/// 곡 분리 서버(Demucs)와 통신한다. 담당: Session
@DependencyClient
public struct SeparationClient: Sendable {
    /// 이 주소의 서버가 살아 있는지 (`/health`)
    public var health: @Sendable (_ baseURL: URL) async -> Bool = { _ in false }
    /// 녹음 파일을 올리고 작업 ID를 받는다
    public var upload: @Sendable (_ file: URL, _ baseURL: URL) async throws -> String
    public var status: @Sendable (_ jobID: String, _ baseURL: URL) async throws -> JobStatus
    /// 분리된 스템(mp3) 하나를 받는다 — 받은 파일의 임시 위치
    public var downloadStem: @Sendable (_ jobID: String, _ stem: String, _ baseURL: URL) async throws -> URL
}

extension SeparationClient: DependencyKey {
    // TODO(Session 담당): 기존 SeparationService를 감싸서 구현한다.
    public static let liveValue = SeparationClient()
    public static let testValue = SeparationClient()
    public static let previewValue = SeparationClient(
        health: { _ in true },
        upload: { _, _ in "preview-job" },
        status: { _, _ in JobStatus(state: .done, stems: ["vocals", "drums", "bass", "guitar", "piano"]) },
        downloadStem: { _, _, _ in URL(fileURLWithPath: "/dev/null") }
    )
}

extension DependencyValues {
    public var separationClient: SeparationClient {
        get { self[SeparationClient.self] }
        set { self[SeparationClient.self] = newValue }
    }
}
