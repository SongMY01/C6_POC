import SwiftUI

// 핀(피드백) 표시에 쓰는 작은 공용 부품: 핀 점, 상태 배지, 사람 이름.

/// 핀 표시: 이야기 중 = 흰 점, 결론 제안 = 노란 점, 정리됨 = 결론 종류 이모지.
struct FeedbackPinDot: View {
    let item: FeedbackItem
    var size: CGFloat = 16

    var body: some View {
        switch item.status {
        case .discussing:
            Circle().fill(Color.white)
                .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1))
                .frame(width: size * 0.7, height: size * 0.7)
                .frame(width: size, height: size)
        case .proposed:
            Circle().fill(GB.cycle)
                .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                .frame(width: size * 0.7, height: size * 0.7)
                .frame(width: size, height: size)
        case .concluded:
            Text((item.effectiveKind ?? .free).emoji)
                .font(.system(size: size * 0.8))
                .frame(width: size, height: size)
        }
    }
}

/// 상태 배지: 이야기 중(회색) / 동의 기다리는 중(노랑) / 이렇게 하기로 했어요(초록).
struct FeedbackStatusBadge: View {
    let status: FeedbackStatus
    var label: String?

    init(status: FeedbackStatus, label: String? = nil) {
        self.status = status
        self.label = label
    }

    init(item: FeedbackItem) {
        self.init(status: item.status)
    }

    var body: some View {
        Text(label ?? status.label)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(status.color.opacity(0.2)))
            .foregroundStyle(status.color)
    }
}

extension FeedbackStatus {
    var color: Color {
        switch self {
        case .discussing: return .gray
        case .proposed: return .orange
        case .concluded: return .green
        }
    }

    /// 어두운 타임라인 위 표시용 색.
    var timelineColor: Color {
        switch self {
        case .discussing: return Color.white.opacity(0.9)
        case .proposed: return GB.cycle
        case .concluded: return Color.green.opacity(0.7)
        }
    }
}

/// 피드백에 등장하는 사람 표기: "leader" 또는 세션 id → 화면 이름.
enum FeedbackPeople {
    static let leader = "leader"

    static func name(of id: String, tracks: [StemTrack]) -> String {
        if id == leader { return L("리더") }
        return tracks.first { $0.id == id }?.displayName ?? id
    }

    /// "전체" 또는 "베이스, 드럼".
    static func recipients(of item: FeedbackItem, tracks: [StemTrack]) -> String {
        if item.isForAllSessions { return L("전체") }
        return item.targetSessionIds.map { name(of: $0, tracks: tracks) }.joined(separator: ", ")
    }
}
