import Foundation

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

    func item(id: UUID) -> FeedbackItem? {
        items.first { $0.id == id }
    }
}
