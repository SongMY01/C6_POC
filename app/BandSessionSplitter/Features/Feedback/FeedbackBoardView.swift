import SwiftUI

/// 파형(타임라인) 없이 핀(대화)만 모아 보는 화면.
/// 파트·대화 상태로 걸러 보고, 누르면 그 핀의 대화 화면을 연다.
struct FeedbackBoardView: View {
    let items: [FeedbackItem]
    let tracks: [StemTrack]
    /// 지금 재생 위치 — 이 위치에 걸친 피드백을 강조한다.
    let currentTime: TimeInterval
    /// 배지가 있을 때(봐야 할 핀이 있을 때) "내 차례"만 걸러서 시작
    var startWithMine = false
    let onOpen: (FeedbackItem) -> Void
    let onCompose: (() -> Void)?

    /// nil = 전체 세션. 세션 연주자의 iPad에서는 처음에 "내 세션"으로 걸러서 보여준다.
    @State private var sessionFilter: String? = DeviceRole.isLeader ? nil : DeviceRole.current
    /// nil = 전체 상태
    @State private var statusFilter: FeedbackStatus?
    /// 내 동의를 기다리거나 내 답을 기다리는 핀만
    @State private var mineOnly = false

    private func isMine(_ item: FeedbackItem) -> Bool { !mineOnly || item.needsAttention(from: DeviceRole.current) }

    private var filtered: [FeedbackItem] {
        items
            .filter { item in sessionFilter.map { item.isFor(sessionId: $0) } ?? true }
            .filter { item in statusFilter.map { item.status == $0 } ?? true }
            .filter(isMine)
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
        .onAppear { mineOnly = startWithMine }
    }

    // MARK: 필터

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(L("👥 전체 세션"), isOn: sessionFilter == nil) { sessionFilter = nil }
                    ForEach(tracks) { track in
                        chip("\(track.instrumentEmoji) \(track.displayName)", isOn: sessionFilter == track.id) {
                            sessionFilter = track.id
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                let mineCount = items.filter { $0.needsAttention(from: DeviceRole.current) }.count
                chip(L("👀 내 차례 \(mineCount)"), isOn: mineOnly, tint: .cyan) { mineOnly.toggle() }
                chip(L("전체 \(count(nil))"), isOn: statusFilter == nil) { statusFilter = nil }
                ForEach([FeedbackStatus.discussing, .proposed, .concluded], id: \.label) { status in
                    chip("\(status.label) \(count(status))", isOn: statusFilter == status, tint: status.color) {
                        statusFilter = status
                    }
                }
                Spacer()
                if let onCompose {
                    Button(action: onCompose) {
                        Label(L("새 핀"), systemImage: "mappin.and.ellipse")
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
        let latestComment = (item.comments + item.attempts.flatMap(\.comments)).max { $0.createdAt < $1.createdAt }
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
                    FeedbackPinDot(item: item, size: 20)
                    Text(recipientsLabel(item))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                    FeedbackStatusBadge(item: item)
                    if !item.comments.isEmpty || !item.attempts.isEmpty {
                        Text(L("답 \(item.comments.count + item.attempts.count)개"))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                    Text(item.createdAt, format: .dateTime.month().day())
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                }
                Text(item.text.isEmpty ? L("(내용 없음)") : item.displayText)
                    .font(.body)
                    .foregroundStyle(.white.opacity(item.text.isEmpty ? 0.5 : 0.95))
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                if let conclusion = item.conclusion {
                    Text("\((conclusion.kind ?? .free).emoji) \(conclusion.text)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(item.status == .concluded ? Color.green : GB.cycle)
                        .lineLimit(1)
                } else if let latestComment {
                    HStack(spacing: 6) {
                        Text(latestComment.stance?.emoji ?? "💬")
                        Text("\(FeedbackPeople.name(of: latestComment.author, tracks: tracks)): \(latestComment.displayText)")
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
        .opacity(item.status == .concluded && statusFilter != .concluded ? 0.6 : 1)
    }

    private func recipientsLabel(_ item: FeedbackItem) -> String {
        if item.isForAllSessions { return L("👥 전체") }
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
            Text(items.isEmpty ? L("아직 핀이 없습니다") : L("조건에 맞는 핀이 없습니다"))
                .font(.headline)
                .foregroundStyle(.white.opacity(0.7))
            if items.isEmpty {
                Text(L("트랙 줄을 길게 눌러 끌면 그 구간에 핀을 남기고 이야기를 시작할 수 있어요."))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
