import SwiftUI

/// 오늘의 구간 뽑기: "뭐부터 하지?"를 없애기 위해 해볼 만한 피드백 하나를 골라 준다.
enum DailyPick {
    /// 뽑을 수 있는 피드백: 이 기기 사람이 해볼 차례인 것 (세션 연주자는 내 세션 대상만, 리더는 전부).
    static func candidates(from items: [FeedbackItem]) -> [FeedbackItem] {
        let role = DeviceRole.current
        return items
            .filter { $0.status == .needsPractice && (DeviceRole.isLeader || $0.isFor(sessionId: role)) }
            .sorted { $0.startTime < $1.startTime }
    }

    /// 같은 날·같은 역할이면 같은 카드가 나온다 ("오늘의" 구간). reroll이 늘면 다음 카드.
    static func pick(from candidates: [FeedbackItem], reroll: Int) -> FeedbackItem? {
        guard !candidates.isEmpty else { return nil }
        let day = Int(Date().timeIntervalSince1970 / 86_400)
        let roleSeed = DeviceRole.current.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return candidates[abs(day &* 31 &+ roleSeed &+ reroll) % candidates.count]
    }

    enum Difficulty {
        case easy, medium, hard

        var label: String {
            switch self {
            case .easy: return "쉬움"
            case .medium: return "보통"
            case .hard: return "어려움"
            }
        }

        var color: Color {
            switch self {
            case .easy: return .green
            case .medium: return .orange
            case .hard: return .red
            }
        }
    }

    /// 구간이 짧을수록 쉽게 해볼 수 있다.
    static func difficulty(of item: FeedbackItem) -> Difficulty {
        switch item.endTime - item.startTime {
        case ..<6.5: return .easy
        case ..<12.5: return .medium
        default: return .hard
        }
    }
}

/// 오늘의 구간 카드. "바로 해보기"를 누르면 카운트인으로 시작한다.
struct DailyPickSheet: View {
    let items: [FeedbackItem]
    let tracks: [StemTrack]
    let useLadder: Bool
    let onStart: (FeedbackItem) -> Void
    let onClose: () -> Void

    @State private var reroll = 0

    private var candidates: [FeedbackItem] { DailyPick.candidates(from: items) }
    private var picked: FeedbackItem? { DailyPick.pick(from: candidates, reroll: reroll) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let item = picked {
                    card(item)
                    Button {
                        onStart(item)
                    } label: {
                        Text("바로 해보기")
                            .font(.title3.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    HStack(spacing: 12) {
                        if candidates.count > 1 {
                            Button {
                                reroll += 1
                                SyncClient.shared.log("daily_pick_reroll")
                            } label: { Label("다른 걸로 뽑기", systemImage: "dice") }
                                .buttonStyle(.bordered)
                        }
                        Button("나중에", action: onClose).buttonStyle(.bordered)
                    }
                } else {
                    Spacer()
                    Text("🎉").font(.system(size: 64))
                    Text("오늘은 해볼 구간이 없어요").font(.title3.weight(.semibold))
                    Text("새 피드백이 오면 여기서 하나 뽑아 드릴게요.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("닫기", action: onClose).buttonStyle(.bordered)
                    Spacer()
                }
            }
            .padding(24)
            .navigationTitle("🎲 오늘의 한 구간")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("닫기", action: onClose) }
            }
        }
        .onAppear { SyncClient.shared.log("daily_pick_open", ["candidates": candidates.count]) }
    }

    private func card(_ item: FeedbackItem) -> some View {
        let difficulty = DailyPick.difficulty(of: item)
        let seconds = PracticeSession.estimatedSeconds(regionLength: item.endTime - item.startTime, ladder: useLadder)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(formatTime(item.startTime)) ~ \(formatTime(item.endTime))")
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                Spacer()
                Text("→ \(FeedbackPeople.recipients(of: item, tracks: tracks))")
                    .font(.headline).foregroundStyle(.secondary)
            }
            Text(item.text.isEmpty ? "(내용 없음)" : item.text)
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                pill(difficulty.label, color: difficulty.color)
                pill("약 \(seconds)초", color: .blue)
                if useLadder { pill("느린 속도부터", color: .purple) }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }
}
