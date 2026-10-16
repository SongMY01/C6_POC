import Foundation

/// 분리된 스템 하나 (보컬, 드럼, 베이스, 기타, 피아노). `id`는 세션 ID와 같다.
public struct SongTrack: Equatable, Identifiable, Sendable {
    public var id: String
    public var fileURL: URL

    public init(id: String, fileURL: URL) {
        self.id = id
        self.fileURL = fileURL
    }
}

/// 열린 곡. Session이 만들고(`delegate(.songReady)`), 부모가 Player와 Rehearsal에 나눠 준다.
public struct Song: Equatable, Identifiable, Sendable {
    /// 분리 작업 ID (서버가 곡을 구분하는 값)
    public var id: String
    public var tracks: [SongTrack]

    public init(id: String, tracks: [SongTrack]) {
        self.id = id
        self.tracks = tracks
    }

    /// 앱이 보여 주는 세션(스템)들. 순서가 곧 화면의 트랙 순서다.
    public static let stemKeys = ["vocals", "drums", "bass", "guitar", "piano"]
}
