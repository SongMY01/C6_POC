import SwiftUI

/// 작성 중인 피드백. 시트 밖(플레이어 화면)에 두어서, 시범을 녹음하러 시트를 잠깐 닫았다가
/// 돌아와도 고른 내용이 그대로 남는다.
struct FeedbackDraft {
    var timeRange: ClosedRange<TimeInterval>
    /// 비어 있으면 "전체".
    var targets: Set<String>
    var kind: FeedbackKind?
    /// 질문 번호 → 고른 보기
    var picks: [Int: String] = [:]
    var text = ""
    /// 밸런스: 목표 믹스 (트랙 id → 볼륨)
    var targetMix: [String: Float] = [:]
    /// 음·연주: 시범 녹음 패치
    var referencePatchId: UUID?
}

/// 구간에 피드백을 남기는 화면: 받는 사람 → 종류 → 상황 칩 → (밸런스: 목표 믹스 / 음·연주: 시범 녹음)
/// → 자동으로 만들어진 문장(고칠 수 있음) → 받는 사람에게 같이 가는 연습 방법 미리보기.
struct FeedbackComposerSheet: View {
    @ObservedObject var controller: StemPlayerController
    @Binding var draft: FeedbackDraft
    let hasReference: Bool
    let onSend: () -> Void
    let onCancel: () -> Void
    /// 시범 녹음 (받는 세션 트랙 위에). 시트가 잠깐 닫힌다.
    let onRecordReference: (_ sessionId: String) -> Void
    let onPlayReference: () -> Void
    let onDeleteReference: () -> Void

    /// 목표 믹스를 듣는 중인지 (아니면 지금 믹스)
    @State private var hearingTargetMix = false
    /// 시트를 열 때의 볼륨 — 닫을 때 되돌린다 (목표 믹스는 들어 보기만 하고 곡 볼륨은 안 바꾼다).
    @State private var originalVolumes: [String: Float] = [:]

    private var tracks: [StemTrack] { controller.tracks }
    private var orderedTargets: [String] { tracks.map(\.id).filter { draft.targets.contains($0) } }
    private var trimmedText: String { draft.text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                recipientSection
                kindSection
                if let kind = draft.kind {
                    ForEach(Array(kind.questions(tracks: tracks, targets: orderedTargets).enumerated()), id: \.offset) { index, question in
                        questionSection(index: index, question: question)
                    }
                    if kind == .balance { mixSection }
                    if kind == .playing { referenceSection }
                }
                textSection
                if let kind = draft.kind {
                    planSection(kind)
                }
            }
            .navigationTitle("피드백 남기기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소", action: onCancel)
                }
                ToolbarItem(placement: .principal) {
                    Button {
                        playRegion()
                    } label: {
                        Label(controller.isPlaying ? "멈춤" : "구간 듣기",
                              systemImage: controller.isPlaying ? "pause.fill" : "play.fill")
                            .labelStyle(.titleAndIcon)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("보내기", action: onSend)
                        .disabled(trimmedText.isEmpty)
                }
            }
        }
        .pageSizedSheet()
        .onAppear {
            originalVolumes = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0.volume) })
        }
        .onDisappear {
            controller.pause()
            restoreVolumes()
        }
    }

    // MARK: 받는 사람

    private var recipientSection: some View {
        Section("\(formatTime(draft.timeRange.lowerBound))~\(formatTime(draft.timeRange.upperBound)) 구간 · 받는 사람") {
            FlowChips {
                chip("👥 전체", isOn: draft.targets.isEmpty) { draft.targets.removeAll(); refreshText() }
                ForEach(tracks) { track in
                    chip("\(track.instrumentEmoji) \(track.displayName)", isOn: draft.targets.contains(track.id)) {
                        if draft.targets.contains(track.id) { draft.targets.remove(track.id) } else { draft.targets.insert(track.id) }
                        refreshText()
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: 종류

    private var kindSection: some View {
        Section("무엇에 대한 피드백?") {
            FlowChips(spacing: 10) {
                ForEach(FeedbackKind.allCases) { kind in
                    Button {
                        selectKind(kind)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: kind.icon)
                            Text(kind.label)
                        }
                            .font(.body.weight(.semibold))
                            .fixedSize()
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .foregroundStyle(draft.kind == kind ? Color.black : Color.primary)
                            .background(Capsule().fill(draft.kind == kind ? GB.cycle : Color.secondary.opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func selectKind(_ kind: FeedbackKind) {
        guard draft.kind != kind else { return }
        draft.kind = kind
        draft.picks = [:]
        if kind == .balance && draft.targetMix.isEmpty {
            draft.targetMix = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, originalVolumes[$0.id] ?? $0.volume) })
        }
        if kind != .balance, hearingTargetMix {
            hearingTargetMix = false
            restoreVolumes()
        }
        // 첫 질문의 첫 보기를 미리 골라 둔다 — 칩 하나만 바꿔도 바로 보낼 수 있게.
        if let first = kind.questions(tracks: tracks, targets: orderedTargets).first?.options.first {
            draft.picks[0] = first
        }
        refreshText()
    }

    // MARK: 상황 칩

    private func questionSection(index: Int, question: FeedbackQuestion) -> some View {
        Section(question.title) {
            FlowChips {
                ForEach(question.options, id: \.self) { option in
                    chip(option, isOn: draft.picks[index] == option) {
                        draft.picks[index] = draft.picks[index] == option ? nil : option
                        refreshText()
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// 칩을 바꾸면 문장을 다시 만든다 (직접 고친 문장은 칩을 다시 누를 때 새로 바뀐다).
    private func refreshText() {
        guard let kind = draft.kind else { return }
        let count = kind.questions(tracks: tracks, targets: orderedTargets).count
        let picks = (0..<count).map { draft.picks[$0] }
        let generated = kind.sentence(picks: picks, hasReference: hasReference)
        if !generated.isEmpty || kind == .free { draft.text = generated }
    }

    // MARK: 밸런스: 목표 믹스

    private var mixSection: some View {
        Section {
            Picker("듣기", selection: Binding(
                get: { hearingTargetMix },
                set: { hearingTargetMix = $0; applyHearing() }
            )) {
                Text("지금 믹스").tag(false)
                Text("목표 믹스").tag(true)
            }
            .pickerStyle(.segmented)
            ForEach(tracks) { track in
                HStack(spacing: 12) {
                    Text("\(track.instrumentEmoji) \(track.displayName)")
                        .frame(width: 110, alignment: .leading)
                    Slider(value: Binding(
                        get: { Double(draft.targetMix[track.id] ?? track.volume) },
                        set: { value in
                            draft.targetMix[track.id] = Float(value)
                            if !hearingTargetMix { hearingTargetMix = true }
                            applyHearing()
                        }
                    ), in: 0...1)
                    Text("\(Int(((draft.targetMix[track.id] ?? track.volume) * 100).rounded()))")
                        .font(.caption.monospacedDigit())
                        .frame(width: 34, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("이렇게 들려야 해요")
        } footer: {
            Text("슬라이더로 맞추고 \"구간 듣기\"로 들어 보세요. 지금 ↔ 목표를 번갈아 눌러 비교할 수 있어요. 곡 볼륨은 바뀌지 않아요.")
        }
    }

    private func applyHearing() {
        for track in tracks {
            track.volume = hearingTargetMix ? (draft.targetMix[track.id] ?? track.volume) : (originalVolumes[track.id] ?? track.volume)
        }
    }

    private func restoreVolumes() {
        for track in tracks {
            if let v = originalVolumes[track.id] { track.volume = v }
        }
    }

    // MARK: 음·연주: 시범 녹음

    private var referenceSection: some View {
        let target = orderedTargets.count == 1 ? tracks.first { $0.id == orderedTargets[0] } : nil
        return Section {
            if hasReference {
                HStack {
                    Label("시범 녹음 있음", systemImage: "waveform.circle.fill").foregroundStyle(.red)
                    Spacer()
                    Button("들어 보기", action: onPlayReference)
                    Button("지우기", role: .destructive, action: onDeleteReference)
                }
                .buttonStyle(.borderless)
            }
            if let target {
                Button {
                    onRecordReference(target.id)
                } label: {
                    Label(hasReference ? "다시 녹음" : "\(target.displayName) 대신 쳐서·불러서 녹음",
                          systemImage: "record.circle")
                }
            }
        } header: {
            Text("보여 주기 (선택)")
        } footer: {
            if target == nil {
                Text("받는 사람을 한 명만 고르면 그 세션 자리에 시범을 녹음할 수 있어요.")
            } else {
                Text("\(target!.displayName) 소리를 끄고 나머지 세션을 들으면서 녹음해요. 악기로 쳐도 되고 입으로 불러도 돼요. 받는 사람은 원본 ↔ 시범을 번갈아 들을 수 있어요.")
            }
        }
    }

    // MARK: 문장 · 연습 방법

    private var textSection: some View {
        Section {
            TextField(draft.kind == nil ? "종류를 고르거나 바로 써도 돼요" : "예: 후렴 들어가기 전에 템포가 빨라져요",
                      text: $draft.text, axis: .vertical)
                .lineLimit(2...6)
        } header: {
            Text("보낼 문장")
        } footer: {
            if draft.kind != nil && draft.kind != .free {
                Text("칩을 고르면 문장이 만들어져요. 필요하면 고쳐 쓰세요.")
            }
        }
    }

    private func planSection(_ kind: FeedbackKind) -> some View {
        Section("받는 사람에게 같이 가는 연습 방법") {
            FlowChips {
                ForEach(kind.plan.steps(hasReference: hasReference), id: \.self) { step in
                    Text(step)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .foregroundStyle(Color.green)
                        .background(Capsule().fill(Color.green.opacity(0.16)))
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: 도우미

    private func playRegion() {
        if controller.isPlaying {
            controller.pause()
            return
        }
        controller.loopRegion = draft.timeRange
        controller.isLoopEnabled = true
        controller.seek(to: draft.timeRange.lowerBound)
        controller.play()
    }

    private func chip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(.subheadline.weight(.semibold))
                if isOn { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(isOn ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.15)))
            .overlay(Capsule().stroke(isOn ? Color.accentColor : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// iPad에서 시트를 기본(작은 폼)보다 크게 연다 — 칩이 많아 스크롤이 길어지지 않게.
    @ViewBuilder
    func pageSizedSheet() -> some View {
        if #available(iOS 18.0, *) {
            presentationSizing(.page)
        } else {
            self
        }
    }
}

/// 칩들을 가로로 채우다 넘치면 다음 줄로 넘기는 레이아웃.
struct FlowChips: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
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
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
