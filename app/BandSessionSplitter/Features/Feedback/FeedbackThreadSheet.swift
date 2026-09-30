import SwiftUI

/// 피드백 하나의 스레드: 원래 피드백 → 받은 세션이 올린 재녹음(코멘트 요청) → 코멘트 → …
///
/// 녹음 답변은 PatchStore의 패치를 가리킨다. "듣기"를 누르면 그 패치를 해당 트랙에 켜서
/// 다른 세션과 함께 피드백 구간을 재생하므로, 원래 연주와 고친 연주를 바로 비교할 수 있다.
struct FeedbackThreadSheet: View {
    let item: FeedbackItem
    let tracks: [StemTrack]
    /// 녹음 답변이 가리키는 패치 (삭제됐으면 nil).
    let patchForId: (UUID) -> Patch?
    /// 답변으로 첨부할 수 있는 기존 패치들 (받는 세션의 패치, 최신 순).
    let attachablePatches: [Patch]
    let versionLabel: (Patch) -> String
    let isPatchPlaying: (Patch) -> Bool
    let onListen: (Patch) -> Void
    let onRecordReply: (_ sessionId: String) -> Void
    let onAttachPatch: (Patch) -> Void
    let onComment: (_ text: String, _ author: String) -> Void
    let onDeleteReply: (UUID) -> Void
    let onDeleteFeedback: () -> Void
    let onClose: () -> Void

    @State private var commentText = ""
    @State private var commentAuthor = FeedbackPeople.leader

    /// 녹음으로 답할 수 있는 세션 = 받는 세션 (전체 대상이면 모든 세션).
    private var replyingTracks: [StemTrack] {
        item.isForAllSessions ? tracks : tracks.filter { item.targetSessionIds.contains($0.id) }
    }

    private var lastRecordingId: UUID? {
        item.replies.last { $0.kind == .recording }?.id
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(formatTime(item.startTime)) ~ \(formatTime(item.endTime))")
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                            Text("→ \(FeedbackPeople.recipients(of: item, tracks: tracks))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text(item.text.isEmpty ? "(내용 없음 — 예전 손글씨 피드백)" : item.text)
                            .foregroundStyle(item.text.isEmpty ? .secondary : .primary)
                        Text(item.createdAt, format: .dateTime.month().day().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("피드백")
                }

                if !item.replies.isEmpty {
                    Section("답변") {
                        ForEach(item.replies) { reply in
                            replyRow(reply)
                        }
                        .onDelete { offsets in
                            offsets.map { item.replies[$0].id }.forEach(onDeleteReply)
                        }
                    }
                }

                Section {
                    ForEach(replyingTracks) { track in
                        Button {
                            onRecordReply(track.id)
                        } label: {
                            Label("\(track.instrumentEmoji) \(track.displayName) 다시 녹음해서 올리기", systemImage: "record.circle")
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
                            Label("이미 녹음한 패치 올리기", systemImage: "paperclip")
                        }
                    }
                } header: {
                    Text("녹음으로 답하고 코멘트 요청")
                } footer: {
                    Text("녹음하면 이 피드백 구간을 준비 시간 2초 뒤부터 녹음합니다. 저장하면 이 스레드에 올라가고 코멘트 요청 상태가 됩니다.")
                }

                Section("코멘트 남기기") {
                    Picker("쓰는 사람", selection: $commentAuthor) {
                        Text("리더").tag(FeedbackPeople.leader)
                        ForEach(tracks) { track in
                            Text("\(track.instrumentEmoji) \(track.displayName)").tag(track.id)
                        }
                    }
                    HStack(alignment: .bottom) {
                        TextField("예: 이번엔 박자 딱 맞아요!", text: $commentText, axis: .vertical)
                            .lineLimit(1...5)
                        Button("보내기") {
                            onComment(commentText.trimmingCharacters(in: .whitespacesAndNewlines), commentAuthor)
                            commentText = ""
                        }
                        .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section {
                    Button("피드백 삭제", role: .destructive, action: onDeleteFeedback)
                }
            }
            .navigationTitle(item.isAwaitingComment ? "피드백 · 코멘트 요청 중" : "피드백")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기", action: onClose)
                }
            }
        }
    }

    @ViewBuilder
    private func replyRow(_ reply: FeedbackReply) -> some View {
        switch reply.kind {
        case .recording:
            let patch = reply.patchId.flatMap(patchForId)
            HStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("\(FeedbackPeople.name(of: reply.author, tracks: tracks)) 재녹음")
                            .font(.subheadline.weight(.semibold))
                        if let patch { Text(versionLabel(patch)).font(.caption).foregroundStyle(.secondary) }
                        if reply.id == lastRecordingId && item.isAwaitingComment {
                            Text("코멘트 요청")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Color.blue.opacity(0.2)))
                                .foregroundStyle(.blue)
                        }
                    }
                    if !reply.text.isEmpty { Text(reply.text) }
                    Text(reply.createdAt, format: .dateTime.month().day().hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
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
            }
        case .comment:
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "text.bubble")
                    Text(FeedbackPeople.name(of: reply.author, tracks: tracks)).font(.subheadline.weight(.semibold))
                }
                Text(reply.text)
                Text(reply.createdAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
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
                            if item.isAwaitingComment {
                                Label("코멘트 요청", systemImage: "waveform")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.blue)
                            } else if !item.replies.isEmpty {
                                Text("답변 \(item.replies.count)").font(.caption).foregroundStyle(.secondary)
                            }
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
