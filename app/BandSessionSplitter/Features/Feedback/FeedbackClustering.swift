import Foundation

/// 화면에서 너무 가까이 붙은 피드백들을 한 묶음으로 합친다.
///
/// 피드백 구간이 겹치거나 몇 초 차이로 붙어 있으면 깃발·말풍선이 서로 덮여서 탭할 수 없다.
/// 그래서 "화면상 거리(초 × 줌 배율)"가 minSpacing보다 가까우면 한 묶음으로 보여주고
/// ("💬 3"), 탭하면 목록에서 고르게 한다. 확대하면 거리가 벌어져 저절로 다시 풀린다.
struct FeedbackCluster: Identifiable {
    var items: [FeedbackItem]
    /// 트랙 레인에서 몇 번째 줄에 놓이는지 (겹치는 말풍선은 아래 줄로 쌓는다)
    var row = 0
    var id: UUID { items[0].id }
    var start: TimeInterval { items[0].startTime }
    var isSingle: Bool { items.count == 1 }
    /// 묶음 대표 상태: 코멘트 요청 > 연습 필요 > 통과 (주목할 것 먼저).
    var status: FeedbackStatus { items.map(\.status).min { $0.displayPriority < $1.displayPriority } ?? .needsPractice }

    static func make(_ items: [FeedbackItem], pxPerSec: CGFloat, minSpacing: CGFloat) -> [FeedbackCluster] {
        var clusters: [[FeedbackItem]] = []
        for item in items.sorted(by: { $0.startTime < $1.startTime }) {
            if let first = clusters.last?.first,
               CGFloat(item.startTime - first.startTime) * pxPerSec < minSpacing {
                clusters[clusters.count - 1].append(item)
            } else {
                clusters.append([item])
            }
        }
        return clusters.map { FeedbackCluster(items: $0) }
    }

    /// 트랙 레인용: 말풍선이 겹치면 묶지 않고 아래 줄로 쌓아서 하나씩 보이게 한다.
    /// 줄이 maxRows개를 넘을 때만 마지막 줄의 말풍선에 묶는다 ("피드백 N개").
    static func stacked(_ items: [FeedbackItem], pxPerSec: CGFloat, markerWidth: CGFloat, maxRows: Int) -> [FeedbackCluster] {
        var placed: [FeedbackCluster] = []
        var rowEnds: [CGFloat] = Array(repeating: -.infinity, count: maxRows)
        var lastInRow: [Int?] = Array(repeating: nil, count: maxRows)
        for item in items.sorted(by: { $0.startTime < $1.startTime }) {
            let x = CGFloat(item.startTime) * pxPerSec
            if let row = rowEnds.firstIndex(where: { $0 <= x }) {
                placed.append(FeedbackCluster(items: [item], row: row))
                rowEnds[row] = x + markerWidth + 4
                lastInRow[row] = placed.count - 1
            } else if let index = lastInRow[maxRows - 1] {
                placed[index].items.append(item)
            }
        }
        return placed
    }
}
