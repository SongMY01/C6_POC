import SwiftUI

// MARK: - 트랙 레인 (리전 + 구간 표시 + 패치 블록)

struct TrackLane: View {
    @ObservedObject var track: StemTrack
    let pxPerSec: CGFloat
    let width: CGFloat
    let height: CGFloat
    let loopRegion: ClosedRange<TimeInterval>?
    let isLoopEnabled: Bool
    let isSelected: Bool

    let patches: [Patch]
    let versionLabel: (Patch) -> String
    let onTapPatch: (Patch) -> Void
    let selectedPatchId: UUID?
    let onMovePatch: (TimeInterval) -> Void
    let onTrimPatchStart: (TimeInterval) -> Void
    let onTrimPatchEnd: (TimeInterval) -> Void

    let selectedRegionId: UUID?
    let onSelectRegion: (UUID) -> Void
    let onMoveRegion: (UUID, TimeInterval) -> Void
    let onTrimRegionStart: (UUID, TimeInterval) -> Void
    let onTrimRegionEnd: (UUID, TimeInterval) -> Void

    /// 이 세션을 콕 집어 받는 사람으로 지정한 피드백 (전체 대상 피드백은 눈금자 깃발로만 표시).
    let feedbacks: [FeedbackItem]
    let selectedFeedbackId: UUID?
    let onTapFeedbackCluster: (FeedbackCluster) -> Void

    /// 말풍선 최대 폭. 이보다 가까운 피드백은 하나로 묶어 "💬 N개"로 보여준다.
    private let feedbackMarkerWidth: CGFloat = 180

    var body: some View {
        ZStack(alignment: .topLeading) {
            (isSelected ? GB.laneSelected : GB.lane)

            if let loopRegion {
                Rectangle()
                    .fill(GB.cycle.opacity(isLoopEnabled ? 0.12 : 0.05))
                    .frame(width: CGFloat(loopRegion.upperBound - loopRegion.lowerBound) * pxPerSec)
                    .offset(x: CGFloat(loopRegion.lowerBound) * pxPerSec)
            }

            ForEach(track.regions) { region in
                regionClip(region)
            }

            ForEach(patches) { patch in
                patchClip(patch)
            }

            ForEach(FeedbackCluster.make(feedbacks, pxPerSec: pxPerSec, minSpacing: feedbackMarkerWidth)) { cluster in
                feedbackMarker(cluster)
            }
        }
        .frame(width: width)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.black.opacity(0.6)).frame(height: 1) }
        .clipped()
        .task(id: track.id) {
            if track.waveform.isEmpty {
                track.waveform = await WaveformLoader.peaks(url: track.fileURL, bins: 1600)
            }
        }
    }

    // MARK: 원본 리전

    private func regionClip(_ region: TrackRegion) -> some View {
        let isSel = region.id == selectedRegionId
        return TimelineClip(
            start: region.timelineStart, duration: region.duration, pxPerSec: pxPerSec,
            y: 5, height: max(height - 10, 10), minWidth: 4,
            isSelected: isSel, handles: .inside,
            onTap: { onSelectRegion(region.id) },
            onMove: { onMoveRegion(region.id, region.timelineStart + $0) },
            onTrimStart: { onTrimRegionStart(region.id, region.timelineStart + $0) },
            onTrimEnd: { onTrimRegionEnd(region.id, region.timelineEnd + $0) }
        ) {
            RoundedRectangle(cornerRadius: 6)
                .fill(track.tint.opacity(track.isMuted ? 0.25 : (isSel ? 0.75 : 0.55)))
                .overlay(alignment: .topLeading) {
                    Text(track.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.leading, isSel ? 24 : 8)
                        .padding(.top, 5)
                }
                .overlay {
                    WaveformShape(peaks: waveformSlice(for: region))
                        .fill(Color.white.opacity(track.isMuted ? 0.3 : 0.75))
                        .padding(.top, 22)
                        .padding(.bottom, 6)
                }
                .overlay {
                    if isSel {
                        RoundedRectangle(cornerRadius: 6).stroke(GB.cycle, lineWidth: 3)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    /// 리전이 가리키는 원본 구간만큼의 파형.
    private func waveformSlice(for region: TrackRegion) -> [Float] {
        let peaks = track.waveform
        guard !peaks.isEmpty, track.duration > 0 else { return [] }
        let perSec = Double(peaks.count) / track.duration
        let lo = max(0, min(peaks.count, Int(region.sourceStart * perSec)))
        let hi = max(lo, min(peaks.count, Int((region.sourceStart + region.duration) * perSec)))
        return Array(peaks[lo..<hi])
    }

    // MARK: 재녹음 패치

    /// 탭하면 켜고 선택, 선택된 패치는 리전처럼 끌어서 옮기고 양끝 손잡이로 자른다.
    private func patchClip(_ stored: Patch) -> some View {
        // 켜져 있는 패치는 컨트롤러가 가진 최신 위치로 그린다.
        let active = track.activePatch(id: stored.id)
        let isActive = active != nil
        let patch = active ?? stored
        let isSel = patch.id == selectedPatchId
        return TimelineClip(
            start: patch.startTime, duration: patch.duration, pxPerSec: pxPerSec,
            y: height - 46, height: 38, minWidth: 18,
            // 패치는 짧은 경우가 많아서 손잡이를 블록 바깥에 붙인다 — 안쪽에 두면 몸통(옮기기)을 잡을 곳이 없다.
            isSelected: isSel, handles: .outside,
            onTap: { onTapPatch(stored) },
            onMove: { onMovePatch(patch.startTime + $0) },
            onTrimStart: { onTrimPatchStart(patch.startTime + $0) },
            onTrimEnd: { onTrimPatchEnd(patch.endTime + $0) }
        ) {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.red.opacity(isActive ? 0.75 : 0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isSel ? GB.cycle : Color.white.opacity(isActive ? 0.9 : 0.3),
                                lineWidth: isSel ? 3 : (isActive ? 2 : 1))
                )
                .overlay(alignment: .bottomLeading) {
                    // 라벨은 저장된 패치 기준 (채택 여부 등은 저장본에만 최신 값이 있다)
                    Text(isActive ? "\(versionLabel(stored)) ●" : versionLabel(stored))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(4)
                }
        }
    }
}

extension TrackLane {
    /// 피드백 구간 위쪽에 붙는 말풍선. 묶음이면 개수, 녹음 답변이 코멘트를 기다리면 파란색.
    fileprivate func feedbackMarker(_ cluster: FeedbackCluster) -> some View {
        let isSel = cluster.items.contains { $0.id == selectedFeedbackId }
        let fill: Color = isSel ? .white : cluster.status.timelineColor
        return Button { onTapFeedbackCluster(cluster) } label: {
            HStack(spacing: 4) {
                Image(systemName: {
                    switch cluster.status {
                    case .awaitingComment: return "waveform.badge.mic"
                    case .passed: return "checkmark.circle.fill"
                    case .needsPractice: return "text.bubble.fill"
                    }
                }())
                if cluster.isSingle {
                    let item = cluster.items[0]
                    Text(item.status == .needsPractice ? item.text : "\(item.status.label) · \(item.text)")
                        .lineLimit(1)
                } else {
                    Text("피드백 \(cluster.items.count)개")
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .frame(maxWidth: feedbackMarkerWidth - 24, alignment: .leading)
            .foregroundStyle(Color.black)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Capsule().fill(fill))
        }
        .buttonStyle(.plain)
        .offset(x: CGFloat(cluster.start) * pxPerSec, y: 26)
    }
}

// MARK: - 타임라인 위 편집 가능한 블록 (리전·패치 공용)

/// 선택되면 노란 손잡이가 생기고, 몸통을 끌면 옮기기, 손잡이를 끌면 그쪽 끝을 자른다.
/// 끄는 동안은 화면에만 미리 보여주고, 손을 떼면 "몇 초 움직였는지"를 콜백으로 넘긴다.
struct TimelineClip<Content: View>: View {
    enum Handles { case inside, outside }

    let start: TimeInterval
    let duration: TimeInterval
    let pxPerSec: CGFloat
    let y: CGFloat
    let height: CGFloat
    let minWidth: CGFloat
    let isSelected: Bool
    let handles: Handles
    let onTap: () -> Void
    let onMove: (_ deltaSeconds: TimeInterval) -> Void
    let onTrimStart: (_ deltaSeconds: TimeInterval) -> Void
    let onTrimEnd: (_ deltaSeconds: TimeInterval) -> Void
    @ViewBuilder let content: () -> Content

    private enum DragMode { case move, left, right }
    @State private var dragMode: DragMode?
    @State private var dragDelta: CGFloat = 0

    private var handleWidth: CGFloat { handles == .inside ? 18 : 16 }

    var body: some View {
        let baseX = CGFloat(start) * pxPerSec
        let baseW = CGFloat(duration) * pxPerSec
        let (x, w): (CGFloat, CGFloat) = {
            guard let dragMode else { return (baseX, baseW) }
            switch dragMode {
            case .move: return (baseX + dragDelta, baseW)
            case .left: return (baseX + min(dragDelta, baseW - 8), baseW - min(dragDelta, baseW - 8))
            case .right: return (baseX, max(8, baseW + dragDelta))
            }
        }()

        // 손잡이는 몸통과 분리된 층에 둔다 — 몸통에 겹쳐 붙이면 몸통의 "옮기기" 제스처가
        // 손잡이 드래그까지 가로채서 자르기가 안 된다.
        ZStack {
            content()
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
                .highPriorityGesture(isSelected ? moveGesture : nil)

            if isSelected && handles == .inside {
                HStack(spacing: 0) {
                    handle(.left)
                    Spacer(minLength: 0)
                    handle(.right)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .frame(width: max(minWidth, w), height: height)
        .overlay(alignment: .leading) {
            if isSelected && handles == .outside { handle(.left).offset(x: -handleWidth) }
        }
        .overlay(alignment: .trailing) {
            if isSelected && handles == .outside { handle(.right).offset(x: handleWidth) }
        }
        .offset(x: x, y: y)
    }

    private func seconds(_ translation: CGFloat) -> TimeInterval {
        TimeInterval(translation / pxPerSec)
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { v in dragMode = .move; dragDelta = v.translation.width }
            .onEnded { v in
                onMove(seconds(v.translation.width))
                dragMode = nil; dragDelta = 0
            }
    }

    @ViewBuilder
    private func handle(_ mode: DragMode) -> some View {
        let grip = Capsule().fill(Color.black.opacity(0.6))
            .frame(width: 3, height: handles == .inside ? 26 : 18)
        Group {
            if handles == .inside {
                Rectangle().fill(GB.cycle).frame(width: handleWidth)
            } else {
                RoundedRectangle(cornerRadius: 4).fill(GB.cycle).frame(width: handleWidth, height: height)
            }
        }
        .overlay(grip)
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 1)
                .onChanged { v in dragMode = mode; dragDelta = v.translation.width }
                .onEnded { v in
                    let delta = seconds(v.translation.width)
                    if mode == .left { onTrimStart(delta) } else { onTrimEnd(delta) }
                    dragMode = nil; dragDelta = 0
                }
        )
    }
}

/// 가운데를 기준으로 위아래 대칭인 막대 파형.
struct WaveformShape: Shape {
    let peaks: [Float]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !peaks.isEmpty else { return path }
        let mid = rect.midY
        let step = rect.width / CGFloat(peaks.count)
        let barWidth = max(step * 0.8, 0.5)
        for (i, peak) in peaks.enumerated() {
            let h = max(0.5, CGFloat(peak) * rect.height / 2)
            path.addRect(CGRect(x: rect.minX + CGFloat(i) * step, y: mid - h, width: barWidth, height: h * 2))
        }
        return path
    }
}
