import SwiftUI

/// 피드백 하나의 진행 화면: 피드백 → 1차 시도(녹음 + 코멘트) → 2차 시도 → … → 통과.
///
/// 시도의 녹음은 PatchStore의 패치를 가리킨다. "비교해서 듣기"에서 원본/각 시도를 고르면
/// 그 버전을 해당 트랙에 끼워 다른 세션과 함께 피드백 구간을 반복 재생한다 — 재생을 멈추지 않고
/// 바꿔 끼우므로 원본 ↔ 최신, 이전 시도 ↔ 최신을 바로바로 비교할 수 있다.
/// "통과"하면 그 시도의 녹음이 곡에 반영된다(채택: 곡을 열 때 기본으로 켜짐).
/// 최신 시도만 펼쳐 두고 이전 시도는 접어서, 여러 번 주고받아도 화면이 길어지지 않게 한다.
struct FeedbackThreadSheet: View {
    let item: FeedbackItem
    let tracks: [StemTrack]
    /// 시도가 가리키는 패치 (삭제됐으면 nil).
    let patchForId: (UUID) -> Patch?
    /// 시도로 올릴 수 있는 기존 패치들 (받는 세션의 패치, 최신 순).
    let attachablePatches: [Patch]
    let versionLabel: (Patch) -> String
    /// 비교 듣기에서 지금 그 세션 트랙에 끼워진 시도의 패치 id (nil = 원본)
    let comparisonSelection: (_ sessionId: String) -> UUID?
    /// 원본(nil) 또는 특정 시도의 패치로 바꿔 끼우고 피드백 구간을 반복 재생
    let onCompare: (_ sessionId: String, _ patch: Patch?) -> Void
    let onRecordAttempt: (_ sessionId: String) -> Void
    let onAttachPatch: (Patch) -> Void
    let onComment: (_ text: String, _ author: String, _ attemptId: UUID?) -> Void
    let onDeleteComment: (UUID) -> Void
    let onDeleteAttempt: (UUID) -> Void
    /// 시도 통과 처리 (nil이면 다시 열기)
    let onSetPassed: (UUID?) -> Void
    /// 음·연주 피드백의 리더 시범 녹음 (없으면 nil)
    let referencePatch: Patch?
    /// 지금 받는 세션 자리에 시범이 끼워져 있는지
    let isHearingReference: Bool
    let onHearReference: (Bool) -> Void
    /// 밸런스 피드백: 목표 믹스로 듣는 중인지
    let isHearingTargetMix: Bool
    let onHearTargetMix: (Bool) -> Void
    /// 종류가 정한 방법(카운트인 · 템포 사다리 · 목표 믹스)으로 연습 시작 — 시트가 닫힌다
    let onStartPractice: () -> Void
    /// 약속 피드백 "확인"
    let onConfirm: () -> Void
    let onDeleteFeedback: () -> Void
    let onClose: () -> Void

    @State private var commentText = ""
    /// 코멘트 작성자 — 이 iPad의 역할이 기본값 (필요하면 바꿀 수 있음).
    @State private var commentAuthor = DeviceRole.current
    /// 펼쳐 둔 이전 시도들 (최신 시도는 항상 펼침).
    @State private var expandedAttempts: Set<UUID> = []

    /// 녹음으로 답할 수 있는 세션 = 받는 세션 (전체 대상이면 모든 세션).
    /// 세션 연주자의 iPad에서는 자기 세션만 보인다 (리더는 시연용으로 전부).
    private var replyingTracks: [StemTrack] {
        let targets = item.isForAllSessions ? tracks : tracks.filter { item.targetSessionIds.contains($0.id) }
        return DeviceRole.isLeader ? targets : targets.filter { $0.id == DeviceRole.current }
    }

    /// 약속 확인은 받는 세션 연주자가 한다 (쓴 리더는 누가 확인했는지만 본다).
    private var canConfirm: Bool {
        !DeviceRole.isLeader && item.isFor(sessionId: DeviceRole.current)
            && !item.confirmedBy.contains(DeviceRole.current)
    }

    /// 통과·다시 열기는 리더만.
    private var canJudge: Bool { DeviceRole.isLeader }

    private var latestAttempt: FeedbackAttempt? { item.attempts.last }

    var body: some View {
        NavigationStack {
            List {
                feedbackSection
                practiceSection

                if !item.attempts.isEmpty {
                    compareSection
                    Section(L("시도 \(item.attempts.count)회")) {
                        ForEach(Array(item.attempts.enumerated()), id: \.element.id) { index, attempt in
                            attemptView(attempt, number: index + 1, isLatest: attempt.id == latestAttempt?.id)
                        }
                    }
                }

                if item.status == .passed && canJudge && item.kind != .cue {
                    Section {
                        Button(L("다시 열기 (추가 연습 필요)")) { onSetPassed(nil) }
                    } footer: {
                        Text(L("통과한 시도의 녹음이 곡에 반영되어 있습니다. 다시 열면 원본으로 돌아갑니다. 새 시도를 올리면 피드백이 다시 열리지만, 새 시도가 통과할 때까지는 지금 반영된 녹음이 유지됩니다."))
                    }
                }

                if item.kind != .cue { recordSection }
                commentSection

                Section {
                    Button(L("피드백 삭제"), role: .destructive, action: onDeleteFeedback)
                }
            }
            .navigationTitle(L("피드백"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("닫기"), action: onClose)
                }
            }
        }
    }

    // MARK: 피드백 본문

    private var feedbackSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if let kind = item.kind {
                        Label(kind.label, systemImage: kind.icon)
                            .font(.subheadline.weight(.bold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(GB.cycle.opacity(0.22)))
                    }
                    Text("\(formatTime(item.startTime)) ~ \(formatTime(item.endTime))")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                    Text("→ \(FeedbackPeople.recipients(of: item, tracks: tracks))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    FeedbackStatusBadge(item: item)
                }
                Text(item.text.isEmpty ? L("(내용 없음 — 예전 손글씨 피드백)") : item.displayText)
                    .foregroundStyle(item.text.isEmpty ? .secondary : .primary)
                Text(item.createdAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            ForEach(item.comments) { comment in
                commentRow(comment)
            }
        } header: {
            Text(L("피드백"))
        }
    }

    // MARK: 연습하기 (종류별)

    /// 받는 사람이 할 일: 약속이면 "확인"만, 나머지는 종류가 정한 방법으로 "연습 시작".
    @ViewBuilder
    private var practiceSection: some View {
        let plan = item.plan
        if plan.confirmOnly {
            Section {
                if item.confirmedBy.isEmpty {
                    Text(L("아직 아무도 확인하지 않았어요")).foregroundStyle(.secondary)
                } else {
                    Label(L("\(item.confirmedBy.map { FeedbackPeople.name(of: $0, tracks: tracks) }.joined(separator: ", ")) 확인"),
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                if canConfirm {
                    Button(action: onConfirm) {
                        Label(L("확인했어요"), systemImage: "hand.thumbsup.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            } header: {
                Text(L("약속 확인"))
            } footer: {
                Text(DeviceRole.isLeader
                     ? L("받는 사람이 확인을 누르면 통과돼요.")
                     : L("연습할 건 없어요. 약속을 봤다면 확인만 눌러 주세요."))
            }
        } else {
            Section {
                if item.kind == .balance, item.targetMix != nil {
                    Picker(L("듣기"), selection: Binding(get: { isHearingTargetMix }, set: onHearTargetMix)) {
                        Text(L("지금 믹스")).tag(false)
                        Text(L("리더 목표 믹스")).tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                if let referencePatch {
                    Picker(L("시범"), selection: Binding(get: { isHearingReference }, set: onHearReference)) {
                        Text(L("원본")).tag(false)
                        Text(L("리더 시범")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityHint(L("\(FeedbackPeople.name(of: referencePatch.sessionId, tracks: tracks)) 자리에 시범을 끼워 들어요"))
                }
                HStack(spacing: 6) {
                    ForEach(plan.steps(hasReference: referencePatch != nil), id: \.self) { step in
                        Text(step)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .foregroundStyle(.green)
                            .background(Capsule().fill(Color.green.opacity(0.15)))
                    }
                }
                Button(action: onStartPractice) {
                    Label(L("연습 시작"), systemImage: "play.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } header: {
                Text(L("연습하기"))
            } footer: {
                Text(practiceFooter(plan))
            }
        }
    }

    private func practiceFooter(_ plan: PracticePlan) -> String {
        if let first = plan.ladder.first, plan.ladder.count > 1 {
            return L("카운트인 뒤 \(Int((first * 100).rounded()))% 속도부터 구간을 두 바퀴씩 돌고, 100%로 한 바퀴 돌면 끝나요.")
        }
        if plan.usesTargetMix { return L("리더가 맞춘 믹스로 구간을 반복해요. 연습 중에도 지금 ↔ 목표를 바꿔 들을 수 있어요.") }
        if plan.countIn { return L("카운트인 뒤 원래 속도로 구간을 반복해요.") }
        return L("구간을 반복해요.")
    }

    // MARK: 시도

    @ViewBuilder
    private func attemptView(_ attempt: FeedbackAttempt, number: Int, isLatest: Bool) -> some View {
        let isExpanded = isLatest || expandedAttempts.contains(attempt.id)
        VStack(alignment: .leading, spacing: 10) {
            attemptHeader(attempt, number: number, isLatest: isLatest, isExpanded: isExpanded)
            if isExpanded {
                if attempt.comments.isEmpty {
                    Text(isLatest && item.status == .awaitingComment ? L("코멘트를 기다리는 중") : L("코멘트 없음"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 40)
                } else {
                    ForEach(attempt.comments) { comment in
                        commentRow(comment).padding(.leading, 40)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button(L("시도 삭제"), role: .destructive) { onDeleteAttempt(attempt.id) }
        }
    }

    private func attemptHeader(_ attempt: FeedbackAttempt, number: Int, isLatest: Bool, isExpanded: Bool) -> some View {
        let patch = patchForId(attempt.patchId)
        let isPassed = item.passedAttemptId == attempt.id
        return HStack(spacing: 12) {
            Image(systemName: isPassed ? "checkmark.circle.fill" : "waveform.circle.fill")
                .font(.title2)
                .foregroundStyle(isPassed ? .green : .red)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(L("\(number)차 시도"))
                        .font(.subheadline.weight(.bold))
                    Text(FeedbackPeople.name(of: attempt.sessionId, tracks: tracks))
                        .font(.subheadline)
                    if let patch { Text(versionLabel(patch)).font(.caption).foregroundStyle(.secondary) }
                    if isPassed { FeedbackStatusBadge(status: .passed) }
                    if !isExpanded && !attempt.comments.isEmpty {
                        Text(L("코멘트 \(attempt.comments.count)")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(attempt.createdAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isLatest else { return }
                if expandedAttempts.contains(attempt.id) {
                    expandedAttempts.remove(attempt.id)
                } else {
                    expandedAttempts.insert(attempt.id)
                }
            }
            Spacer()
            if !isLatest {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if patch == nil {
                Text(L("삭제된 녹음")).font(.caption).foregroundStyle(.secondary)
            }
            if isLatest && item.status != .passed && canJudge {
                Button {
                    onSetPassed(attempt.id)
                } label: {
                    Label(L("통과"), systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
    }

    private func commentRow(_ comment: FeedbackComment) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "text.bubble").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(FeedbackPeople.name(of: comment.author, tracks: tracks)).font(.subheadline.weight(.semibold))
                    Text(comment.createdAt, format: .dateTime.month().day().hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(comment.displayText)
            }
        }
        .contextMenu {
            Button(L("코멘트 삭제"), role: .destructive) { onDeleteComment(comment.id) }
        }
    }

    // MARK: 비교해서 듣기

    /// 시도를 올린 세션마다: [원본 | 1차 | 2차 …] 중 하나를 골라 그 버전으로 피드백 구간을 듣는다.
    private var compareSection: some View {
        let sessions = item.attempts.map(\.sessionId).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return Section {
            ForEach(sessions, id: \.self) { sessionId in
                let attempts = item.attempts.filter { $0.sessionId == sessionId && patchForId($0.patchId) != nil }
                VStack(alignment: .leading, spacing: 8) {
                    if sessions.count > 1 {
                        Text(FeedbackPeople.name(of: sessionId, tracks: tracks)).font(.subheadline.weight(.semibold))
                    }
                    Picker(L("비교"), selection: Binding<UUID?>(
                        get: { comparisonSelection(sessionId) },
                        set: { id in onCompare(sessionId, id.flatMap(patchForId)) }
                    )) {
                        Text(L("원본")).tag(UUID?.none)
                        ForEach(attempts) { attempt in
                            let n = item.attemptNumber(of: attempt.id) ?? 0
                            Text(item.passedAttemptId == attempt.id ? L("\(n)차 ✓") : L("\(n)차")).tag(UUID?.some(attempt.patchId))
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text(L("비교해서 듣기"))
        } footer: {
            Text(L("고르면 그 버전으로 바꿔 끼워 피드백 구간을 반복 재생합니다. 닫으면 곡에 반영된 버전으로 돌아갑니다."))
        }
    }

    // MARK: 새 시도 올리기

    private var recordSection: some View {
        Section {
            ForEach(replyingTracks) { track in
                Button {
                    onRecordAttempt(track.id)
                } label: {
                    Label(L("\(track.instrumentEmoji) \(track.displayName) \(item.attempts.count + 1)차 시도 녹음하기"), systemImage: "record.circle")
                }
            }
            if !attachablePatches.isEmpty {
                Menu {
                    ForEach(attachablePatches) { patch in
                        Button("\(FeedbackPeople.name(of: patch.sessionId, tracks: tracks)) \(versionLabel(patch)) · \(formatTime(patch.startTime))~\(formatTime(patch.endTime))") {
                            onAttachPatch(patch)
                        }
                    }
                } label: {
                    Label(L("이미 녹음한 패치로 올리기"), systemImage: "paperclip")
                }
            }
        } header: {
            Text(item.attempts.isEmpty ? L("연습해서 올리기") : L("다시 연습해서 올리기"))
        } footer: {
            Text(L("이 피드백 구간을 준비 시간 2초 뒤부터 녹음합니다. 올리면 새 시도로 추가되고 코멘트 요청 상태가 됩니다."))
        }
    }

    // MARK: 코멘트

    private var commentSection: some View {
        Section {
            Picker(L("쓰는 사람"), selection: $commentAuthor) {
                Text(L("리더")).tag(FeedbackPeople.leader)
                ForEach(tracks) { track in
                    Text("\(track.instrumentEmoji) \(track.displayName)").tag(track.id)
                }
            }
            HStack(alignment: .bottom) {
                TextField(latestAttempt == nil ? L("예: 3박째 베이스 음이 반음 낮아요") : L("예: 이번엔 박자 딱 맞아요!"),
                          text: $commentText, axis: .vertical)
                    .lineLimit(1...5)
                Button(L("보내기")) {
                    onComment(commentText.trimmingCharacters(in: .whitespacesAndNewlines), commentAuthor, latestAttempt?.id)
                    commentText = ""
                }
                .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            if let latest = latestAttempt, let n = item.attemptNumber(of: latest.id) {
                Text(L("\(n)차 시도에 코멘트"))
            } else {
                Text(L("피드백에 코멘트"))
            }
        }
    }
}

/// 상태 배지: 연습 필요(주황) / 코멘트 요청(파랑) / 통과(초록).
struct FeedbackStatusBadge: View {
    let status: FeedbackStatus
    var label: String?

    init(status: FeedbackStatus, label: String? = nil) {
        self.status = status
        self.label = label
    }

    /// 약속 피드백은 연습이 아니라 확인을 기다리므로 "확인 필요"로 보여준다.
    init(item: FeedbackItem) {
        self.init(status: item.status,
                  label: item.kind == .cue && item.status != .passed ? L("확인 필요") : nil)
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
        case .needsPractice: return .orange
        case .awaitingComment: return .blue
        case .passed: return .green
        }
    }

    /// 어두운 타임라인 위 표시용 색.
    var timelineColor: Color {
        switch self {
        case .needsPractice: return Color.orange.opacity(0.9)
        case .awaitingComment: return .cyan
        case .passed: return Color.green.opacity(0.55)
        }
    }
}

/// 겹치거나 가까이 붙은 피드백 묶음을 탭했을 때, 그중 하나를 고르는 목록.
struct FeedbackPickerSheet: View {
    let items: [FeedbackItem]
    let tracks: [StemTrack]
    let onSelect: (FeedbackItem) -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List(items) { item in
                Button { onSelect(item) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            if let kind = item.kind {
                                Label(kind.label, systemImage: kind.icon)
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(Capsule().fill(GB.cycle.opacity(0.22)))
                            }
                            Text("\(formatTime(item.startTime))~\(formatTime(item.endTime))")
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                            Text("→ \(FeedbackPeople.recipients(of: item, tracks: tracks))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if !item.attempts.isEmpty {
                                Text(L("시도 \(item.attempts.count)회")).font(.caption).foregroundStyle(.secondary)
                            }
                            FeedbackStatusBadge(item: item)
                        }
                        Text(item.text.isEmpty ? L("(내용 없음)") : item.displayText)
                            .lineLimit(2)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle(L("이 구간의 피드백 \(items.count)개"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("닫기"), action: onClose) }
            }
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
