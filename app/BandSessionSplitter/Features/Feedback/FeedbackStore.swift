import Foundation

/// 코멘트 하나. 쓴 사람은 "leader" 또는 세션 id("bass" 등).
struct FeedbackComment: Identifiable, Codable, Equatable {
    let id: UUID
    var author: String
    var text: String
    var createdAt: Date

    init(id: UUID = UUID(), author: String, text: String, createdAt: Date = Date()) {
        self.id = id
        self.author = author
        self.text = text
        self.createdAt = createdAt
    }
}

/// 시도 하나 = 피드백 받은 세션이 그 구간을 다시 녹음해 올린 것 + 그 녹음에 달린 코멘트.
/// 코멘트를 시도 아래에 두어서 "어느 녹음에 대한 말인지"가 항상 분명하다.
struct FeedbackAttempt: Identifiable, Codable, Equatable {
    let id: UUID
    /// 녹음한 세션 id
    var sessionId: String
    /// 올린 녹음 (PatchStore의 Patch.id)
    var patchId: UUID
    var createdAt: Date
    var comments: [FeedbackComment] = []

    init(id: UUID = UUID(), sessionId: String, patchId: UUID, createdAt: Date = Date(), comments: [FeedbackComment] = []) {
        self.id = id
        self.sessionId = sessionId
        self.patchId = patchId
        self.createdAt = createdAt
        self.comments = comments
    }
}

/// 피드백 진행 상태: 연습 필요 → (녹음 올림) 코멘트 요청 → (코멘트) 연습 필요 … → 통과
enum FeedbackStatus: Equatable {
    /// 아직 답이 없거나, 최신 시도에 코멘트가 달려 다시 연습해야 함
    case needsPractice
    /// 최신 시도를 올리고 코멘트(평가)를 기다리는 중
    case awaitingComment
    /// 리더가 통과 처리함
    case passed

    var label: String {
        switch self {
        case .needsPractice: return "연습 필요"
        case .awaitingComment: return "코멘트 요청"
        case .passed: return "통과"
        }
    }

    /// 여러 피드백이 한 표시로 묶였을 때 어떤 상태를 대표로 보여줄지 (주목할 것 먼저).
    var displayPriority: Int {
        switch self {
        case .awaitingComment: return 0
        case .needsPractice: return 1
        case .passed: return 2
        }
    }
}

/// 피드백 하나 = "이 구간(시작~끝)에 대해, 이 세션(들)에게 이런 말을 남겼다" + 그에 대한 시도들.
///
/// 피드백마다 자기 시간 구간(timeRange)을 갖는다 — 그래야 피드백을 탭했을 때
/// "그 구간을 자동으로 구간반복 설정"할 수 있다.
struct FeedbackItem: Identifiable, Codable, Equatable {
    let id: UUID
    var startTime: TimeInterval
    var endTime: TimeInterval
    var createdAt: Date
    var text: String
    /// 받는 세션 id(StemTrack.id: "bass" 등). 비어 있으면 전체 세션에게 보낸 피드백.
    var targetSessionIds: [String]
    /// 시도들 (오래된 순). 다시 연습해서 올릴 때마다 하나씩 늘어난다.
    var attempts: [FeedbackAttempt] = []
    /// 첫 시도 전에 오간 코멘트 (예: 피드백 내용 보충 설명).
    var comments: [FeedbackComment] = []
    /// 통과 처리된 시도. nil이면 아직 진행 중.
    var passedAttemptId: UUID?

    var status: FeedbackStatus {
        if passedAttemptId != nil { return .passed }
        if let latest = attempts.last, latest.comments.isEmpty { return .awaitingComment }
        return .needsPractice
    }

    var timeRange: ClosedRange<TimeInterval> {
        startTime...endTime
    }

    var isForAllSessions: Bool { targetSessionIds.isEmpty }

    func isFor(sessionId: String) -> Bool {
        isForAllSessions || targetSessionIds.contains(sessionId)
    }

    /// "N차 시도"의 N (1부터).
    func attemptNumber(of attemptId: UUID) -> Int? {
        attempts.firstIndex { $0.id == attemptId }.map { $0 + 1 }
    }

    init(id: UUID = UUID(), timeRange: ClosedRange<TimeInterval>, text: String, targetSessionIds: [String], createdAt: Date = Date()) {
        self.id = id
        self.startTime = timeRange.lowerBound
        self.endTime = timeRange.upperBound
        self.createdAt = createdAt
        self.text = text
        self.targetSessionIds = targetSessionIds
    }

    private enum CodingKeys: String, CodingKey {
        case id, startTime, endTime, createdAt, text, targetSessionIds, attempts, comments, passedAttemptId
        case replies // 예전 형식 (읽기 전용)
    }

    /// 예전 형식도 읽는다:
    /// - 손글씨 피드백: text/targetSessionIds 없음 → 빈 내용·전체 세션
    /// - 답글 목록(replies): 녹음 → 새 시도, 코멘트 → 직전 시도에 붙임 (시도 전이면 피드백 코멘트)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        startTime = try c.decode(TimeInterval.self, forKey: .startTime)
        endTime = try c.decode(TimeInterval.self, forKey: .endTime)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        targetSessionIds = try c.decodeIfPresent([String].self, forKey: .targetSessionIds) ?? []
        attempts = try c.decodeIfPresent([FeedbackAttempt].self, forKey: .attempts) ?? []
        comments = try c.decodeIfPresent([FeedbackComment].self, forKey: .comments) ?? []
        passedAttemptId = try c.decodeIfPresent(UUID.self, forKey: .passedAttemptId)

        if attempts.isEmpty, comments.isEmpty,
           let legacy = try c.decodeIfPresent([LegacyReply].self, forKey: .replies) {
            for reply in legacy {
                if reply.kind == "recording", let patchId = reply.patchId {
                    attempts.append(FeedbackAttempt(id: reply.id, sessionId: reply.author, patchId: patchId, createdAt: reply.createdAt))
                } else {
                    let comment = FeedbackComment(id: reply.id, author: reply.author, text: reply.text, createdAt: reply.createdAt)
                    if attempts.isEmpty { comments.append(comment) } else { attempts[attempts.count - 1].comments.append(comment) }
                }
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(startTime, forKey: .startTime)
        try c.encode(endTime, forKey: .endTime)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(text, forKey: .text)
        try c.encode(targetSessionIds, forKey: .targetSessionIds)
        try c.encode(attempts, forKey: .attempts)
        try c.encode(comments, forKey: .comments)
        try c.encodeIfPresent(passedAttemptId, forKey: .passedAttemptId)
    }

    private struct LegacyReply: Decodable {
        let id: UUID
        let kind: String
        let createdAt: Date
        let author: String
        let text: String
        let patchId: UUID?
    }
}

@MainActor
final class FeedbackStore: ObservableObject {
    @Published private(set) var items: [FeedbackItem] = []

    private let manifestURL: URL

    init(songTitle: String = "항해") {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("annotations", isDirectory: true)
            .appendingPathComponent(songTitle, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.manifestURL = dir.appendingPathComponent("feedback_manifest.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONDecoder().decode([FeedbackItem].self, from: data) else { return }
        items = decoded.sorted { $0.startTime < $1.startTime }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    private func update(_ feedbackId: UUID, _ change: (inout FeedbackItem) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == feedbackId }) else { return }
        change(&items[i])
        persist()
    }

    @discardableResult
    func addFeedback(timeRange: ClosedRange<TimeInterval>, text: String, targetSessionIds: [String]) -> FeedbackItem {
        let item = FeedbackItem(timeRange: timeRange, text: text, targetSessionIds: targetSessionIds)
        items.append(item)
        items.sort { $0.startTime < $1.startTime }
        persist()
        return item
    }

    func delete(_ item: FeedbackItem) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    func item(id: UUID) -> FeedbackItem? {
        items.first { $0.id == id }
    }

    /// 녹음을 새 시도로 올린다 → 코멘트 요청 상태. 통과했던 피드백이면 다시 열린다.
    func addAttempt(patch: Patch, to feedbackId: UUID) {
        update(feedbackId) {
            $0.attempts.append(FeedbackAttempt(sessionId: patch.sessionId, patchId: patch.id))
            $0.passedAttemptId = nil
        }
    }

    func deleteAttempt(_ attemptId: UUID, from feedbackId: UUID) {
        update(feedbackId) {
            $0.attempts.removeAll { $0.id == attemptId }
            if $0.passedAttemptId == attemptId { $0.passedAttemptId = nil }
        }
    }

    /// attemptId가 있으면 그 시도에, 없으면 피드백 자체에 코멘트를 단다.
    func addComment(_ text: String, author: String, to feedbackId: UUID, attemptId: UUID?) {
        let comment = FeedbackComment(author: author, text: text)
        update(feedbackId) { item in
            if let attemptId, let i = item.attempts.firstIndex(where: { $0.id == attemptId }) {
                item.attempts[i].comments.append(comment)
            } else {
                item.comments.append(comment)
            }
        }
    }

    func deleteComment(_ commentId: UUID, from feedbackId: UUID) {
        update(feedbackId) { item in
            item.comments.removeAll { $0.id == commentId }
            for i in item.attempts.indices {
                item.attempts[i].comments.removeAll { $0.id == commentId }
            }
        }
    }

    /// 시도를 통과 처리한다 (nil이면 다시 열기).
    func setPassed(_ attemptId: UUID?, for feedbackId: UUID) {
        update(feedbackId) { $0.passedAttemptId = attemptId }
    }
}
