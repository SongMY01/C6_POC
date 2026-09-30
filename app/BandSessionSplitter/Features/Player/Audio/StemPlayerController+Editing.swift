import Foundation
import AVFoundation

// MARK: - 리전 편집 (옮기기 / 양끝 자르기 / 분할 / 삭제)
//
// 계산 규칙은 TimelineEditing.swift에 있고, 여기서는 적용 후
// 곡 길이 갱신 → (재생 중이면) 그 트랙만 다시 예약 → 저장만 한다.

extension StemPlayerController {
    private func editRegions(of track: StemTrack, _ change: (inout [TrackRegion]) -> Void) {
        change(&track.regions)
        recomputeDuration()
        rescheduleIfPlaying(track)
        scheduleRegionSave()
    }

    /// 드래그 중엔 변경이 초당 수십 번 일어나므로, 멈추고 0.5초 뒤에 한 번만 파일에 쓴다.
    private func scheduleRegionSave() {
        regionSaveTask?.cancel()
        regionSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            self.regionStore.save(self.tracks)
        }
    }

    func moveRegion(_ id: UUID, in track: StemTrack, to newStart: TimeInterval) {
        editRegions(of: track) { $0.moveRegion(id, to: newStart) }
    }

    func trimRegionStart(_ id: UUID, in track: StemTrack, to newStart: TimeInterval) {
        editRegions(of: track) { $0.trimRegionStart(id, to: newStart) }
    }

    func trimRegionEnd(_ id: UUID, in track: StemTrack, to newEnd: TimeInterval) {
        editRegions(of: track) { $0.trimRegionEnd(id, to: newEnd, fileDuration: track.duration) }
    }

    /// time 위치에서 리전을 둘로 자른다. 잘린 두 리전의 id를 돌려준다.
    @discardableResult
    func splitRegion(in track: StemTrack, at time: TimeInterval) -> (left: UUID, right: UUID)? {
        guard track.regions.regionSplittable(at: time) != nil else { return nil }
        var result: (left: UUID, right: UUID)?
        editRegions(of: track) { result = $0.splitRegion(at: time) }
        return result
    }

    func deleteRegion(_ id: UUID, in track: StemTrack) {
        editRegions(of: track) { $0.removeAll { $0.id == id } }
    }

    /// 편집 전 상태(파일 전체 한 덩어리)로 되돌린다.
    func resetRegions(of track: StemTrack) {
        editRegions(of: track) { $0 = [.whole(duration: track.duration)] }
    }
}

// MARK: - 패치 켜기/끄기 · 편집 (켜져 있는 패치만: 옮기기 / 양끝 자르기)
//
// 편집 함수는 바뀐 패치를 돌려주고, 화면이 그걸 PatchStore에 저장한다. 녹음 파일은 건드리지 않고
// "파일의 어느 부분(sourceStart~)을 곡의 어디(startTime~endTime)에 놓는지"만 바꾼다.

extension StemPlayerController {
    /// 이 트랙에서 재녹음한 패치를 켜거나(patch != nil) 끈다(nil).
    /// 재생 중이면 이 트랙만 지금 위치에 맞춰 다시 예약한다 — 다른 트랙은 건드리지 않는다.
    func setPreviewPatch(_ patch: Patch?, fileURL: URL?, for track: StemTrack) {
        track.previewPatch = patch
        if let fileURL, patch != nil {
            track.previewFile = try? AVAudioFile(forReading: fileURL)
            if track.previewFile == nil { track.previewPatch = nil }
        } else {
            track.previewFile = nil
        }
        rescheduleIfPlaying(track)
    }

    private func editPreviewPatch(of track: StemTrack, _ change: (inout Patch, _ fileDuration: TimeInterval) -> Void) -> Patch? {
        guard var patch = track.previewPatch, let file = track.previewFile else { return nil }
        change(&patch, file.durationSeconds)
        guard patch != track.previewPatch else { return nil }
        track.previewPatch = patch
        rescheduleIfPlaying(track)
        return patch
    }

    func movePreviewPatch(of track: StemTrack, to newStart: TimeInterval) -> Patch? {
        editPreviewPatch(of: track) { patch, _ in patch.move(to: newStart, songDuration: duration) }
    }

    func trimPreviewPatchStart(of track: StemTrack, to newStart: TimeInterval) -> Patch? {
        editPreviewPatch(of: track) { patch, _ in patch.trimStart(to: newStart) }
    }

    func trimPreviewPatchEnd(of track: StemTrack, to newEnd: TimeInterval) -> Patch? {
        editPreviewPatch(of: track) { patch, fileDuration in patch.trimEnd(to: newEnd, fileDuration: fileDuration) }
    }
}
