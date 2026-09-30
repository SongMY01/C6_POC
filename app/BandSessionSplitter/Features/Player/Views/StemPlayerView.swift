import SwiftUI
import PDFKit
import PencilKit

/// GarageBand 트랙 뷰 형태의 멀티트랙 플레이어.
/// 위: 트랜스포트 바 / 왼쪽: 트랙 헤더(뮤트·솔로·볼륨) / 오른쪽: 눈금자 + 트랙별 파형 레인 + 재생헤드.
/// 구간반복은 노란 영역, 피드백은 눈금자 위 깃발, 재녹음 패치는 레인 위 블록으로 표시한다.
struct StemPlayerView: View {
    @ObservedObject var controller: StemPlayerController
    let onReset: () -> Void

    @StateObject private var scoreSync = ScoreSyncController()
    @StateObject private var feedbackStore = FeedbackStore()
    @StateObject private var patchStore = PatchStore()
    @State private var pdfDocument: PDFDocument?
    @State private var showingFeedbackComposer = false
    @State private var showingScore = false
    @State private var selectedTrackId: String?
    @State private var recordingTrackId: String?
    @State private var recordingError: String?
    @State private var zoom: CGFloat = 1
    @State private var selectedRegion: RegionSelection?
    /// 선택된 패치 블록 (선택 = 켜져서 들리는 상태). 선택되면 옮기기·자르기가 가능하다.
    @State private var selectedPatch: PatchSelection?

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

    private let headerWidth: CGFloat = 280
    private let laneHeight: CGFloat = 104
    private let rulerHeight: CGFloat = 52

    private var currentPage: Int {
        scoreSync.pageIndex(for: controller.currentTime)
    }

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
                trackArea
            }
        }
        .background(GB.background)
        .environment(\.colorScheme, .dark)
        .overlay(alignment: .bottom) { bottomBanners }
        .onAppear {
            loadPDFIfNeeded()
            if selectedTrackId == nil { selectedTrackId = controller.tracks.first?.id }
        }
        .onChange(of: controller.loopRegion) { _, newRegion in
            selectLatestPatchByDefault(for: newRegion)
        }
        .sheet(isPresented: $showingFeedbackComposer) {
            if let region = controller.loopRegion {
                FeedbackComposerSheet(
                    page: currentPage,
                    timeRange: region,
                    document: pdfDocument,
                    onSave: { drawing in
                        feedbackStore.addFeedback(page: currentPage, timeRange: region, drawing: drawing)
                        showingFeedbackComposer = false
                    },
                    onCancel: { showingFeedbackComposer = false }
                )
            }
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

            Button { showingFeedbackComposer = true } label: {
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
                                        versionLabel: { "패치 v\(patchStore.versionNumber(of: $0))" },
                                        onTapPatch: { tapPatch($0, for: track) },
                                        selectedPatchId: selectedPatch?.trackId == track.id ? selectedPatch?.patchId : nil,
                                        onMovePatch: { if let p = controller.movePreviewPatch(of: track, to: $0) { patchStore.update(p) } },
                                        onTrimPatchStart: { if let p = controller.trimPreviewPatchStart(of: track, to: $0) { patchStore.update(p) } },
                                        onTrimPatchEnd: { if let p = controller.trimPreviewPatchEnd(of: track, to: $0) { patchStore.update(p) } },
                                        selectedRegionId: selectedRegion?.trackId == track.id ? selectedRegion?.regionId : nil,
                                        onSelectRegion: { id in
                                            selectedTrackId = track.id
                                            selectedPatch = nil
                                            selectedRegion = RegionSelection(trackId: track.id, regionId: id)
                                        },
                                        onMoveRegion: { controller.moveRegion($0, in: track, to: $1) },
                                        onTrimRegionStart: { controller.trimRegionStart($0, in: track, to: $1) },
                                        onTrimRegionEnd: { controller.trimRegionEnd($0, in: track, to: $1) }
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

            ForEach(feedbackStore.items) { item in
                Button {
                    controller.loopRegion = item.timeRange
                    controller.isLoopEnabled = true
                    controller.seek(to: item.startTime)
                } label: {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.orange)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("피드백 삭제", role: .destructive) { feedbackStore.delete(item) }
                }
                .offset(x: CGFloat(item.startTime) * pxPerSec - 4, y: rulerHeight - 22)
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
               let patch = track.previewPatch, patch.id == selectedPatch.patchId {
                HStack(spacing: 10) {
                    Text("\(track.displayName) 패치 v\(patchStore.versionNumber(of: patch)) · \(formatTime(patch.startTime))~\(formatTime(patch.endTime))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                    Button {
                        controller.setPreviewPatch(nil, fileURL: nil, for: track)
                        self.selectedPatch = nil
                    } label: { Label("끄기", systemImage: "speaker.slash") }
                    Button(role: .destructive) {
                        controller.setPreviewPatch(nil, fileURL: nil, for: track)
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
                    Text("방금 녹음 — \(track.displayName) \(formatTime(pending.region.lowerBound))~\(formatTime(pending.region.upperBound))")
                        .font(.subheadline.weight(.semibold))
                    Button("들어보기") { controller.previewPendingRecording() }
                        .buttonStyle(.bordered)
                    Button("저장") { savePendingRecording(for: track) }
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
            }
        }
    }

    /// 패치 블록 탭: 꺼져 있으면 켜고 선택(옮기기·자르기 가능), 선택된 걸 다시 탭하면 끈다.
    private func tapPatch(_ patch: Patch, for track: StemTrack) {
        if selectedPatch?.patchId == patch.id {
            controller.setPreviewPatch(nil, fileURL: nil, for: track)
            selectedPatch = nil
            return
        }
        if track.previewPatch?.id != patch.id {
            controller.setPreviewPatch(patch, fileURL: patchStore.fileURL(for: patch), for: track)
        }
        guard track.previewPatch?.id == patch.id else { return }
        selectedTrackId = track.id
        selectedRegion = nil
        selectedPatch = PatchSelection(trackId: track.id, patchId: patch.id)
    }

    /// 구간이 바뀌었을 때, 그 구간에 패치가 있고 아직 아무것도 선택 안 된 트랙은
    /// 최신 패치를 기본값으로 자동 선택한다.
    private func selectLatestPatchByDefault(for region: ClosedRange<TimeInterval>?) {
        guard let region else { return }
        for track in controller.tracks {
            guard track.previewPatch == nil else { continue }
            guard let latest = patchStore.patches(sessionId: track.id, region: region).first else { continue }
            controller.setPreviewPatch(latest, fileURL: patchStore.fileURL(for: latest), for: track)
        }
    }

    private func savePendingRecording(for track: StemTrack) {
        guard let pending = controller.pendingRecording, pending.trackId == track.id else { return }
        do {
            let patch = try patchStore.addPatch(sessionId: track.id, timeRange: pending.region, tempFileURL: pending.tempURL)
            controller.clearPendingRecording()
            controller.setPreviewPatch(patch, fileURL: patchStore.fileURL(for: patch), for: track)
        } catch {
            recordingError = "패치 저장 실패: \(error.localizedDescription)"
        }
    }

    private func loadPDFIfNeeded() {
        guard pdfDocument == nil else { return }
        if let url = Bundle.main.url(forResource: scoreSync.song.pdfResourceName, withExtension: "pdf") {
            pdfDocument = PDFDocument(url: url)
        }
    }
}

