import SwiftUI

/// 버전 B의 위쪽 띠: 다음 합주까지 팀이 같이 채우는 링, 지금 연습 중인 동료, 칭호 주기.
struct TeamBar: View {
    @ObservedObject private var sync = SyncClient.shared
    @ObservedObject private var variants = VariantStore.shared
    let feedback: [FeedbackItem]
    let tracks: [StemTrack]
    let onTitles: () -> Void

    /// 연습할 몫이 있는 사람들 = 피드백을 직접 받은 세션 (전체 대상 피드백은 세지 않는다)
    private var members: [String] {
        var seen: [String] = []
        for item in feedback { for id in item.targetSessionIds where !seen.contains(id) { seen.append(id) } }
        return tracks.map(\.id).filter { seen.contains($0) }
    }

    private var started: [String] { members.filter { sync.teamStarted.contains($0) } }

    var body: some View {
        HStack(spacing: 16) {
            if variants.isOn(.teamRing) { ring }
            if variants.isOn(.presence) { presenceChips }
            Spacer(minLength: 8)
            if variants.isOn(.peerTitles) {
                Button(action: onTitles) { Label("칭호 주기", systemImage: "rosette") }
                    .buttonStyle(GBToolButtonStyle())
            }
        }
        .foregroundStyle(.white)
        .lineLimit(1)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.16, green: 0.14, blue: 0.22))
        .clipped()
    }

    // MARK: D-day 링

    private var dayText: String {
        guard let date = sync.nextRehearsal else { return "합주 날짜 미정" }
        let days = Calendar.current.dateComponents([.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: date)).day ?? 0
        switch days {
        case ..<0: return "합주 끝"
        case 0: return "오늘 합주!"
        default: return "합주 D-\(days)"
        }
    }

    private var ring: some View {
        let total = max(members.count, 1)
        let done = started.count
        let fraction = members.isEmpty ? 0 : CGFloat(done) / CGFloat(total)
        return HStack(spacing: 10) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.15), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(done == total && !members.isEmpty ? Color.green : GB.cycle,
                            style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.5), value: fraction)
                Text(members.isEmpty ? "-" : "\(done)/\(total)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(dayText).font(.system(size: 14, weight: .bold))
                Text(members.isEmpty ? "피드백을 남기면 시작해요"
                     : (done == total ? "모두 시작했어요! 🎉" : "\(done)명이 연습을 시작했어요"))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    // MARK: 지금 연습 중

    private var presenceChips: some View {
        HStack(spacing: 8) {
            if sync.othersPresence.isEmpty {
                Text("지금 연습 중인 사람이 없어요")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
            }
            ForEach(sync.othersPresence) { person in
                HStack(spacing: 5) {
                    Circle().fill(Color.green).frame(width: 7, height: 7)
                    Text("\(DeviceRole.emoji(for: person.role ?? "")) \(FeedbackPeople.name(of: person.role ?? "?", tracks: tracks)) \(person.activity == "recording" ? "녹음 중" : "연습 중")")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.12)))
            }
        }
    }
}

/// 칭호 주기: 동료를 고르고 칭호를 붙여 준다. 받은 칭호는 그 사람 트랙 이름 아래에 보인다.
struct TitlesSheet: View {
    let tracks: [StemTrack]
    let onClose: () -> Void

    @ObservedObject private var sync = SyncClient.shared
    @State private var target: String?
    @State private var custom = ""

    private var candidates: [StemTrack] { tracks.filter { $0.id != DeviceRole.current } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    FlowRow {
                        ForEach(candidates) { track in
                            chip("\(track.instrumentEmoji) \(track.displayName)", isOn: target == track.id) { target = track.id }
                        }
                    }
                } header: { Text("누구에게?") }

                Section {
                    FlowRow {
                        ForEach(PeerTitle.presets, id: \.self) { title in
                            chip(title, isOn: false) { give(title) }
                        }
                    }
                    HStack {
                        TextField("직접 쓰기 (예: 박자 지킴이)", text: $custom)
                        Button("주기") { give(custom.trimmingCharacters(in: .whitespacesAndNewlines)) }
                            .disabled(target == nil || custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } header: { Text("어떤 칭호?") } footer: {
                    Text(target == nil ? "먼저 받는 사람을 골라 주세요." : "칭호를 누르면 바로 전해져요.")
                }

                if !sync.titles.isEmpty {
                    Section("최근에 오간 칭호") {
                        ForEach(sync.titles.sorted { $0.createdAt > $1.createdAt }.prefix(8)) { item in
                            HStack {
                                Text("\(DeviceRole.emoji(for: item.toSession)) \(FeedbackPeople.name(of: item.toSession, tracks: tracks))")
                                    .font(.subheadline.weight(.semibold))
                                Text("“\(item.title)”")
                                Spacer()
                                Text("\(FeedbackPeople.name(of: item.from, tracks: tracks))이(가)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("🏅 칭호 주기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기", action: onClose) } }
        }
    }

    private func give(_ title: String) {
        guard let target, !title.isEmpty else { return }
        sync.giveTitle(title, to: target)
        custom = ""
    }

    private func chip(_ text: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule().fill(isOn ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.15)))
                .overlay(Capsule().stroke(isOn ? Color.accentColor : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}

/// 칩을 가로로 채우고 넘치면 줄바꿈.
private struct FlowRow<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        // 간단한 줄바꿈 레이아웃: 고정 폭 격자 대신 Layout 프로토콜 사용
        FlowLayout(spacing: 8) { content() }
            .padding(.vertical, 4)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? (rows.map(\.width).max() ?? 0),
                      height: rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty { rows.append(Row()) }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

/// 피드백 화면의 응원 줄: 🔥🎯👏💪를 누르면 가볍게 응원이 전해진다. 누른 사람 이름과 개수가 보인다.
struct ReactionStrip: View {
    let feedbackId: UUID
    let tracks: [StemTrack]
    @ObservedObject private var sync = SyncClient.shared

    private var mine: [FeedbackReaction] { sync.reactions.filter { $0.feedbackId == feedbackId } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ForEach(FeedbackReaction.emojis, id: \.self) { emoji in
                    let items = mine.filter { $0.emoji == emoji }
                    let iDidIt = items.contains { $0.author == DeviceRole.current }
                    Button {
                        sync.toggleReaction(emoji, feedbackId: feedbackId)
                    } label: {
                        HStack(spacing: 5) {
                            Text(emoji).font(.title3)
                            if !items.isEmpty { Text("\(items.count)").font(.subheadline.weight(.bold)) }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(iDidIt ? Color.orange.opacity(0.28) : Color.secondary.opacity(0.14)))
                        .overlay(Capsule().stroke(iDidIt ? Color.orange : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            if !mine.isEmpty {
                Text(mine.map { "\($0.emoji) \(FeedbackPeople.name(of: $0.author, tracks: tracks))" }.joined(separator: "  "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
