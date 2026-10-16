import Foundation

/// 이 기기를 쓰는 사람 = 합주의 역할. 리더이거나 세션(악기 파트) 하나다.
/// 세션 ID는 분리된 스템의 key("vocals", "drums", "bass", "guitar", "piano")를 그대로 쓴다.
public enum Person: Hashable, Codable, Sendable {
    case leader
    case session(String)

    /// 저장·전송할 때 쓰는 문자열 ID. 리더는 "leader".
    public static let leaderID = "leader"

    public init(id: String) {
        self = id == Person.leaderID ? .leader : .session(id)
    }

    public var id: String {
        switch self {
        case .leader: return Person.leaderID
        case .session(let id): return id
        }
    }

    public var isLeader: Bool { self == .leader }
}
