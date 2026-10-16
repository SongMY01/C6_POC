import SwiftUI

// MARK: - 핀 패널: 화면 오른쪽에서 핀을 만들고 대화한다
//
// 뎁스를 줄이려고 (2026-10-15 UX 검토):
// - 창(시트) 대신 오른쪽 패널 — 대화하는 동안에도 왼쪽 타임라인과 파형이 보인다.
// - 채팅 모양 — 대화는 위로 쌓이고 입력 줄은 항상 아래에 붙어 있다. 👍/🤔 · 툴 · 녹음 · "이렇게 하자"가 입력 줄에 모여 있다.
// - 결론도 메시지 — "✋ 이렇게 하자"를 누르면 쓴 글(과 붙인 툴)이 결론 제안 카드로 대화에 올라가고,
//   동의도 그 카드에서 한다. 정리되면 패널 맨 위에 고정되고 "맞춰 보기"도 거기서 바로.
// - 툴은 창을 띄우지 않고 입력 줄 위 서랍에 펼친다.
// 이 패널에서 말하는 사람은 이 iPad의 역할(DeviceRole.current)이다.

/// 입력 줄: 글 + 👍/🤔 + 툴 서랍 + 녹음 + "이렇게 하자".
struct PinComposer: View {
    @Binding var text: String
    let timeRange: ClosedRange<TimeInterval>
    let tracks: [StemTrack]
    let controller: StemPlayerController
    var placeholder: String
    var showsStances = true
    /// 녹음으로 답할 수 있는 파트 (비어 있으면 녹음 버튼 없음)
    var recordTracks: [StemTrack] = []
    /// nil이면 "이렇게 하자" 버튼 없음
    var onPropose: ((_ text: String, _ tool: FeedbackToolValue?) -> Void)?
    var onRecord: (String) -> Void = { _ in }
    var autofocus = false
    let onSend: (_ text: String, _ stance: FeedbackStance?, _ tool: FeedbackToolValue?) -> Void

    /// 펼친 툴 서랍의 처음 종류 (nil = 닫힘)
    @State private var drawerKind: FeedbackKind?
    @State private var drawerValue: FeedbackToolValue?
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var tool: FeedbackToolValue? { drawerKind == nil ? nil : drawerValue }
    private var canSend: Bool { !trimmed.isEmpty || tool != nil }

    var body: some View {
        VStack(spacing: 8) {
            if let drawerKind { drawer(drawerKind) }
            HStack(alignment: .bottom, spacing: 8) {
                TextField(drawerKind == nil ? placeholder : L("예: 이 믹스 어때요?"), text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($focused)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.08)))
                Button { send(stance: nil) } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
                }
                .disabled(!canSend)
                .accessibilityLabel(L("보내기"))
            }
            HStack(spacing: 6) {
                if showsStances {
                    ForEach([FeedbackStance.agree, .rethink], id: \.self) { stance in
                        Button { send(stance: stance) } label: { Text(stance.emoji) }
                            .buttonStyle(.bordered)
                            .accessibilityLabel(stance.label)
                    }
                }
                ForEach(FeedbackKind.tools) { kind in
                    let isOpen = drawerKind == kind
                    Button {
                        toggleDrawer(kind)
                    } label: {
                        Text(kind.emoji)
                    }
                    .buttonStyle(.bordered)
                    .tint(isOpen ? kind.color : .gray)
                    .accessibilityLabel(L("툴: \(kind.label)"))
                }
                recordButton
                Spacer(minLength: 0)
                if let onPropose {
                    Button {
                        guard canSend else { return }
                        onPropose(trimmed.isEmpty ? (tool?.displaySummary ?? "") : trimmed, tool)
                        reset()
                    } label: {
                        Text(L("✋ 이렇게 하자")).font(.footnote.weight(.bold)).lineLimit(1).fixedSize()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(!canSend)
                }
            }
            .controlSize(.small)
        }
        .padding(12)
        .onAppear { if autofocus { focused = true } }
    }

    @ViewBuilder
    private var recordButton: some View {
        if recordTracks.count == 1, let track = recordTracks.first {
            Button { onRecord(track.id) } label: { Image(systemName: "mic.fill") }
                .buttonStyle(.bordered)
                .tint(.red)
                .accessibilityLabel(L("\(track.displayName) 녹음으로 답하기"))
        } else if recordTracks.count > 1 {
            Menu {
                ForEach(recordTracks) { track in
                    Button("\(track.instrumentEmoji) \(track.displayName)") { onRecord(track.id) }
                }
            } label: {
                Image(systemName: "mic.fill")
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .accessibilityLabel(L("녹음으로 답하기"))
        }
    }

    private func drawer(_ kind: FeedbackKind) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L("툴로 보여주기")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { reset(keepText: true) } label: { Image(systemName: "xmark.circle.fill") }
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(L("첨부 빼기"))
            }
            ScrollView {
                FeedbackToolEditor(kind: kind, timeRange: timeRange, tracks: tracks, controller: controller) { drawerValue = $0 }
                    .id(kind)
            }
            .frame(maxHeight: 380)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
    }

    private func toggleDrawer(_ kind: FeedbackKind) {
        if drawerKind == kind {
            reset(keepText: true)
        } else {
            drawerValue = nil
            drawerKind = kind
        }
    }

    private func send(stance: FeedbackStance?) {
        if stance == nil && !canSend { return }
        let body = trimmed.isEmpty ? (stance?.label ?? "") : trimmed
        onSend(body, stance, tool)
        reset()
    }

    private func reset(keepText: Bool = false) {
        if !keepText { text = "" }
        drawerKind = nil
        drawerValue = nil
    }
}

// MARK: - 새 핀

/// 줄을 길게 눌러 끈 구간에 핀을 꽂고 첫 마디를 남긴다. 받는 사람은 그 줄의 파트.
struct NewPinView: View {
    let track: StemTrack
    let timeRange: ClosedRange<TimeInterval>
    let tracks: [StemTrack]
    let controller: StemPlayerController
    let onSend: (_ text: String, _ tool: FeedbackToolValue?) -> Void

    @State private var text = ""

    private let starters = [L("여기 어떻게 맞출까요?"), L("이렇게 해 보면 어때요?"), L("여기 좋았어요!")]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Text(track.instrumentEmoji).font(.largeTitle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.displayName).font(.title3.weight(.bold))
                            Text("\(formatTime(timeRange.lowerBound)) ~ \(formatTime(timeRange.upperBound))")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(L("핀을 남기면 이 구간에 흰 점이 생기고 \(track.displayName)와 이야기가 시작돼요. 이야기가 정리되면 결론으로 바뀌어요."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(starters, id: \.self) { starter in
                            Button(starter) { text = starter }
                                .buttonStyle(.bordered)
                                .font(.subheadline)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            PinComposer(
                text: $text,
                timeRange: timeRange,
                tracks: tracks,
                controller: controller,
                placeholder: L("예: 여기 끝을 어떻게 맞출까요?"),
                showsStances: false,
                autofocus: true,
                onSend: { body, _, tool in onSend(body.isEmpty ? (tool?.displaySummary ?? "") : body, tool) }
            )
        }
    }
}

// MARK: - 겹친 핀 목록

struct PinListView: View {
    let items: [FeedbackItem]
    let tracks: [StemTrack]
    let onSelect: (FeedbackItem) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(items) { item in
                    Button { onSelect(item) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                FeedbackPinDot(item: item, size: 20)
                                Text("\(formatTime(item.startTime))~\(formatTime(item.endTime))")
                                    .font(.subheadline.monospacedDigit().weight(.semibold))
                                Text("→ \(FeedbackPeople.recipients(of: item, tracks: tracks))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                FeedbackStatusBadge(status: item.status)
                            }
                            Text(item.text.isEmpty ? L("(내용 없음)") : item.displayText)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
    }
}

// MARK: - 핀 대화

struct PinConversationView: View {
    let item: FeedbackItem
    let tracks: [StemTrack]
    let controller: StemPlayerController
    /// 녹음(시도)이 가리키는 패치 (삭제됐으면 nil)
    let patchForId: (UUID) -> Patch?
    let versionLabel: (Patch) -> String
    /// 지금 그 파트 트랙에 끼워진 녹음의 패치 id (nil = 원본)
    let comparisonSelection: (_ sessionId: String) -> UUID?
    /// 원본(nil) 또는 특정 녹음으로 바꿔 끼우고 구간을 반복 재생
    let onCompare: (_ sessionId: String, _ patch: Patch?) -> Void
    let onRecordAttempt: (_ sessionId: String) -> Void
    let onComment: (_ text: String, _ stance: FeedbackStance?, _ tool: FeedbackToolValue?) -> Void
    let onDeleteComment: (UUID) -> Void
    let onDeleteAttempt: (UUID) -> Void
    let onPropose: (_ text: String, _ kind: FeedbackKind?, _ attemptId: UUID?, _ tool: FeedbackToolValue?) -> Void
    let onAgree: (_ conclusionId: UUID) -> Void
    let onClearConclusion: () -> Void
    /// 예전 "음·연주" 피드백의 시범 녹음 (없으면 nil)
    let referencePatch: Patch?
    let isHearingReference: Bool
    let onHearReference: (Bool) -> Void
    /// 지금 믹스로 듣고 있는 것의 id (대화 글 · 결론 · 핀). nil이면 원래 믹스.
    let hearingMixId: UUID?
    let onHearMix: (_ id: UUID?, _ mix: [String: Float]?) -> Void
    let onStartPractice: () -> Void

    @State private var text = ""

    private var me: String { DeviceRole.current }
    private func name(_ id: String) -> String { FeedbackPeople.name(of: id, tracks: tracks) }

    /// 녹음으로 답할 수 있는 파트 = 관련된 파트. 세션 연주자의 iPad에서는 자기 파트만 (리더는 시연용으로 전부).
    private var recordTracks: [StemTrack] {
        guard item.canAddRecording else { return [] }
        let ids = Set(item.isForAllSessions ? tracks.map(\.id) : item.participants)
        let candidates = tracks.filter { ids.contains($0.id) }
        return DeviceRole.isLeader ? candidates : candidates.filter { $0.id == me }
    }

    var body: some View {
        VStack(spacing: 0) {
            if item.status == .concluded { concludedBanner }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        openingMessage
                        if item.targetMix != nil || referencePatch != nil { legacyListening }
                        ForEach(messages) { message in
                            messageView(message)
                        }
                        if !item.canAddRecording {
                            Text(L("녹음으로 답하기는 핀 하나에 \(FeedbackItem.maxRecordings)번까지예요. 더 맞출 부분은 다음 합주에서 같이 맞춰 봐요."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(14)
                }
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: messages.count) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            Divider()
            if item.status == .concluded {
                Text(L("정리된 핀이에요. 다시 이야기하려면 위에서 \"다시 이야기하기\"를 눌러 주세요."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                PinComposer(
                    text: $text,
                    timeRange: item.timeRange,
                    tracks: tracks,
                    controller: controller,
                    placeholder: L("예: 피아노 끝을 한 박 길게 끌어 볼까요?"),
                    recordTracks: recordTracks,
                    onPropose: { body, tool in onPropose(body, tool?.kind, nil, tool) },
                    onRecord: onRecordAttempt,
                    onSend: onComment
                )
            }
        }
    }

    // MARK: 메시지

    private enum Message: Identifiable {
        case comment(FeedbackComment)
        case recording(FeedbackAttempt)
        case proposal(FeedbackConclusion)

        var id: UUID {
            switch self {
            case .comment(let c): return c.id
            case .recording(let a): return a.id
            case .proposal(let p): return p.id
            }
        }

        var date: Date {
            switch self {
            case .comment(let c): return c.createdAt
            case .recording(let a): return a.createdAt
            case .proposal(let p): return p.createdAt
            }
        }
    }

    /// 대화 순서대로. 동의를 기다리는 결론 제안도 제안한 시점에 카드로 끼어 있다 (정리되면 위에 고정).
    private var messages: [Message] {
        var all = item.comments.map(Message.comment) + item.attempts.map(Message.recording)
        if item.status == .proposed, let conclusion = item.conclusion { all.append(.proposal(conclusion)) }
        return all.sorted { $0.date < $1.date }
    }

    @ViewBuilder
    private func messageView(_ message: Message) -> some View {
        switch message {
        case .comment(let comment): commentBubble(comment)
        case .recording(let attempt): recordingBubble(attempt)
        case .proposal(let conclusion): proposalCard(conclusion)
        }
    }

    /// 핀을 남긴 첫 마디
    private var openingMessage: some View {
        bubble(author: item.author, date: item.createdAt, leading: { FeedbackPinDot(item: item, size: 22) }) {
            Text(item.text.isEmpty ? L("(내용 없음 — 예전 손글씨 피드백)") : item.displayText)
                .font(.body.weight(.medium))
                .foregroundStyle(item.text.isEmpty ? .secondary : .primary)
        }
    }

    private func commentBubble(_ comment: FeedbackComment) -> some View {
        bubble(author: comment.author, date: comment.createdAt, leading: {
            Text(comment.stance?.emoji ?? "💬").font(.title3)
        }) {
            VStack(alignment: .leading, spacing: 8) {
                if !comment.displayText.isEmpty { Text(comment.displayText) }
                if let tool = comment.tool {
                    FeedbackToolCard(tool: tool, tracks: tracks, isHearingMix: hearingMixId == comment.id,
                                     onHearMix: { onHearMix($0 ? comment.id : nil, $0 ? tool.targetMix : nil) })
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(tool.kind.color.opacity(0.12)))
                    if item.status == .discussing {
                        Button {
                            onPropose(tool.displaySummary, tool.kind, nil, tool)
                        } label: {
                            Text(L("✋ 이걸로 하자")).font(.caption.weight(.bold))
                        }
                        .buttonStyle(.bordered)
                        .tint(.green)
                    }
                }
            }
        }
        .contextMenu {
            Button(L("삭제"), role: .destructive) { onDeleteComment(comment.id) }
        }
    }

    /// 녹음으로 단 답. "듣기"를 누르면 그 파트 자리에 끼워 구간을 반복 재생하고, 다시 누르면 원본으로.
    private func recordingBubble(_ attempt: FeedbackAttempt) -> some View {
        let patch = patchForId(attempt.patchId)
        let isOn = comparisonSelection(attempt.sessionId) == attempt.patchId
        return bubble(author: attempt.sessionId, date: attempt.createdAt, leading: {
            Image(systemName: "waveform.circle.fill").font(.title2).foregroundStyle(.red)
        }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(L("\(name(attempt.sessionId)) 녹음")).font(.subheadline.weight(.semibold))
                    if let patch { Text(versionLabel(patch)).font(.caption).foregroundStyle(.secondary) }
                }
                HStack(spacing: 8) {
                    if let patch {
                        Button {
                            onCompare(attempt.sessionId, isOn ? nil : patch)
                        } label: {
                            Label(isOn ? L("원본으로") : L("듣기"), systemImage: isOn ? "arrow.uturn.backward" : "play.fill")
                        }
                        .buttonStyle(.bordered)
                        if item.status == .discussing {
                            Button {
                                onPropose(L("🎤 \(name(attempt.sessionId)) 녹음처럼"), nil, attempt.id, nil)
                            } label: {
                                Text(L("✋ 이걸로 하자")).font(.caption.weight(.bold))
                            }
                            .buttonStyle(.bordered)
                            .tint(.green)
                        }
                    } else {
                        Text(L("삭제된 녹음")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                // 예전 형식: 녹음에 달린 코멘트
                ForEach(attempt.comments) { comment in
                    Text("\(name(comment.author)): \(comment.displayText)").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .contextMenu {
            Button(L("녹음 삭제"), role: .destructive) { onDeleteAttempt(attempt.id) }
        }
    }

    /// 동의를 기다리는 결론 제안 카드. 관련된 사람이 여기서 바로 동의한다.
    private func proposalCard(_ conclusion: FeedbackConclusion) -> some View {
        let canAgree = !conclusion.agreedBy.contains(me) && (item.participants.contains(me) || item.isForAllSessions)
        return VStack(alignment: .leading, spacing: 10) {
            Text(L("✋ 결론 제안")).font(.caption.weight(.bold)).foregroundStyle(GB.cycle)
            conclusionBody(conclusion)
            agreementRow(conclusion)
            HStack(spacing: 8) {
                if canAgree {
                    Button { onAgree(conclusion.id) } label: {
                        Text(L("👍 이렇게 해요")).font(.subheadline.weight(.bold)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                } else if conclusion.agreedBy.contains(me) {
                    Text(L("다른 사람의 동의를 기다리는 중")).font(.caption).foregroundStyle(.secondary)
                }
                if conclusion.proposer == me {
                    Button(L("거두기"), role: .destructive, action: onClearConclusion)
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(GB.cycle.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(GB.cycle.opacity(0.6), lineWidth: 1.5))
    }

    /// 정리된 결론: 패널 맨 위에 고정. 여기서 바로 맞춰 보기.
    private var concludedBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("🤝 이렇게 하기로 했어요")).font(.caption.weight(.bold)).foregroundStyle(.green)
            if let conclusion = item.conclusion {
                conclusionBody(conclusion)
            } else {
                Text(L("예전 방식으로 정리된 피드백이에요.")).font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button(action: onStartPractice) {
                    Label(L("맞춰 보기"), systemImage: "play.circle.fill")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button(L("다시 이야기하기"), action: onClearConclusion)
                    .buttonStyle(.bordered)
            }
            Text(item.plan.steps(hasReference: referencePatch != nil).joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color.green.opacity(0.1))
    }

    private func conclusionBody(_ conclusion: FeedbackConclusion) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text((conclusion.kind ?? .free).emoji).font(.title)
            VStack(alignment: .leading, spacing: 6) {
                Text(conclusion.text).font(.headline)
                if let tool = conclusion.tool {
                    FeedbackToolCard(tool: tool, tracks: tracks, isHearingMix: hearingMixId == conclusion.id,
                                     onHearMix: { onHearMix($0 ? conclusion.id : nil, $0 ? tool.targetMix : nil) },
                                     showsSummary: tool.displaySummary != conclusion.text)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(tool.kind.color.opacity(0.12)))
                }
                if let attemptId = conclusion.attemptId, let attempt = item.attempts.first(where: { $0.id == attemptId }),
                   let patch = patchForId(attempt.patchId) {
                    let isOn = comparisonSelection(attempt.sessionId) == attempt.patchId
                    Button {
                        onCompare(attempt.sessionId, isOn ? nil : patch)
                    } label: {
                        Label(isOn ? L("원본으로") : L("🎤 \(name(attempt.sessionId)) 녹음 듣기"),
                              systemImage: isOn ? "arrow.uturn.backward" : "play.fill")
                    }
                    .buttonStyle(.bordered)
                }
                Text(L("\(name(conclusion.proposer)) 제안")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// 관련된 사람별 동의 여부: ✓ 동의 / ○ 아직
    private func agreementRow(_ conclusion: FeedbackConclusion) -> some View {
        let people = item.isForAllSessions ? conclusion.agreedBy : item.participants
        return HStack(spacing: 10) {
            ForEach(people, id: \.self) { person in
                let agreed = conclusion.agreedBy.contains(person)
                Label(name(person), systemImage: agreed ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline)
                    .foregroundStyle(agreed ? .green : .secondary)
            }
        }
    }

    // MARK: 예전 피드백에 담긴 목표 믹스·시범

    private var legacyListening: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let mix = item.targetMix {
                Picker(L("믹스"), selection: Binding(get: { hearingMixId == item.id },
                                                    set: { onHearMix($0 ? item.id : nil, $0 ? mix : nil) })) {
                    Text(L("지금 믹스")).tag(false)
                    Text(L("제안한 믹스")).tag(true)
                }
                .pickerStyle(.segmented)
            }
            if referencePatch != nil {
                Picker(L("시범"), selection: Binding(get: { isHearingReference }, set: onHearReference)) {
                    Text(L("원본")).tag(false)
                    Text(L("시범 녹음")).tag(true)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    // MARK: 말풍선

    private func bubble<Leading: View, Content: View>(author: String, date: Date,
                                                      @ViewBuilder leading: () -> Leading,
                                                      @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 8) {
            leading().frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(name(author)).font(.subheadline.weight(.semibold))
                    Text(date, format: .dateTime.month().day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                content()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(author == me ? Color.accentColor.opacity(0.14) : Color.white.opacity(0.06)))
        }
    }
}
