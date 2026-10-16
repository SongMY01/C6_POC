import Foundation

/// 대화나 결론에 붙이는 "툴" 값: 종류별 입력창으로 만든 구체적인 제안 (박 표시, 믹스, 코드, 느낌).
/// 글로 설명하기 어려운 걸 보여 주고 들려 주는 용도 — 양식처럼 꼭 채워야 하는 건 아니다.
struct FeedbackToolValue: Codable, Equatable {
    var kind: FeedbackKind
    /// 박자: "마디×4+박"(0~15) → "rushing"(빨라요) / "dragging"(느려요)
    var beatMarks: [String: String]?
    /// 볼륨·밸런스: 이 믹스로 들어 보기 (트랙 id → 볼륨 0~1)
    var targetMix: [String: Float]?
    /// 하모니: 박마다 코드 4칸 (빈 칸은 "")
    var chords: [String]?
    /// 표현: 악보 기호 (ExprSymbol rawValue)
    var expression: String?
    /// 표현: 톤 (ToneStyle rawValue)
    var tones: [String]?
    var link: String?
    /// 입력값으로 만든 한 줄 요약 ("ko"/"en")
    var summaries: [String: String]

    var displaySummary: String { summaries[AppLanguage.current.rawValue] ?? summaries.values.first ?? "" }
}

/// 코멘트 하나. 쓴 사람은 "leader" 또는 세션 id("bass" 등).
struct FeedbackComment: Identifiable, Codable, Equatable {
    let id: UUID
    var author: String
    var text: String
    var createdAt: Date
    /// 다른 언어 번역 ("en"/"ko" → 문장). 샘플 데이터처럼 두 언어를 다 갖고 있을 때만 있다.
    var translations: [String: String]?
    /// 👍 좋아요 / 🤔 다르게 생각해요 로 남긴 답이면 그 입장 (그냥 글이면 nil).
    var stance: FeedbackStance?
    /// 글과 함께 보여 준 툴 (예: "이 믹스 어때?" + 페이더로 만든 믹스)
    var tool: FeedbackToolValue?

    init(id: UUID = UUID(), author: String, text: String, createdAt: Date = Date(),
         translations: [String: String]? = nil, stance: FeedbackStance? = nil, tool: FeedbackToolValue? = nil) {
        self.id = id
        self.author = author
        self.text = text
        self.createdAt = createdAt
        self.translations = translations
        self.stance = stance
        self.tool = tool
    }

    /// 지금 표시 언어에 맞는 문장 (번역이 없으면 쓴 그대로).
    var displayText: String { translations?[AppLanguage.current.rawValue] ?? text }
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

/// 대화에 남기는 입장. 반대(🤔)도 처음부터 버튼으로 둬서, 지시가 아니라 의견을 주고받는 느낌을 준다.
enum FeedbackStance: String, Codable {
    case agree
    case rethink

    var emoji: String { self == .agree ? "👍" : "🤔" }
    var label: String { self == .agree ? L("좋아요") : L("다르게 생각해요") }
}

/// 대화 끝에 "이렇게 하자"고 제안한 결론. 관련된 사람이 모두 동의하면 대화가 정리된다.
struct FeedbackConclusion: Identifiable, Codable, Equatable {
    let id: UUID
    /// 결론 한 줄 (예: "후렴 들어갈 때 킥을 한 박 늦게")
    var text: String
    /// 결론을 표현하는 툴 = 피드백 종류 (박자·볼륨 등). 타임라인에 이 종류의 이모지가 뜬다.
    var kind: FeedbackKind?
    /// "이 녹음처럼 하자" — 대화 중 올라온 녹음(시도) 하나. 결론이 나면 곡에 반영된다.
    var attemptId: UUID?
    /// 결론을 구체적으로 정한 툴 값 (예: 합의한 믹스). 정리되면 연습할 때 이 값을 쓴다.
    var tool: FeedbackToolValue?
    var proposer: String
    /// 동의한 사람들 (제안한 사람 포함)
    var agreedBy: [String]
    var createdAt: Date

    init(id: UUID = UUID(), text: String, kind: FeedbackKind?, attemptId: UUID?, tool: FeedbackToolValue? = nil,
         proposer: String, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.kind = tool?.kind ?? kind
        self.attemptId = attemptId
        self.tool = tool
        self.proposer = proposer
        self.agreedBy = [proposer]
        self.createdAt = createdAt
    }
}

/// 핀(피드백)의 대화 상태: 이야기 중(흰 점) → 결론 제안(동의 기다림) → 정리됨(결론 이모지).
enum FeedbackStatus: Equatable {
    case discussing
    case proposed
    case concluded

    var label: String {
        switch self {
        case .discussing: return L("이야기 중")
        case .proposed: return L("동의 기다리는 중")
        case .concluded: return L("이렇게 하기로 했어요")
        }
    }

    /// 여러 핀이 한 표시로 묶였을 때 어떤 상태를 대표로 보여줄지 (주목할 것 먼저).
    var displayPriority: Int {
        switch self {
        case .proposed: return 0
        case .discussing: return 1
        case .concluded: return 2
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
    /// 피드백을 준 사람 ("leader" 또는 세션 id). 코멘트 요청은 이 사람에게 가고, 통과·다시 열기도 이 사람이 한다.
    /// 예전 피드백(필드 없음)은 리더가 준 것으로 본다.
    var author: String = FeedbackPeople.leader
    /// 다른 언어 번역 ("en"/"ko" → 문장). 두 언어를 다 갖고 있을 때만 있다.
    var translations: [String: String]?
    /// 받는 세션 id(StemTrack.id: "bass" 등). 비어 있으면 전체 세션에게 보낸 피드백.
    var targetSessionIds: [String]
    /// 시도들 (오래된 순). 다시 연습해서 올릴 때마다 하나씩 늘어난다.
    var attempts: [FeedbackAttempt] = []
    /// 첫 시도 전에 오간 코멘트 (예: 피드백 내용 보충 설명).
    var comments: [FeedbackComment] = []
    /// 통과 처리된 시도. nil이면 아직 진행 중.
    var passedAttemptId: UUID?
    /// 피드백 종류 (예전 피드백·"그냥 말로"는 nil일 수 있음). 받는 사람의 연습 방법을 정한다.
    var kind: FeedbackKind?
    /// 밸런스 피드백: 리더가 맞춘 목표 믹스 (트랙 id → 볼륨 0~1)
    var targetMix: [String: Float]?
    /// 음·연주 피드백: 리더가 받는 세션 트랙 위에 녹음한 시범 (PatchStore의 Patch.id, isReference)
    var referencePatchId: UUID?
    /// 약속 피드백: 확인을 누른 사람들 (세션 id 또는 "leader"). 예전 데이터 읽기용.
    var confirmedBy: [String] = []
    /// 제안된 결론 (없으면 아직 이야기 중)
    var conclusion: FeedbackConclusion?

    /// 지금 표시 언어에 맞는 문장 (번역이 없으면 쓴 그대로).
    var displayText: String { translations?[AppLanguage.current.rawValue] ?? text }

    /// 핀 하나에 녹음으로 답하기는 최대 2번 (팀 규칙: 숙제처럼 끝없이 늘어나지 않게).
    static let maxRecordings = 2
    var remainingRecordings: Int { max(0, Self.maxRecordings - attempts.count) }
    var canAddRecording: Bool { remainingRecordings > 0 }

    /// 결론이 정한 종류가 있으면 그것, 없으면 처음 종류. 연습 방법과 타임라인 이모지를 정한다.
    var effectiveKind: FeedbackKind? { conclusion?.kind ?? kind }
    var plan: PracticePlan { (effectiveKind ?? .free).plan }
    /// 연습할 때 들을 믹스: 결론에 붙은 믹스, 없으면 예전 밸런스 피드백의 목표 믹스.
    var effectiveTargetMix: [String: Float]? { conclusion?.tool?.targetMix ?? targetMix }

    /// 이 대화에 관련된 사람 = 핀을 남긴 사람 + 핀이 꽂힌 파트.
    var participants: [String] {
        ([author] + targetSessionIds).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
    }

    /// 결론이 정리되려면 동의가 필요한 사람. 전체 대상 핀(예전 데이터)은 남긴 사람 + 다른 한 명.
    func hasEnoughAgreement(_ conclusion: FeedbackConclusion) -> Bool {
        if isForAllSessions {
            return conclusion.agreedBy.contains(author) && conclusion.agreedBy.contains { $0 != author }
        }
        return participants.allSatisfy { conclusion.agreedBy.contains($0) }
    }

    /// 아직 동의하지 않은 관련자
    var pendingAgreers: [String] {
        guard let conclusion, !isForAllSessions else { return [] }
        return participants.filter { !conclusion.agreedBy.contains($0) }
    }

    var status: FeedbackStatus {
        if let conclusion { return hasEnoughAgreement(conclusion) ? .concluded : .proposed }
        // 예전 방식으로 통과·확인된 피드백은 정리된 것으로 본다
        if passedAttemptId != nil || (kind == .cue && isConfirmed) { return .concluded }
        return .discussing
    }

    /// 마지막으로 말한 사람 (코멘트·녹음 중 가장 최근, 없으면 핀을 남긴 사람)
    var lastSpeaker: String {
        let comments = self.comments + attempts.flatMap(\.comments)
        let events = comments.map { ($0.createdAt, $0.author) } + attempts.map { ($0.createdAt, $0.sessionId) }
        return events.max { $0.0 < $1.0 }?.1 ?? author
    }

    /// 이 사람이 지금 봐야 하는 핀인지: 내 동의를 기다리는 결론, 또는 내가 관련된 대화에 다른 사람이 말한 뒤.
    func needsAttention(from person: String) -> Bool {
        switch status {
        case .proposed: return pendingAgreers.contains(person)
        case .discussing: return participants.contains(person) && lastSpeaker != person
        case .concluded: return false
        }
    }

    var timeRange: ClosedRange<TimeInterval> {
        startTime...endTime
    }

    var isForAllSessions: Bool { targetSessionIds.isEmpty }

    /// 약속 피드백: 받는 세션이 모두 확인했는지 (전체 대상이면 세션 한 명이라도).
    var isConfirmed: Bool {
        if isForAllSessions { return confirmedBy.contains { $0 != FeedbackPeople.leader } }
        return targetSessionIds.allSatisfy { confirmedBy.contains($0) }
    }

    func isFor(sessionId: String) -> Bool {
        isForAllSessions || targetSessionIds.contains(sessionId)
    }

    /// "N차 시도"의 N (1부터).
    func attemptNumber(of attemptId: UUID) -> Int? {
        attempts.firstIndex { $0.id == attemptId }.map { $0 + 1 }
    }

    init(id: UUID = UUID(), timeRange: ClosedRange<TimeInterval>, text: String, targetSessionIds: [String],
         kind: FeedbackKind? = nil, targetMix: [String: Float]? = nil, referencePatchId: UUID? = nil,
         createdAt: Date = Date()) {
        self.id = id
        self.startTime = timeRange.lowerBound
        self.endTime = timeRange.upperBound
        self.createdAt = createdAt
        self.text = text
        self.targetSessionIds = targetSessionIds
        self.kind = kind
        self.targetMix = targetMix
        self.referencePatchId = referencePatchId
    }

    private enum CodingKeys: String, CodingKey {
        case id, startTime, endTime, createdAt, text, author, translations, targetSessionIds, attempts, comments, passedAttemptId
        case kind, targetMix, referencePatchId, confirmedBy, conclusion
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
        translations = try c.decodeIfPresent([String: String].self, forKey: .translations)
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? FeedbackPeople.leader
        targetSessionIds = try c.decodeIfPresent([String].self, forKey: .targetSessionIds) ?? []
        attempts = try c.decodeIfPresent([FeedbackAttempt].self, forKey: .attempts) ?? []
        comments = try c.decodeIfPresent([FeedbackComment].self, forKey: .comments) ?? []
        passedAttemptId = try c.decodeIfPresent(UUID.self, forKey: .passedAttemptId)
        // 모르는 종류(새 버전 앱이 만든 것)는 nil로 읽는다
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)).flatMap { $0.flatMap(FeedbackKind.init(rawValue:)) }
        targetMix = try c.decodeIfPresent([String: Float].self, forKey: .targetMix)
        referencePatchId = try c.decodeIfPresent(UUID.self, forKey: .referencePatchId)
        confirmedBy = try c.decodeIfPresent([String].self, forKey: .confirmedBy) ?? []
        conclusion = try? c.decodeIfPresent(FeedbackConclusion.self, forKey: .conclusion)

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
        try c.encode(author, forKey: .author)
        try c.encodeIfPresent(translations, forKey: .translations)
        try c.encode(targetSessionIds, forKey: .targetSessionIds)
        try c.encode(attempts, forKey: .attempts)
        try c.encode(comments, forKey: .comments)
        try c.encodeIfPresent(passedAttemptId, forKey: .passedAttemptId)
        try c.encodeIfPresent(kind, forKey: .kind)
        try c.encodeIfPresent(targetMix, forKey: .targetMix)
        try c.encodeIfPresent(referencePatchId, forKey: .referencePatchId)
        try c.encode(confirmedBy, forKey: .confirmedBy)
        try c.encodeIfPresent(conclusion, forKey: .conclusion)
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

/// 피드백 저장소. 로컬 파일에 저장하고, 바뀐 내용은 SyncClient로 서버에 보낸다.
/// 다른 기기에서 바뀐 내용은 SyncClient가 replaceAll로 통째로 넣어 준다.
@MainActor
final class FeedbackStore: ObservableObject {
    private var sync: SyncClient { .shared }

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

    /// 서버에서 받은 최신 상태로 교체 (다른 기기의 변경 반영).
    func replaceAll(_ newItems: [FeedbackItem]) {
        let sorted = newItems.sorted { $0.startTime < $1.startTime }
        guard sorted != items else { return }
        items = sorted
        persist()
    }

    private func update(_ feedbackId: UUID, _ change: (inout FeedbackItem) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == feedbackId }) else { return }
        change(&items[i])
        persist()
    }

    @discardableResult
    func addFeedback(timeRange: ClosedRange<TimeInterval>, text: String, targetSessionIds: [String],
                     kind: FeedbackKind? = nil, targetMix: [String: Float]? = nil,
                     referencePatchId: UUID? = nil, translations: [String: String]? = nil,
                     author: String = FeedbackPeople.leader) -> FeedbackItem {
        var item = FeedbackItem(timeRange: timeRange, text: text, targetSessionIds: targetSessionIds,
                                kind: kind, targetMix: targetMix, referencePatchId: referencePatchId)
        item.translations = translations
        item.author = author
        items.append(item)
        items.sort { $0.startTime < $1.startTime }
        persist()
        sync.send("feedback.add", ["item": SyncClient.json(item)])
        return item
    }

    func delete(_ item: FeedbackItem) {
        items.removeAll { $0.id == item.id }
        persist()
        sync.send("feedback.delete", ["id": item.id.uuidString])
    }

    func item(id: UUID) -> FeedbackItem? {
        items.first { $0.id == id }
    }

    /// 녹음으로 답한다 (대화에 녹음 하나가 추가됨).
    func addAttempt(patch: Patch, to feedbackId: UUID) {
        guard item(id: feedbackId)?.canAddRecording ?? false else { return }
        let attempt = FeedbackAttempt(sessionId: patch.sessionId, patchId: patch.id)
        update(feedbackId) {
            $0.attempts.append(attempt)
            $0.passedAttemptId = nil
        }
        sync.send("attempt.add", ["feedbackId": feedbackId.uuidString, "attempt": SyncClient.json(attempt)])
    }

    func deleteAttempt(_ attemptId: UUID, from feedbackId: UUID) {
        update(feedbackId) {
            $0.attempts.removeAll { $0.id == attemptId }
            if $0.passedAttemptId == attemptId { $0.passedAttemptId = nil }
        }
        sync.send("attempt.delete", ["feedbackId": feedbackId.uuidString, "attemptId": attemptId.uuidString])
    }

    /// 대화에 글이나 👍/🤔를 남긴다. attemptId가 있으면 그 녹음에 단 말(예전 형식 호환).
    func addComment(_ text: String, author: String, to feedbackId: UUID, attemptId: UUID? = nil,
                    stance: FeedbackStance? = nil, tool: FeedbackToolValue? = nil) {
        let comment = FeedbackComment(author: author, text: text, stance: stance, tool: tool)
        update(feedbackId) { item in
            if let attemptId, let i = item.attempts.firstIndex(where: { $0.id == attemptId }) {
                item.attempts[i].comments.append(comment)
            } else {
                item.comments.append(comment)
            }
        }
        sync.send("comment.add", [
            "feedbackId": feedbackId.uuidString,
            "attemptId": attemptId?.uuidString ?? NSNull(),
            "comment": SyncClient.json(comment),
        ])
    }

    func deleteComment(_ commentId: UUID, from feedbackId: UUID) {
        update(feedbackId) { item in
            item.comments.removeAll { $0.id == commentId }
            for i in item.attempts.indices {
                item.attempts[i].comments.removeAll { $0.id == commentId }
            }
        }
        sync.send("comment.delete", ["feedbackId": feedbackId.uuidString, "commentId": commentId.uuidString])
    }

    // MARK: 결론

    /// 결론을 제안한다 (제안한 사람은 바로 동의한 것으로). 이미 제안이 있으면 새 제안으로 바뀌고 동의는 처음부터.
    @discardableResult
    func proposeConclusion(text: String, kind: FeedbackKind?, attemptId: UUID?, tool: FeedbackToolValue? = nil,
                           by person: String, to feedbackId: UUID) -> FeedbackConclusion {
        let conclusion = FeedbackConclusion(text: text, kind: kind, attemptId: attemptId, tool: tool, proposer: person)
        update(feedbackId) { $0.conclusion = conclusion }
        sync.send("conclusion.propose", ["feedbackId": feedbackId.uuidString, "conclusion": SyncClient.json(conclusion)])
        return conclusion
    }

    /// 제안된 결론에 동의한다.
    func agree(to conclusionId: UUID, by person: String, on feedbackId: UUID) {
        update(feedbackId) { item in
            guard item.conclusion?.id == conclusionId, item.conclusion?.agreedBy.contains(person) == false else { return }
            item.conclusion?.agreedBy.append(person)
        }
        sync.send("conclusion.agree", ["feedbackId": feedbackId.uuidString, "conclusionId": conclusionId.uuidString, "by": person])
    }

    /// 결론을 거두고 다시 이야기한다 (예전 방식의 통과 표시도 지운다).
    func clearConclusion(of feedbackId: UUID) {
        update(feedbackId) {
            $0.conclusion = nil
            $0.passedAttemptId = nil
        }
        sync.send("conclusion.clear", ["feedbackId": feedbackId.uuidString])
    }
}
