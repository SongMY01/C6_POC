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

// MARK: - 패치 켜기/끄기 · 편집 (켜진 패치만: 옮기기 / 양끝 자르기)
//
// 한 트랙에 서로 다른 구간의 패치를 여러 개 켤 수 있다. 구간이 겹치는 패치는 동시에 못 켠다
// (같은 순간에 같은 세션이 두 번 연주되면 안 되므로) — 새로 켜거나 옮겨서 겹치면 다른 쪽을 끈다.
// 편집 함수는 바뀐 패치를 돌려주고, 화면이 그걸 PatchStore에 저장한다. 녹음 파일은 건드리지 않고
// "파일의 어느 부분(sourceStart~)을 곡의 어디(startTime~endTime)에 놓는지"만 바꾼다.

extension StemPlayerController {
    /// 패치를 켠다. 재생 중이면 이 트랙만 지금 위치에 맞춰 다시 예약한다 — 다른 트랙은 건드리지 않는다.
    @discardableResult
    func activatePatch(_ patch: Patch, fileURL: URL, for track: StemTrack) -> Bool {
        if track.isActive(patch.id) { return true }
        guard let file = try? AVAudioFile(forReading: fileURL) else { return false }
        deactivateOverlapping(patch, in: track)
        let player = PatchPlayer(file: file)
        track.patchPlayers[patch.id] = player
        attach(player)
        track.applyVolume()
        track.activePatches.append(patch)
        track.activePatches.sort { $0.startTime < $1.startTime }
        rescheduleIfPlaying(track)
        return true
    }

    func deactivatePatch(_ patchId: UUID, for track: StemTrack) {
        removePatchPlayer(patchId, from: track)
        rescheduleIfPlaying(track)
    }

    /// 트랙의 패치를 모두 끈다 (원본만 재생).
    func deactivateAllPatches(of track: StemTrack) {
        for patch in track.activePatches { removePatchPlayer(patch.id, from: track) }
        rescheduleIfPlaying(track)
    }

    private func removePatchPlayer(_ patchId: UUID, from track: StemTrack) {
        if let player = track.patchPlayers.removeValue(forKey: patchId) { detach(player) }
        track.activePatches.removeAll { $0.id == patchId }
    }

    private func deactivateOverlapping(_ patch: Patch, in track: StemTrack) {
        for other in track.activePatches where other.id != patch.id
            && other.startTime < patch.endTime && other.endTime > patch.startTime {
            removePatchPlayer(other.id, from: track)
        }
    }

    private func editActivePatch(_ patchId: UUID, of track: StemTrack, _ change: (inout Patch, _ fileDuration: TimeInterval) -> Void) -> Patch? {
        guard let i = track.activePatches.firstIndex(where: { $0.id == patchId }),
              let player = track.patchPlayers[patchId] else { return nil }
        var patch = track.activePatches[i]
        change(&patch, player.file.durationSeconds)
        guard patch != track.activePatches[i] else { return nil }
        track.activePatches[i] = patch
        deactivateOverlapping(patch, in: track)
        track.activePatches.sort { $0.startTime < $1.startTime }
        rescheduleIfPlaying(track)
        return patch
    }

    func movePatch(_ patchId: UUID, of track: StemTrack, to newStart: TimeInterval) -> Patch? {
        editActivePatch(patchId, of: track) { patch, _ in patch.move(to: newStart, songDuration: duration) }
    }

    func trimPatchStart(_ patchId: UUID, of track: StemTrack, to newStart: TimeInterval) -> Patch? {
        editActivePatch(patchId, of: track) { patch, _ in patch.trimStart(to: newStart) }
    }

    func trimPatchEnd(_ patchId: UUID, of track: StemTrack, to newEnd: TimeInterval) -> Patch? {
        editActivePatch(patchId, of: track) { patch, fileDuration in patch.trimEnd(to: newEnd, fileDuration: fileDuration) }
    }
}
