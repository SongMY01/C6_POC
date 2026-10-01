import Foundation

/// 이 iPad를 누가 쓰는지. 유저테스트에서 iPad마다 한 명(리더 1 + 세션 연주자들)이 쓴다.
/// 코멘트 작성자, 녹음으로 답할 수 있는 세션, "통과" 권한, 피드백 목록 기본 필터가 이 값을 따른다.
enum DeviceRole {
    static let leader = FeedbackPeople.leader
    private static let key = "deviceRole"

    /// "leader" 또는 세션 id("vocals", "bass" …). 처음엔 리더.
    static var current: String {
        get { UserDefaults.standard.string(forKey: key) ?? leader }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static var isLeader: Bool { current == leader }

    /// 선택지: 리더 + 분리되는 세션들
    static var options: [(id: String, label: String)] {
        [(leader, "👑 리더")] + sessionStems.map { ($0.key, "\(emoji(for: $0.key)) \($0.displayName)") }
    }

    static func label(for id: String) -> String {
        options.first { $0.id == id }?.label ?? id
    }

    static func emoji(for sessionId: String) -> String {
        switch sessionId {
        case "vocals": return "🎤"
        case "drums": return "🥁"
        case "bass", "guitar": return "🎸"
        case "piano": return "🎹"
        default: return "🎵"
        }
    }
}
