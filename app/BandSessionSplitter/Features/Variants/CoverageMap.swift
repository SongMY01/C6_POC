import SwiftUI

/// 정복 지도: 곡 전체를 칸으로 나눠 놓고, 피드백이 걸린 구간을 하나씩 "정복"해 가며 색을 채운다.
///
/// - 피드백이 없는 칸은 평평한 회색, 피드백이 걸린 칸은 아직 안 한 곳 (안개 낀 테두리)
/// - 녹음을 올려 기다리는 중이면 반쯤 채워지고, 마무리하면 세션 색으로 가득 찬다
/// - 내 몫만 센다: 세션 연주자는 내 세션이 받은 피드백, 리더는 전체
enum CoverageMap {
    enum CellState: Equatable {
        case empty      // 이 칸엔 피드백 없음
        case todo       // 해볼 구간
        case started    // 녹음을 올렸거나 답장 기다리는 중
        case done       // 정복
    }

    struct Cell: Identifiable {
        let index: Int
        let start: TimeInterval
        let end: TimeInterval
        let state: CellState
        /// 이 칸에 걸친 피드백 (시간 순)
        let items: [FeedbackItem]
        var id: Int { index }
    }

    /// 지도에 쓸 피드백: 이 기기 사람의 몫.
    static func relevantItems(_ items: [FeedbackItem]) -> [FeedbackItem] {
        DeviceRole.isLeader ? items : items.filter { $0.isFor(sessionId: DeviceRole.current) }
    }

    static func state(of item: FeedbackItem) -> CellState {
        switch item.status {
        case .passed: return .done
        case .awaitingComment: return .started
        case .needsPractice: return item.attempts.isEmpty ? .todo : .started
        }
    }

    static func cells(items: [FeedbackItem], duration: TimeInterval, count: Int = 60) -> [Cell] {
        guard duration > 0, count > 0 else { return [] }
        let width = duration / Double(count)
        return (0..<count).map { index in
            let start = Double(index) * width
            let end = start + width
            let overlapping = items.filter { $0.startTime < end && $0.endTime > start }
            let states = overlapping.map(state(of:))
            // 안 끝난 게 하나라도 있으면 그 칸은 아직 진행 중
            let cellState: CellState
            if overlapping.isEmpty { cellState = .empty }
            else if states.contains(.todo) { cellState = .todo }
            else if states.contains(.started) { cellState = .started }
            else { cellState = .done }
            return Cell(index: index, start: start, end: end, state: cellState, items: overlapping)
        }
    }

    static func progress(of items: [FeedbackItem]) -> (done: Int, total: Int) {
        (items.filter { $0.status == .passed }.count, items.count)
    }
}

/// 위쪽에 곡 전체 폭으로 보이는 정복 지도 띠.
struct CoverageMapBar: View {
    let items: [FeedbackItem]
    let tracks: [StemTrack]
    let duration: TimeInterval
    let currentTime: TimeInterval
    /// 방금 정복한 피드백 (칸이 반짝인다)
    let highlightId: UUID?
    let onTap: (FeedbackItem) -> Void

    private var mine: [FeedbackItem] { CoverageMap.relevantItems(items) }

    var body: some View {
        let progress = CoverageMap.progress(of: mine)
        let cells = CoverageMap.cells(items: mine, duration: duration)
        return VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text("🗺 정복 지도")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                Text("\(progress.done)/\(progress.total) 구간")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(progress.done == progress.total && progress.total > 0 ? Color.green : .white.opacity(0.75))
                if progress.total > 0 && progress.done == progress.total {
                    Text("모두 정복! 🎉").font(.system(size: 13, weight: .bold)).foregroundStyle(.green)
                }
                Spacer()
                legend
            }
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 2) {
                        ForEach(cells) { cell in
                            cellView(cell)
                                .contentShape(Rectangle())
                                .onTapGesture { tap(cell) }
                        }
                    }
                    // 재생 위치
                    if duration > 0 {
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 2, height: geo.size.height + 4)
                            .offset(x: geo.size.width * CGFloat(currentTime / duration) - 1, y: -2)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(height: 26)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(white: 0.14))
    }

    private var legend: some View {
        HStack(spacing: 10) {
            legendDot(Color.clear, stroke: Color.orange.opacity(0.8), "해볼 곳")
            legendDot(Color.cyan.opacity(0.45), stroke: nil, "진행 중")
            legendDot(Color.green.opacity(0.85), stroke: nil, "정복")
        }
    }

    private func legendDot(_ fill: Color, stroke: Color?, _ text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(fill).frame(width: 10, height: 10)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(stroke ?? .clear, lineWidth: 1.5))
            Text(text).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
        }
    }

    private func color(for cell: CoverageMap.Cell) -> Color {
        // 칸을 채울 색: 그 칸 피드백의 첫 번째 받는 세션 색 (전체 대상이면 노란색)
        guard let item = cell.items.first, let id = item.targetSessionIds.first,
              let track = tracks.first(where: { $0.id == id }) else { return GB.cycle }
        return track.tint
    }

    @ViewBuilder
    private func cellView(_ cell: CoverageMap.Cell) -> some View {
        let isHighlighted = highlightId.map { id in cell.items.contains { $0.id == id } } ?? false
        RoundedRectangle(cornerRadius: 3)
            .fill(fill(for: cell))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(stroke(for: cell, highlighted: isHighlighted), lineWidth: isHighlighted ? 2.5 : 1.5)
            )
            .scaleEffect(isHighlighted ? 1.12 : 1)
            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isHighlighted)
    }

    private func fill(for cell: CoverageMap.Cell) -> Color {
        switch cell.state {
        case .empty: return Color.white.opacity(0.08)
        case .todo: return Color.clear
        case .started: return color(for: cell).opacity(0.45)
        case .done: return color(for: cell)
        }
    }

    private func stroke(for cell: CoverageMap.Cell, highlighted: Bool) -> Color {
        if highlighted { return .white }
        switch cell.state {
        case .empty: return .clear
        case .todo: return Color.orange.opacity(0.8)
        case .started: return color(for: cell).opacity(0.9)
        case .done: return .clear
        }
    }

    private func tap(_ cell: CoverageMap.Cell) {
        // 안 끝난 피드백을 먼저, 없으면 첫 번째
        let target = cell.items.first(where: { $0.status != .passed }) ?? cell.items.first
        guard let target else { return }
        SyncClient.shared.log("map_cell_tap", ["status": target.status.label])
        onTap(target)
    }
}
