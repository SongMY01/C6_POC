import Foundation

/// 응원 리액션 하나. "이 피드백(의 지금 시도)이 좋았어요" — 리더 컨펌 대신 누구나 가볍게 누른다.
struct FeedbackReaction: Identifiable, Codable, Equatable {
    let id: UUID
    let feedbackId: UUID
    let emoji: String
    /// 누른 사람 ("leader" 또는 세션 id)
    let author: String
    let createdAt: Date

    static let emojis = ["🔥", "🎯", "👏", "💪"]
}

/// 동료가 붙여 주는 칭호. 점수가 아니라 별명이라 평가받는 느낌이 없다.
struct PeerTitle: Identifiable, Codable, Equatable {
    let id: UUID
    /// 칭호를 받은 사람 (세션 id)
    let toSession: String
    let title: String
    /// 준 사람 ("leader" 또는 세션 id)
    let from: String
    let createdAt: Date

    static let presets = ["칼박 요정", "킥 장인", "분위기 메이커", "끈기왕", "리듬 감별사", "소리 요정"]
}

/// 지금 연습 중인 사람 (서버가 3초마다 모아 준다).
struct PresenceInfo: Identifiable, Decodable, Equatable {
    let device: String
    let role: String?
    let activity: String?
    var id: String { device }

    /// 지금 뭔가 하고 있는가
    var isActive: Bool { activity != nil }
}
