import SwiftUI

/// GarageBand 트랙 뷰 형태의 멀티트랙 플레이어.
/// 위: 트랜스포트 바 / 왼쪽: 트랙 헤더(뮤트·솔로·볼륨) / 오른쪽: 눈금자 + 트랙별 파형 레인 + 재생헤드.
/// 구간반복은 노란 영역, 피드백은 눈금자 위 깃발(받는 세션 레인에는 말풍선), 재녹음 패치는 레인 위 블록으로 표시한다.
struct StemPlayerView: View {
    @ObservedObject var controller: StemPlayerController
    let onReset: () -> Void

    @StateObject private var scoreSync = ScoreSyncController()
    @StateObject private var feedbackStore = FeedbackStore()
    @StateObject private var patchStore = PatchStore()
    @State private var showingScore = false
    /// 트랙(파형) 대신 피드백 목록 화면을 보여줄지.
    @State private var showingFeedbackBoard = false
    @State private var selectedTrackId: String?
    @State private var recordingTrackId: String?
    @State private var recordingError: String?
    @State private var zoom: CGFloat = 1
    @State private var selectedRegion: RegionSelection?
    /// 선택된 패치 블록 (선택 = 켜져서 들리는 상태). 선택되면 옮기기·자르기가 가능하다.
    @State private var selectedPatch: PatchSelection?
    /// 지금 열려 있는(구간 반복이 잡힌) 피드백 — 깃발 강조용.
    @State private var selectedFeedbackId: UUID?
    @State private var activeSheet: FeedbackSheet?
    /// "녹음으로 답하기"로 시작한 녹음이면, 저장할 때 이 피드백 스레드에 올린다.
    @State private var replyingToFeedbackId: UUID?
    /// 피드백 화면에서 원본/시도 비교로 패치 구성을 임시로 바꾼 트랙들.
    /// 시트를 닫으면 이 트랙들을 곡에 반영된(채택된) 버전으로 되돌린다.
    @State private var comparedTrackIds: Set<String> = []

    private enum FeedbackSheet: Identifiable {
        case compose
        case thread(UUID)
        /// 겹치거나 붙어 있는 피드백 묶음에서 고르기
        case picker([UUID])

        var id: String {
            switch self {
            case .compose: return "compose"
            case .thread(let id): return "thread-\(id)"
            case .picker(let ids): return "picker-\(ids.map(\.uuidString).joined())"
            }
        }
    }

    private struct PatchSelection: Equatable {
        let trackId: String
        let patchId: UUID
    }

    private struct RegionSelection: Equatable {
        let trackId: String
        let regionId: UUID
    }

    private var selectedRegionTrack: StemTrack? {
        guard let selectedRegion else { return nil }
        return controller.tracks.first { $0.id == selectedRegion.trackId }
    }

    /// 재생헤드가 선택된 리전 안쪽에 있어야 분할할 수 있다.
    private var canSplitSelectedRegion: Bool {
        guard let selectedRegion, let track = selectedRegionTrack,
              let region = track.regions.first(where: { $0.id == selectedRegion.regionId }) else { return false }
        let t = controller.currentTime
        return t > region.timelineStart + TimelineEditing.minLength
            && t < region.timelineEnd - TimelineEditing.minLength
    }

    /// 피드백 버튼 배지 숫자 = 이 iPad 사람이 지금 해야 할 일.
    /// 리더: 코멘트를 기다리는 시도 수 / 세션 연주자: 내 세션의 "연습 필요" 수.
    private var awaitingCommentCount: Int {
        if DeviceRole.isLeader {
            return feedbackStore.items.filter { $0.status == .awaitingComment }.count
        }
        return feedbackStore.items.filter {
            $0.status == .needsPractice && $0.isFor(sessionId: DeviceRole.current)
        }.count
    }

    private let headerWidth: CGFloat = 280
    private let laneHeight: CGFloat = 104
    private let rulerHeight: CGFloat = 52

    var body: some View {
        VStack(spacing: 0) {
            transportBar
            Divider().overlay(Color.black)
            HStack(spacing: 0) {
                if showingScore {
                    ScoreView(scoreSync: scoreSync, currentTime: controller.currentTime)
                        .frame(width: 420)
                        .background(Color(white: 0.95))
                        .environment(\.colorScheme, .light)
                    Divider().overlay(Color.black)
                }
                if showingFeedbackBoard {
                    FeedbackBoardView(
                        items: feedbackStore.items,
                        tracks: controller.tracks,
                        currentTime: controller.currentTime,
                        onOpen: { openFeedback($0) },
                        onCompose: controller.loopRegion == nil ? nil : { activeSheet = .compose }
                    )
                } else {
                    trackArea
                }
            }
        }
        .background(GB.background)
        .environment(\.colorScheme, .dark)
        .overlay(alignment: .bottom) { bottomBanners }
        .onAppear {
            if selectedTrackId == nil {
                // 세션 연주자의 iPad는 자기 트랙을 선택해 둔다 (● 녹음 버튼이 바로 내 세션을 녹음)
                selectedTrackId = controller.tracks.first { $0.id == DeviceRole.current }?.id ?? controller.tracks.first?.id
            }
            activateAdoptedPatches()
            SyncClient.shared.attach(
                feedback: { feedbackStore.replaceAll($0) },
                patches: { applyRemotePatches($0) },
                audioURL: { patchStore.fileURL(for: $0) }
            )
        }
        .onDisappear { SyncClient.shared.detach() }
        .onChange(of: controller.loopRegion) { _, newRegion in
            selectLatestPatchByDefault(for: newRegion)
        }
        .sheet(item: $activeSheet, onDismiss: {
            restoreComparedTracks()
        }) { sheet in
            feedbackSheet(sheet)
        }
    }

    // MARK: - 트랜스포트 바

    private var transportBar: some View {
        HStack(spacing: 10) {
            Button(action: onReset) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(GBToolButtonStyle())

            Button { showingScore.toggle() } label: {
                Image(systemName: "music.note.list")
            }
            .buttonStyle(GBToolButtonStyle(isOn: showingScore))

            Button { showingFeedbackBoard.toggle() } label: {
                HStack(spacing: 4) {
                    Image(systemName: showingFeedbackBoard ? "waveform" : "text.bubble")
                    if !showingFeedbackBoard, awaitingCommentCount > 0 {
                        Text("\(awaitingCommentCount)")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 5)
                            .background(Capsule().fill(Color.cyan))
                            .foregroundStyle(.black)
                    }
                }
            }
            .buttonStyle(GBToolButtonStyle(isOn: showingFeedbackBoard, onColor: .orange))

            VStack(alignment: .leading, spacing: 2) {
                Text(DeviceRole.label(for: DeviceRole.current))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                SyncStatusLabel(compact: true)
            }
            .fixedSize()

            Spacer(minLength: 8)

            HStack(spacing: 2) {
                Button { controller.seek(to: controller.loopRegion?.lowerBound ?? 0) } label: {
                    Image(systemName: "backward.end.fill")
                }
                .buttonStyle(GBTransportButtonStyle())

                Button { controller.togglePlayPause() } label: {
                    Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(GBTransportButtonStyle())

                Button(action: recordTapped) {
                    Image(systemName: controller.isRecording ? "stop.fill" : "circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(GBTransportButtonStyle())
                .disabled(!canRecord && !controller.isRecording)
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(GB.panel))

            Button {
                let newValue = !controller.isLoopEnabled
                if newValue { controller.ensureLoopRegion() }
                controller.isLoopEnabled = newValue
            } label: {
                Image(systemName: "repeat")
            }
            .buttonStyle(GBToolButtonStyle(isOn: controller.isLoopEnabled, onColor: GB.cycle))

            HStack(spacing: 6) {
                Button("시작") { controller.markLoopStart() }
                Button("끝") { controller.markLoopEnd() }
                if controller.loopRegion != nil {
                    Button { controller.clearLoop() } label: { Image(systemName: "xmark") }
                }
            }
            .buttonStyle(GBToolButtonStyle())

            Text("\(formatTime(controller.currentTime)) / \(formatTime(controller.duration))")
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(GB.panel))

            Spacer(minLength: 8)

            Button { activeSheet = .compose } label: {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(GBToolButtonStyle())
            .disabled(controller.loopRegion == nil)

            HStack(spacing: 2) {
                Button { zoom = max(1, zoom / 1.5) } label: { Image(systemName: "minus.magnifyingglass") }
                Button { zoom = min(12, zoom * 1.5) } label: { Image(systemName: "plus.magnifyingglass") }
            }
            .buttonStyle(GBToolButtonStyle())
        }
        .font(.system(size: 17, weight: .semibold))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(GB.toolbar)
    }

    // MARK: - 트랙 영역 (헤더 + 타임라인)

    private var trackArea: some View {
        GeometryReader { geo in
            let timelineWidth = max(geo.size.width - headerWidth, 100)
            let duration = max(controller.duration, 0.01)
            let pxPerSec = timelineWidth / duration * zoom
            let contentWidth = duration * pxPerSec
            let trackCount = CGFloat(max(controller.tracks.count, 1))
            let laneHeight = max(self.laneHeight, (geo.size.height - rulerHeight) / trackCount)

            ScrollView(.vertical, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: rulerHeight)
                        ForEach(controller.tracks) { track in
                            TrackHeader(
                                track: track,
                                isSolo: controller.soloTrackId == track.id,
                                isSelected: selectedTrackId == track.id,
                                isRecording: recordingTrackId == track.id,
                                onSelect: { selectedTrackId = track.id },
                                onSolo: { controller.setSolo(track.id) }
                            )
                            .frame(height: laneHeight)
                        }
                    }
                    .frame(width: headerWidth)
                    .background(GB.headerColumn)

                    ScrollView(.horizontal, showsIndicators: true) {
                        ZStack(alignment: .topLeading) {
                            VStack(spacing: 0) {
                                ruler(pxPerSec: pxPerSec, width: contentWidth)
                                ForEach(controller.tracks) { track in
                                    TrackLane(
                                        track: track,
                                        pxPerSec: pxPerSec,
                                        width: contentWidth,
                                        height: laneHeight,
                                        loopRegion: controller.loopRegion,
                                        isLoopEnabled: controller.isLoopEnabled,
                                        isSelected: selectedTrackId == track.id,
                                        patches: patchStore.patches(sessionId: track.id),
                                        versionLabel: { "\($0.isAdopted ? "✓ " : "")패치 v\(patchStore.versionNumber(of: $0))" },
                                        onTapPatch: { tapPatch($0, for: track) },
                                        selectedPatchId: selectedPatch?.trackId == track.id ? selectedPatch?.patchId : nil,
                                        onMovePatch: { t in editSelectedPatch(in: track) { id in controller.movePatch(id, of: track, to: t) } },
                                        onTrimPatchStart: { t in editSelectedPatch(in: track) { id in controller.trimPatchStart(id, of: track, to: t) } },
                                        onTrimPatchEnd: { t in editSelectedPatch(in: track) { id in controller.trimPatchEnd(id, of: track, to: t) } },
                                        selectedRegionId: selectedRegion?.trackId == track.id ? selectedRegion?.regionId : nil,
                                        onSelectRegion: { id in
                                            selectedTrackId = track.id
                                            selectedPatch = nil
                                            selectedRegion = RegionSelection(trackId: track.id, regionId: id)
                                        },
                                        onMoveRegion: { controller.moveRegion($0, in: track, to: $1) },
                                        onTrimRegionStart: { controller.trimRegionStart($0, in: track, to: $1) },
                                        onTrimRegionEnd: { controller.trimRegionEnd($0, in: track, to: $1) },
                                        feedbacks: feedbackStore.items.filter { $0.targetSessionIds.contains(track.id) },
                                        selectedFeedbackId: selectedFeedbackId,
                                        onTapFeedbackCluster: { openCluster($0) }
                                    )
                                    .frame(height: laneHeight)
                                    .onTapGesture {
                                        selectedTrackId = track.id
                                        selectedRegion = nil
                                        selectedPatch = nil
                                    }
                                }
                            }
                            playhead(pxPerSec: pxPerSec, height: rulerHeight + laneHeight * CGFloat(controller.tracks.count))
                        }
                        .frame(width: contentWidth)
                    }
                }
            }
        }
    }

    private func ruler(pxPerSec: CGFloat, width: CGFloat) -> some View {
        let step = rulerStep(pxPerSec: pxPerSec)
        let tickCount = Int(controller.duration / step) + 1
        return ZStack(alignment: .topLeading) {
            GB.ruler

            if let region = controller.loopRegion {
                RoundedRectangle(cornerRadius: 4)
                    .fill(GB.cycle.opacity(controller.isLoopEnabled ? 0.9 : 0.35))
                    .frame(width: max(4, CGFloat(region.upperBound - region.lowerBound) * pxPerSec), height: 10)
                    .offset(x: CGFloat(region.lowerBound) * pxPerSec, y: 2)
            }

            ForEach(0..<tickCount, id: \.self) { i in
                let t = Double(i) * step
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatTime(t))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                    Rectangle().fill(Color.white.opacity(0.4)).frame(width: 1, height: 10)
                }
                .offset(x: CGFloat(t) * pxPerSec + 4, y: 14)
            }

            // 겹치거나 가까운 피드백은 깃발 하나에 개수를 붙여 묶는다 (확대하면 풀림).
            ForEach(FeedbackCluster.make(feedbackStore.items, pxPerSec: pxPerSec, minSpacing: 30)) { cluster in
                Button { openCluster(cluster) } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "flag.fill")
                        if !cluster.isSingle {
                            Text("\(cluster.items.count)").font(.system(size: 11, weight: .bold))
                        }
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(cluster.items.contains { $0.id == selectedFeedbackId } ? Color.white
                                     : cluster.status.timelineColor)
                    .padding(4)
                }
                .buttonStyle(.plain)
                .offset(x: CGFloat(cluster.start) * pxPerSec - 4, y: rulerHeight - 22)
            }
        }
        .frame(width: width, height: rulerHeight, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0).onEnded { value in
                controller.seek(to: Double(max(0, value.location.x) / pxPerSec))
            }
        )
    }

    private func playhead(pxPerSec: CGFloat, height: CGFloat) -> some View {
        let x = CGFloat(controller.currentTime) * pxPerSec
        return ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.white)
                .frame(width: 1.5, height: height)
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color(white: 0.8))
                .offset(y: rulerHeight - 16)
        }
        .offset(x: x - 7)
        .frame(width: 14, alignment: .top)
        .allowsHitTesting(false)
    }

    /// 눈금 간격(초) — 눈금 사이가 최소 70px은 되도록 고른다.
    private func rulerStep(pxPerSec: CGFloat) -> Double {
        let candidates: [Double] = [1, 2, 5, 10, 15, 30, 60]
        return candidates.first { CGFloat($0) * pxPerSec >= 70 } ?? 120
    }

    // MARK: - 하단 배너 (녹음 확인 / 에러 / 안내)

    @ViewBuilder
    private var bottomBanners: some View {
        VStack(spacing: 8) {
            if let selectedRegion, let track = selectedRegionTrack {
                HStack(spacing: 10) {
                    Text("\(track.displayName) 리전")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                    Button {
                        if let (left, _) = controller.splitRegion(in: track, at: controller.currentTime) {
                            self.selectedRegion = RegionSelection(trackId: track.id, regionId: left)
                        }
                    } label: { Label("재생헤드에서 분할", systemImage: "scissors") }
                    .disabled(!canSplitSelectedRegion)
                    Button(role: .destructive) {
                        controller.deleteRegion(selectedRegion.regionId, in: track)
                        self.selectedRegion = nil
                    } label: { Label("삭제", systemImage: "trash") }
                    Button {
                        controller.resetRegions(of: track)
                        self.selectedRegion = nil
                    } label: { Label("원래대로", systemImage: "arrow.uturn.backward") }
                    Button("완료") { self.selectedRegion = nil }
                }
                .buttonStyle(GBToolButtonStyle())
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 14).fill(GB.toolbar))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(GB.cycle.opacity(0.6), lineWidth: 1))
            }
            if let selectedPatch,
               let track = controller.tracks.first(where: { $0.id == selectedPatch.trackId }),
               let patch = track.activePatch(id: selectedPatch.patchId) {
                let isAdopted = patchStore.patch(id: patch.id)?.isAdopted == true
                HStack(spacing: 10) {
                    Text("\(track.displayName) 패치 v\(patchStore.versionNumber(of: patch)) · \(formatTime(patch.startTime))~\(formatTime(patch.endTime))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                    Button {
                        patchStore.setAdopted(!isAdopted, patchId: patch.id)
                    } label: {
                        Label(isAdopted ? "반영 해제" : "곡에 반영", systemImage: isAdopted ? "checkmark.seal.fill" : "checkmark.seal")
                    }
                    Button {
                        controller.deactivatePatch(patch.id, for: track)
                        self.selectedPatch = nil
                    } label: { Label("끄기", systemImage: "speaker.slash") }
                    Button(role: .destructive) {
                        controller.deactivatePatch(patch.id, for: track)
                        patchStore.delete(patch)
                        self.selectedPatch = nil
                    } label: { Label("삭제", systemImage: "trash") }
                    Button("완료") { self.selectedPatch = nil }
                }
                .buttonStyle(GBToolButtonStyle())
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 14).fill(GB.toolbar))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.red.opacity(0.7), lineWidth: 1))
            }
            if let pending = controller.pendingRecording,
               let track = controller.tracks.first(where: { $0.id == pending.trackId }) {
                HStack(spacing: 12) {
                    Text("\(replyingToFeedbackId != nil ? "피드백 답변 녹음" : "방금 녹음") — \(track.displayName) \(formatTime(pending.region.lowerBound))~\(formatTime(pending.region.upperBound))")
                        .font(.subheadline.weight(.semibold))
                    Button("들어보기") { controller.previewPendingRecording() }
                        .buttonStyle(.bordered)
                    Button(replyingToFeedbackId != nil ? "올리고 코멘트 요청" : "저장") { savePendingRecording(for: track) }
                        .buttonStyle(.borderedProminent)
                    Button("다시 녹음", role: .destructive) { controller.discardPendingRecording() }
                        .buttonStyle(.bordered)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(GB.panel))
            } else if controller.isRecording {
                Text("● 녹음 중 — 준비 시간(2초) 뒤부터 녹음됩니다. 다시 ■를 누르면 멈춥니다.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(GB.panel))
            }

            if let recordingError {
                Text(recordingError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(GB.panel))
                    .onTapGesture { self.recordingError = nil }
            }
        }
        .padding(.bottom, 20)
    }

    // MARK: - 동작

    /// 피드백 깃발·말풍선 탭: 그 구간을 구간반복으로 잡고 스레드를 연다.
    private func openFeedback(_ item: FeedbackItem) {
        selectedRegion = nil
        selectedPatch = nil
        selectedFeedbackId = item.id
        controller.loopRegion = item.timeRange
        controller.isLoopEnabled = true
        controller.seek(to: item.startTime)
        activeSheet = .thread(item.id)
    }

    /// 하나면 바로 열고, 여러 개가 묶여 있으면 목록에서 고르게 한다.
    private func openCluster(_ cluster: FeedbackCluster) {
        if cluster.isSingle {
            openFeedback(cluster.items[0])
        } else {
            activeSheet = .picker(cluster.items.map(\.id))
        }
    }

    private func deleteFeedback(_ item: FeedbackItem) {
        if selectedFeedbackId == item.id { selectedFeedbackId = nil }
        feedbackStore.delete(item)
    }

    // MARK: - 피드백 시트 (작성 / 스레드 / 묶음 목록)

    @ViewBuilder
    private func feedbackSheet(_ sheet: FeedbackSheet) -> some View {
        switch sheet {
        case .compose:
            if let region = controller.loopRegion {
                FeedbackComposerSheet(
                    timeRange: region,
                    tracks: controller.tracks,
                    onSave: { text, targets in
                        let item = feedbackStore.addFeedback(timeRange: region, text: text, targetSessionIds: targets)
                        selectedFeedbackId = item.id
                        activeSheet = nil
                    },
                    onCancel: { activeSheet = nil }
                )
            }
        case .picker(let ids):
            FeedbackPickerSheet(
                items: ids.compactMap { feedbackStore.item(id: $0) },
                tracks: controller.tracks,
                onSelect: { openFeedback($0) },
                onClose: { activeSheet = nil }
            )
        case .thread(let id):
            if let item = feedbackStore.item(id: id) {
                FeedbackThreadSheet(
                    item: item,
                    tracks: controller.tracks,
                    patchForId: { pid in patchStore.patches.first { $0.id == pid } },
                    attachablePatches: attachablePatches(for: item),
                    versionLabel: { "v\(patchStore.versionNumber(of: $0))" },
                    comparisonSelection: { sessionId in comparisonSelection(for: item, sessionId: sessionId) },
                    onCompare: { sessionId, patch in compare(sessionId: sessionId, patch: patch, feedback: item) },
                    onRecordAttempt: { recordReply(to: item, sessionId: $0) },
                    onAttachPatch: { feedbackStore.addAttempt(patch: $0, to: item.id) },
                    onComment: { text, author, attemptId in
                        feedbackStore.addComment(text, author: author, to: item.id, attemptId: attemptId)
                    },
                    onDeleteComment: { feedbackStore.deleteComment($0, from: item.id) },
                    onDeleteAttempt: { feedbackStore.deleteAttempt($0, from: item.id) },
                    onSetPassed: { setPassed($0, feedback: item) },
                    onDeleteFeedback: {
                        deleteFeedback(item)
                        activeSheet = nil
                    },
                    onClose: { activeSheet = nil }
                )
            }
        }
    }

    /// 답변으로 올릴 수 있는 기존 패치: 받는 세션의 패치 중 피드백 구간과 겹치고 아직 안 올린 것.
    private func attachablePatches(for item: FeedbackItem) -> [Patch] {
        let attached = Set(item.attempts.map(\.patchId))
        return patchStore.patches.filter {
            item.isFor(sessionId: $0.sessionId)
                && $0.startTime < item.endTime && $0.endTime > item.startTime
                && !attached.contains($0.id)
        }
    }

    /// 비교 듣기에서 지금 선택된 것: 그 세션 트랙에 켜진 시도 패치 id (없으면 nil = 원본).
    private func comparisonSelection(for feedback: FeedbackItem, sessionId: String) -> UUID? {
        guard let track = controller.tracks.first(where: { $0.id == sessionId }) else { return nil }
        return feedback.attempts.first { $0.sessionId == sessionId && track.isActive($0.patchId) }?.patchId
    }

    /// 원본(patch == nil) 또는 특정 시도로 바꿔 끼우고, 피드백 구간을 반복 재생한다.
    /// 재생 중이면 그 트랙만 다시 맞추므로 끊기지 않고 바로 비교된다.
    private func compare(sessionId: String, patch: Patch?, feedback: FeedbackItem) {
        guard let track = controller.tracks.first(where: { $0.id == sessionId }) else { return }
        comparedTrackIds.insert(sessionId)
        if let patch {
            controller.activatePatch(patch, fileURL: patchStore.fileURL(for: patch), for: track)
        } else {
            for active in track.activePatches
            where active.startTime < feedback.endTime && active.endTime > feedback.startTime {
                controller.deactivatePatch(active.id, for: track)
            }
        }
        if controller.loopRegion != feedback.timeRange || !controller.isPlaying {
            controller.loopRegion = feedback.timeRange
            controller.isLoopEnabled = true
            controller.seek(to: feedback.startTime)
            if !controller.isPlaying { controller.play() }
        }
    }

    /// 통과 처리하면 그 시도의 녹음을 곡에 반영(채택)하고 바로 켠다.
    /// 다시 열면 반영했던 녹음을 해제하고 원본으로 돌린다.
    private func setPassed(_ attemptId: UUID?, feedback: FeedbackItem) {
        if let previous = feedback.attempts.first(where: { $0.id == feedback.passedAttemptId }) {
            patchStore.setAdopted(false, patchId: previous.patchId)
            if let track = controller.tracks.first(where: { $0.id == previous.sessionId }) {
                controller.deactivatePatch(previous.patchId, for: track)
            }
        }
        feedbackStore.setPassed(attemptId, for: feedback.id)
        guard let attempt = feedback.attempts.first(where: { $0.id == attemptId }),
              let patch = patchStore.patch(id: attempt.patchId),
              let track = controller.tracks.first(where: { $0.id == attempt.sessionId }) else { return }
        patchStore.setAdopted(true, patchId: patch.id)
        controller.activatePatch(patch, fileURL: patchStore.fileURL(for: patch), for: track)
    }

    /// 다른 기기에서 바뀐 패치 목록을 반영하고, 재생 중인 패치 구성을 맞춘다.
    /// - 삭제된 패치는 끄고, 위치가 바뀐 패치는 새 위치로 다시 켠다.
    /// - 새로 곡에 반영(채택)된 패치는 켜고, 반영이 해제된 패치는 끈다.
    private func applyRemotePatches(_ remote: [Patch]) {
        let before = Dictionary(patchStore.patches.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        patchStore.replaceAll(remote)
        let after = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for track in controller.tracks {
            for active in track.activePatches {
                guard let updated = after[active.id] else {
                    controller.deactivatePatch(active.id, for: track)
                    continue
                }
                let wasAdopted = before[active.id]?.isAdopted == true
                if wasAdopted && !updated.isAdopted && !comparedTrackIds.contains(track.id) {
                    controller.deactivatePatch(active.id, for: track)
                } else if updated.startTime != active.startTime || updated.endTime != active.endTime
                            || updated.sourceStart != active.sourceStart {
                    controller.deactivatePatch(active.id, for: track)
                    controller.activatePatch(updated, fileURL: patchStore.fileURL(for: updated), for: track)
                }
            }
            for patch in remote where patch.sessionId == track.id && patch.isAdopted && before[patch.id]?.isAdopted != true {
                controller.activatePatch(patch, fileURL: patchStore.fileURL(for: patch), for: track)
            }
        }
    }

    /// 곡에 반영된(채택된) 패치를 모두 켠다. 곡을 열 때와 비교 듣기를 마쳤을 때 호출한다.
    private func activateAdoptedPatches() {
        for track in controller.tracks {
            for patch in patchStore.adoptedPatches(sessionId: track.id) {
                controller.activatePatch(patch, fileURL: patchStore.fileURL(for: patch), for: track)
            }
        }
    }

    /// 비교 듣기로 바꿨던 트랙을 곡 기본 상태로: 채택 안 된 패치는 끄고, 채택된 패치를 켠다.
    private func restoreComparedTracks() {
        for track in controller.tracks where comparedTrackIds.contains(track.id) {
            let adopted = patchStore.adoptedPatches(sessionId: track.id)
            for active in track.activePatches where !adopted.contains(where: { $0.id == active.id }) {
                controller.deactivatePatch(active.id, for: track)
            }
            for patch in adopted {
                controller.activatePatch(patch, fileURL: patchStore.fileURL(for: patch), for: track)
            }
        }
        comparedTrackIds.removeAll()
    }

    /// 선택된 패치 블록을 옮기거나 자른 뒤, 바뀐 위치를 저장한다.
    private func editSelectedPatch(in track: StemTrack, _ edit: (UUID) -> Patch?) {
        guard let selectedPatch, selectedPatch.trackId == track.id,
              let changed = edit(selectedPatch.patchId) else { return }
        patchStore.updatePlacement(changed)
    }

    /// 피드백 구간을 그 세션으로 바로 녹음 시작. 저장하면 스레드에 올라간다.
    private func recordReply(to item: FeedbackItem, sessionId: String) {
        activeSheet = nil
        replyingToFeedbackId = item.id
        selectedTrackId = sessionId
        selectedFeedbackId = item.id
        controller.loopRegion = item.timeRange
        // 시트가 내려간 뒤 녹음을 시작해야 준비 시간(카운트인)을 화면에서 볼 수 있다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard !controller.isRecording, controller.pendingRecording == nil else { return }
            recordTapped()
        }
    }

    private var canRecord: Bool {
        selectedTrackId != nil && controller.loopRegion != nil && controller.pendingRecording == nil
    }

    private func recordTapped() {
        if controller.isRecording {
            controller.stopPatchRecording()
            recordingTrackId = nil
            return
        }
        guard let region = controller.loopRegion,
              let track = controller.tracks.first(where: { $0.id == selectedTrackId }) else { return }
        recordingError = nil
        recordingTrackId = track.id
        Task {
            do {
                try await controller.startPatchRecording(target: track, region: region)
            } catch {
                recordingTrackId = nil
                recordingError = "녹음 시작 실패: \(error.localizedDescription)"
                replyingToFeedbackId = nil
            }
        }
    }

    /// 패치 블록 탭: 꺼져 있으면 켜고 선택(옮기기·자르기 가능), 선택된 걸 다시 탭하면 끈다.
    private func tapPatch(_ patch: Patch, for track: StemTrack) {
        if selectedPatch?.patchId == patch.id {
            controller.deactivatePatch(patch.id, for: track)
            selectedPatch = nil
            return
        }
        controller.activatePatch(patch, fileURL: patchStore.fileURL(for: patch), for: track)
        guard track.isActive(patch.id) else { return }
        selectedTrackId = track.id
        selectedRegion = nil
        selectedPatch = PatchSelection(trackId: track.id, patchId: patch.id)
    }

    /// 구간이 바뀌었을 때, 그 구간에 패치가 있고 아직 아무것도 선택 안 된 트랙은
    /// 최신 패치를 기본값으로 자동 선택한다.
    private func selectLatestPatchByDefault(for region: ClosedRange<TimeInterval>?) {
        guard let region else { return }
        for track in controller.tracks {
            let hasPatchHere = track.activePatches.contains {
                $0.startTime < region.upperBound && $0.endTime > region.lowerBound
            }
            guard !hasPatchHere else { continue }
            guard let latest = patchStore.patches(sessionId: track.id, region: region).first else { continue }
            controller.activatePatch(latest, fileURL: patchStore.fileURL(for: latest), for: track)
        }
    }

    private func savePendingRecording(for track: StemTrack) {
        guard let pending = controller.pendingRecording, pending.trackId == track.id else { return }
        do {
            let patch = try patchStore.addPatch(sessionId: track.id, timeRange: pending.region, tempFileURL: pending.tempURL)
            controller.clearPendingRecording()
            controller.activatePatch(patch, fileURL: patchStore.fileURL(for: patch), for: track)
            if let feedbackId = replyingToFeedbackId {
                replyingToFeedbackId = nil
                feedbackStore.addAttempt(patch: patch, to: feedbackId)
                activeSheet = .thread(feedbackId)
            }
        } catch {
            recordingError = "패치 저장 실패: \(error.localizedDescription)"
        }
    }
}

