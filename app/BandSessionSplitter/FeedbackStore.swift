import Foundation
import PencilKit

/// 피드백 하나 = "이 구간(시작~끝)에 대해 이런 메모를 남겼다".
///
/// 손글씨 POC(페이지당 캔버스 하나)와 달리, 여기서는 피드백 단위로 쪼개서
/// 각각 자기 시간 구간(timeRange)을 갖는다 — 그래야 피드백을 탭했을 때
/// "그 구간을 자동으로 구간반복 설정"할 수 있다.
struct FeedbackItem: Identifiable, Codable, Equatable {
    let id: UUID
    var page: Int
    var startTime: TimeInterval
    var endTime: TimeInterval
    var createdAt: Date

    var timeRange: ClosedRange<TimeInterval> {
        startTime...endTime
    }
}

@MainActor
final class FeedbackStore: ObservableObject {
    @Published private(set) var items: [FeedbackItem] = []

    private let baseDir: URL
    private let manifestURL: URL

    init(songTitle: String = "항해") {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("annotations", isDirectory: true)
            .appendingPathComponent(songTitle, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.baseDir = dir
        self.manifestURL = dir.appendingPathComponent("feedback_manifest.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONDecoder().decode([FeedbackItem].self, from: data) else { return }
        items = decoded.sorted { $0.startTime < $1.startTime }
    }

    private func persistManifest() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: manifestURL)
    }

    private func drawingURL(for id: UUID) -> URL {
        baseDir.appendingPathComponent("feedback_\(id.uuidString).drawing")
    }

    func loadDrawing(for item: FeedbackItem) -> PKDrawing {
        guard let data = try? Data(contentsOf: drawingURL(for: item.id)) else { return PKDrawing() }
        return (try? PKDrawing(data: data)) ?? PKDrawing()
    }

    @discardableResult
    func addFeedback(page: Int, timeRange: ClosedRange<TimeInterval>, drawing: PKDrawing) -> FeedbackItem {
        let item = FeedbackItem(
            id: UUID(),
            page: page,
            startTime: timeRange.lowerBound,
            endTime: timeRange.upperBound,
            createdAt: Date()
        )
        try? drawing.dataRepresentation().write(to: drawingURL(for: item.id))
        items.append(item)
        items.sort { $0.startTime < $1.startTime }
        persistManifest()
        return item
    }

    func delete(_ item: FeedbackItem) {
        try? FileManager.default.removeItem(at: drawingURL(for: item.id))
        items.removeAll { $0.id == item.id }
        persistManifest()
    }

    func items(onPage page: Int) -> [FeedbackItem] {
        items.filter { $0.page == page }
    }
}
