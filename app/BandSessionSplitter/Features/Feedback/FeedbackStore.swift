import Foundation

/// 피드백 스레드의 답글 하나.
/// - recording: 피드백 받은 세션이 그 구간을 다시 녹음한 패치를 올리고 코멘트를 요청한 것
/// - comment: 텍스트 코멘트 (보통 올라온 녹음에 대한 평가)
struct FeedbackReply: Identifiable, Codable, Equatable {
    enum Kind: String, Codable { case recording, comment }

    let id: UUID
    var kind: Kind
    var createdAt: Date
    /// 쓴 사람: "leader" 또는 세션 id("bass" 등). 녹음 답글이면 녹음한 세션.
    var author: String
    var text: String
    /// kind == .recording일 때 올린 패치 (PatchStore의 Patch.id).
    var patchId: UUID?

    static func recording(patch: Patch, note: String = "") -> FeedbackReply {
        FeedbackReply(id: UUID(), kind: .recording, createdAt: Date(), author: patch.sessionId, text: note, patchId: patch.id)
    }

    static func comment(_ text: String, author: String) -> FeedbackReply {
        FeedbackReply(id: UUID(), kind: .comment, createdAt: Date(), author: author, text: text, patchId: nil)
    }
}

/// 피드백 하나 = "이 구간(시작~끝)에 대해, 이 세션(들)에게 이런 말을 남겼다".
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
    /// 답글 스레드 (시간 순): 녹음 답변 → 코멘트 → 다시 녹음 …
    var replies: [FeedbackReply] = []

    /// 가장 최근 녹음 답변 뒤에 아직 코멘트가 없으면 "코멘트 요청 중".
    var isAwaitingComment: Bool {
        guard let lastRecording = replies.lastIndex(where: { $0.kind == .recording }) else { return false }
        return !replies[(lastRecording + 1)...].contains { $0.kind == .comment }
    }

    var recordingReplyCount: Int { replies.filter { $0.kind == .recording }.count }

    var timeRange: ClosedRange<TimeInterval> {
        startTime...endTime
    }

    var isForAllSessions: Bool { targetSessionIds.isEmpty }

    func isFor(sessionId: String) -> Bool {
        isForAllSessions || targetSessionIds.contains(sessionId)
    }

    init(id: UUID = UUID(), timeRange: ClosedRange<TimeInterval>, text: String, targetSessionIds: [String], createdAt: Date = Date()) {
        self.id = id
        self.startTime = timeRange.lowerBound
        self.endTime = timeRange.upperBound
        self.createdAt = createdAt
        self.text = text
        self.targetSessionIds = targetSessionIds
    }

    /// 예전(손글씨) 피드백 manifest에는 text/targetSessionIds가 없다 — 빈 내용·전체 세션으로 읽는다.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        startTime = try c.decode(TimeInterval.self, forKey: .startTime)
        endTime = try c.decode(TimeInterval.self, forKey: .endTime)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        targetSessionIds = try c.decodeIfPresent([String].self, forKey: .targetSessionIds) ?? []
        replies = try c.decodeIfPresent([FeedbackReply].self, forKey: .replies) ?? []
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

    func addReply(_ reply: FeedbackReply, to feedbackId: UUID) {
        guard let i = items.firstIndex(where: { $0.id == feedbackId }) else { return }
        items[i].replies.append(reply)
        persist()
    }

    func deleteReply(_ replyId: UUID, from feedbackId: UUID) {
        guard let i = items.firstIndex(where: { $0.id == feedbackId }) else { return }
        items[i].replies.removeAll { $0.id == replyId }
        persist()
    }

    func item(id: UUID) -> FeedbackItem? {
        items.first { $0.id == id }
    }
}
