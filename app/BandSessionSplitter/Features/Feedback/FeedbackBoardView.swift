import SwiftUI

/// 파형(타임라인) 없이 피드백만 모아 보는 화면.
/// 받는 세션·진행 상태로 걸러 보고, 누르면 그 피드백 화면(시도·코멘트·비교 듣기)을 연다.
struct FeedbackBoardView: View {
    let items: [FeedbackItem]
    let tracks: [StemTrack]
    /// 지금 재생 위치 — 이 위치에 걸친 피드백을 강조한다.
    let currentTime: TimeInterval
    let onOpen: (FeedbackItem) -> Void
    let onCompose: (() -> Void)?

    /// nil = 전체 세션. 세션 연주자의 iPad에서는 처음에 "내 세션"으로 걸러서 보여준다.
    @State private var sessionFilter: String? = DeviceRole.isLeader ? nil : DeviceRole.current
    /// nil = 전체 상태
    @State private var statusFilter: FeedbackStatus?

    private var filtered: [FeedbackItem] {
        items
            .filter { item in sessionFilter.map { item.isFor(sessionId: $0) } ?? true }
            .filter { item in statusFilter.map { item.status == $0 } ?? true }
            .sorted { $0.startTime < $1.startTime }
    }

    private func count(_ status: FeedbackStatus?) -> Int {
        items
            .filter { item in sessionFilter.map { item.isFor(sessionId: $0) } ?? true }
            .filter { item in status.map { item.status == $0 } ?? true }
            .count
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider().overlay(Color.black)
            if filtered.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filtered) { item in
                            Button { onOpen(item) } label: { row(item) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: 900)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(GB.background)
    }

    // MARK: 필터

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("👥 전체 세션", isOn: sessionFilter == nil) { sessionFilter = nil }
                    ForEach(tracks) { track in
                        chip("\(track.instrumentEmoji) \(track.displayName)", isOn: sessionFilter == track.id) {
                            sessionFilter = track.id
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                chip("전체 \(count(nil))", isOn: statusFilter == nil) { statusFilter = nil }
                ForEach([FeedbackStatus.awaitingComment, .needsPractice, .passed], id: \.label) { status in
                    chip("\(status.label) \(count(status))", isOn: statusFilter == status, tint: status.color) {
                        statusFilter = status
                    }
                }
                Spacer()
                if let onCompose {
                    Button(action: onCompose) {
                        Label("새 피드백", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(GBToolButtonStyle())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(GB.toolbar)
    }

    private func chip(_ title: String, isOn: Bool, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isOn ? Color.black : tint.opacity(0.9))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(isOn ? tint.opacity(tint == .white ? 0.9 : 0.85) : GB.panel))
        }
        .buttonStyle(.plain)
    }

    // MARK: 목록

    private func row(_ item: FeedbackItem) -> some View {
        let isNow = item.timeRange.contains(currentTime)
        let latestComment = (item.attempts.last?.comments.last) ?? item.comments.last
        return HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(formatTime(item.startTime))
                    .font(.title3.monospacedDigit().weight(.bold))
                Text("~\(formatTime(item.endTime))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
            }
            .frame(width: 64, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(recipientsLabel(item))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                    FeedbackStatusBadge(status: item.status)
                    if !item.attempts.isEmpty {
                        Text("시도 \(item.attempts.count)회")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                    Text(item.createdAt, format: .dateTime.month().day())
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                }
                Text(item.text.isEmpty ? "(내용 없음)" : item.text)
                    .font(.body)
                    .foregroundStyle(.white.opacity(item.text.isEmpty ? 0.5 : 0.95))
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                if let latestComment {
                    HStack(spacing: 6) {
                        Image(systemName: "text.bubble")
                        Text("\(FeedbackPeople.name(of: latestComment.author, tracks: tracks)): \(latestComment.text)")
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                }
            }
            Image(systemName: "chevron.right")
                .foregroundStyle(.white.opacity(0.35))
                .padding(.top, 4)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(GB.toolbar))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isNow ? GB.cycle : item.status.color.opacity(0.35), lineWidth: isNow ? 2 : 1)
        )
        .opacity(item.status == .passed && statusFilter != .passed ? 0.6 : 1)
    }

    private func recipientsLabel(_ item: FeedbackItem) -> String {
        if item.isForAllSessions { return "👥 전체" }
        return item.targetSessionIds.map { id in
            let track = tracks.first { $0.id == id }
            return "\(track?.instrumentEmoji ?? "") \(track?.displayName ?? id)"
        }.joined(separator: ", ")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.bubble")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.35))
            Text(items.isEmpty ? "아직 피드백이 없습니다" : "조건에 맞는 피드백이 없습니다")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.7))
            if items.isEmpty {
                Text("타임라인에서 구간을 잡고 새 피드백을 남겨 보세요.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
