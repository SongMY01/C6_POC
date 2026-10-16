import Foundation

/// 서버로 보내는 변경 하나. 지금의 `sync.send("feedback.add", ...)` 문자열 op 11개를 타입으로 바꾼 것이다.
/// Rehearsal이 만들고(`delegate(.opProduced)`), Sync가 큐에 쌓아 서버로 보낸다.
public enum SyncOp: Equatable, Sendable {
    case feedbackAdded(FeedbackItem)
    case feedbackDeleted(FeedbackItem.ID)
    case attemptAdded(feedback: FeedbackItem.ID, FeedbackAttempt)
    case attemptDeleted(feedback: FeedbackItem.ID, FeedbackAttempt.ID)
    case commentAdded(feedback: FeedbackItem.ID, attempt: FeedbackAttempt.ID?, FeedbackComment)
    case commentDeleted(feedback: FeedbackItem.ID, FeedbackComment.ID)
    case conclusionProposed(feedback: FeedbackItem.ID, FeedbackConclusion)
    case conclusionAgreed(feedback: FeedbackItem.ID, conclusion: FeedbackConclusion.ID, by: Person)
    case conclusionCleared(feedback: FeedbackItem.ID)
    case patchUpserted(Patch)
    case patchDeleted(Patch.ID)

    /// 서버와 주고받는 op 이름. 서버(server/sync.py)가 쓰는 문자열과 같아야 한다.
    public var wireName: String {
        switch self {
        case .feedbackAdded: return "feedback.add"
        case .feedbackDeleted: return "feedback.delete"
        case .attemptAdded: return "attempt.add"
        case .attemptDeleted: return "attempt.delete"
        case .commentAdded: return "comment.add"
        case .commentDeleted: return "comment.delete"
        case .conclusionProposed: return "conclusion.propose"
        case .conclusionAgreed: return "conclusion.agree"
        case .conclusionCleared: return "conclusion.clear"
        case .patchUpserted: return "patch.upsert"
        case .patchDeleted: return "patch.delete"
        }
    }
}

/// 서버가 내려주는 공유 상태 한 벌. 받으면 Rehearsal이 통째로 덮어쓴다.
public struct RemoteState: Decodable, Equatable, Sendable {
    public var version: Int
    public var songJobId: String?
    public var feedback: [FeedbackItem]?
    public var patches: [Patch]?

    public init(version: Int, songJobId: String? = nil, feedback: [FeedbackItem]? = nil, patches: [Patch]? = nil) {
        self.version = version
        self.songJobId = songJobId
        self.feedback = feedback
        self.patches = patches
    }
}
