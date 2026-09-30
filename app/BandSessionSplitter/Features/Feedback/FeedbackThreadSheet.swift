import SwiftUI

/// 피드백 하나의 진행 화면: 피드백 → 1차 시도(녹음 + 코멘트) → 2차 시도 → … → 통과.
///
/// 시도의 녹음은 PatchStore의 패치를 가리킨다. "듣기"를 누르면 그 패치를 해당 트랙에 켜서
/// 다른 세션과 함께 피드백 구간을 재생하므로, 원래 연주와 고친 연주를 바로 비교할 수 있다.
/// 최신 시도만 펼쳐 두고 이전 시도는 접어서, 여러 번 주고받아도 화면이 길어지지 않게 한다.
struct FeedbackThreadSheet: View {
    let item: FeedbackItem
    let tracks: [StemTrack]
    /// 시도가 가리키는 패치 (삭제됐으면 nil).
    let patchForId: (UUID) -> Patch?
    /// 시도로 올릴 수 있는 기존 패치들 (받는 세션의 패치, 최신 순).
    let attachablePatches: [Patch]
    let versionLabel: (Patch) -> String
    let isPatchPlaying: (Patch) -> Bool
    let onListen: (Patch) -> Void
    let onRecordAttempt: (_ sessionId: String) -> Void
    let onAttachPatch: (Patch) -> Void
    let onComment: (_ text: String, _ author: String, _ attemptId: UUID?) -> Void
    let onDeleteComment: (UUID) -> Void
    let onDeleteAttempt: (UUID) -> Void
    /// 시도 통과 처리 (nil이면 다시 열기)
    let onSetPassed: (UUID?) -> Void
    let onDeleteFeedback: () -> Void
    let onClose: () -> Void

    @State private var commentText = ""
    @State private var commentAuthor = FeedbackPeople.leader
    /// 펼쳐 둔 이전 시도들 (최신 시도는 항상 펼침).
    @State private var expandedAttempts: Set<UUID> = []

    /// 녹음으로 답할 수 있는 세션 = 받는 세션 (전체 대상이면 모든 세션).
    private var replyingTracks: [StemTrack] {
        item.isForAllSessions ? tracks : tracks.filter { item.targetSessionIds.contains($0.id) }
    }

    private var latestAttempt: FeedbackAttempt? { item.attempts.last }

    var body: some View {
        NavigationStack {
            List {
                feedbackSection

                if !item.attempts.isEmpty {
                    Section("시도 \(item.attempts.count)회") {
                        ForEach(Array(item.attempts.enumerated()), id: \.element.id) { index, attempt in
                            attemptView(attempt, number: index + 1, isLatest: attempt.id == latestAttempt?.id)
                        }
                    }
                }

                if item.status == .passed {
                    Section {
                        Button("다시 열기 (추가 연습 필요)") { onSetPassed(nil) }
                    } footer: {
                        Text("다시 녹음해서 올려도 자동으로 다시 열립니다.")
                    }
                }

                recordSection
                commentSection

                Section {
                    Button("피드백 삭제", role: .destructive, action: onDeleteFeedback)
                }
            }
            .navigationTitle("피드백")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기", action: onClose)
                }
            }
        }
    }

    // MARK: 피드백 본문

    private var feedbackSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("\(formatTime(item.startTime)) ~ \(formatTime(item.endTime))")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                    Text("→ \(FeedbackPeople.recipients(of: item, tracks: tracks))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    FeedbackStatusBadge(status: item.status)
                }
                Text(item.text.isEmpty ? "(내용 없음 — 예전 손글씨 피드백)" : item.text)
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
            Text("피드백")
        }
    }

    // MARK: 시도

    @ViewBuilder
    private func attemptView(_ attempt: FeedbackAttempt, number: Int, isLatest: Bool) -> some View {
        let isExpanded = isLatest || expandedAttempts.contains(attempt.id)
        VStack(alignment: .leading, spacing: 10) {
            attemptHeader(attempt, number: number, isLatest: isLatest, isExpanded: isExpanded)
            if isExpanded {
                if attempt.comments.isEmpty {
                    Text(isLatest && item.status == .awaitingComment ? "코멘트를 기다리는 중" : "코멘트 없음")
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
            Button("시도 삭제", role: .destructive) { onDeleteAttempt(attempt.id) }
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
                    Text("\(number)차 시도")
                        .font(.subheadline.weight(.bold))
                    Text(FeedbackPeople.name(of: attempt.sessionId, tracks: tracks))
                        .font(.subheadline)
                    if let patch { Text(versionLabel(patch)).font(.caption).foregroundStyle(.secondary) }
                    if isPassed { FeedbackStatusBadge(status: .passed) }
                    if !isExpanded && !attempt.comments.isEmpty {
                        Text("코멘트 \(attempt.comments.count)").font(.caption).foregroundStyle(.secondary)
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
            if let patch {
                Button {
                    onListen(patch)
                } label: {
                    Label(isPatchPlaying(patch) ? "끄기" : "듣기",
                          systemImage: isPatchPlaying(patch) ? "speaker.slash.fill" : "play.fill")
                }
                .buttonStyle(.bordered)
            } else {
                Text("삭제된 녹음").font(.caption).foregroundStyle(.secondary)
            }
            if isLatest && item.status != .passed {
                Button {
                    onSetPassed(attempt.id)
                } label: {
                    Label("통과", systemImage: "checkmark")
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
                Text(comment.text)
            }
        }
        .contextMenu {
            Button("코멘트 삭제", role: .destructive) { onDeleteComment(comment.id) }
        }
    }

    // MARK: 새 시도 올리기

    private var recordSection: some View {
        Section {
            ForEach(replyingTracks) { track in
                Button {
                    onRecordAttempt(track.id)
                } label: {
                    Label("\(track.instrumentEmoji) \(track.displayName) \(item.attempts.count + 1)차 시도 녹음하기", systemImage: "record.circle")
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
                    Label("이미 녹음한 패치로 올리기", systemImage: "paperclip")
                }
            }
        } header: {
            Text(item.attempts.isEmpty ? "연습해서 올리기" : "다시 연습해서 올리기")
        } footer: {
            Text("이 피드백 구간을 준비 시간 2초 뒤부터 녹음합니다. 올리면 새 시도로 추가되고 코멘트 요청 상태가 됩니다.")
        }
    }

    // MARK: 코멘트

    private var commentSection: some View {
        Section {
            Picker("쓰는 사람", selection: $commentAuthor) {
                Text("리더").tag(FeedbackPeople.leader)
                ForEach(tracks) { track in
                    Text("\(track.instrumentEmoji) \(track.displayName)").tag(track.id)
                }
            }
            HStack(alignment: .bottom) {
                TextField(latestAttempt == nil ? "예: 3박째 베이스 음이 반음 낮아요" : "예: 이번엔 박자 딱 맞아요!",
                          text: $commentText, axis: .vertical)
                    .lineLimit(1...5)
                Button("보내기") {
                    onComment(commentText.trimmingCharacters(in: .whitespacesAndNewlines), commentAuthor, latestAttempt?.id)
                    commentText = ""
                }
                .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            if let latest = latestAttempt, let n = item.attemptNumber(of: latest.id) {
                Text("\(n)차 시도에 코멘트")
            } else {
                Text("피드백에 코멘트")
            }
        }
    }
}

/// 상태 배지: 연습 필요(주황) / 코멘트 요청(파랑) / 통과(초록).
struct FeedbackStatusBadge: View {
    let status: FeedbackStatus

    var body: some View {
        Text(status.label)
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
                            Text("\(formatTime(item.startTime))~\(formatTime(item.endTime))")
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                            Text("→ \(FeedbackPeople.recipients(of: item, tracks: tracks))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if !item.attempts.isEmpty {
                                Text("시도 \(item.attempts.count)회").font(.caption).foregroundStyle(.secondary)
                            }
                            FeedbackStatusBadge(status: item.status)
                        }
                        Text(item.text.isEmpty ? "(내용 없음)" : item.text)
                            .lineLimit(2)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("이 구간의 피드백 \(items.count)개")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("닫기", action: onClose) }
            }
        }
    }
}

/// 피드백에 등장하는 사람 표기: "leader" 또는 세션 id → 화면 이름.
enum FeedbackPeople {
    static let leader = "leader"

    static func name(of id: String, tracks: [StemTrack]) -> String {
        if id == leader { return "리더" }
        return tracks.first { $0.id == id }?.displayName ?? id
    }

    /// "전체" 또는 "베이스, 드럼".
    static func recipients(of item: FeedbackItem, tracks: [StemTrack]) -> String {
        if item.isForAllSessions { return "전체" }
        return item.targetSessionIds.map { name(of: $0, tracks: tracks) }.joined(separator: ", ")
    }
}
