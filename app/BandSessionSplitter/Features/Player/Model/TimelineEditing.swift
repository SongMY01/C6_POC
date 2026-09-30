import Foundation

/// 리전·패치 편집의 순수 계산 (오디오 엔진·화면과 무관).
/// 규칙: 리전끼리는 겹치지 않고, 리전/패치는 원본(녹음) 파일에 있는 소리 범위 밖으로 늘어나지 않는다.
enum TimelineEditing {
    static let minLength: TimeInterval = 0.1
}

// MARK: - 리전

extension Array where Element == TrackRegion {
    private func neighbors(of id: UUID) -> (prevEnd: TimeInterval, nextStart: TimeInterval)? {
        let sorted = self.sorted { $0.timelineStart < $1.timelineStart }
        guard let i = sorted.firstIndex(where: { $0.id == id }) else { return nil }
        let prevEnd = i > 0 ? sorted[i - 1].timelineEnd : 0
        let nextStart = i + 1 < sorted.count ? sorted[i + 1].timelineStart : .greatestFiniteMagnitude
        return (prevEnd, nextStart)
    }

    private mutating func update(_ id: UUID, _ change: (inout TrackRegion) -> Void) {
        guard let i = firstIndex(where: { $0.id == id }) else { return }
        change(&self[i])
        sort { $0.timelineStart < $1.timelineStart }
    }

    /// 리전을 newStart 위치로 옮긴다 (이웃과 겹치지 않는 범위에서).
    mutating func moveRegion(_ id: UUID, to newStart: TimeInterval) {
        guard let n = neighbors(of: id), let region = first(where: { $0.id == id }) else { return }
        let clamped = Swift.min(Swift.max(newStart, n.prevEnd), n.nextStart - region.duration)
        guard clamped >= n.prevEnd else { return }
        update(id) { $0.timelineStart = clamped }
    }

    /// 왼쪽 끝을 newStart로 (오른쪽 끝은 고정). 원본에 남은 소리보다 더 앞으로는 못 늘린다.
    mutating func trimRegionStart(_ id: UUID, to newStart: TimeInterval) {
        guard let n = neighbors(of: id), let r = first(where: { $0.id == id }) else { return }
        let earliest = Swift.max(n.prevEnd, r.timelineStart - r.sourceStart)
        let latest = r.timelineEnd - TimelineEditing.minLength
        let clamped = Swift.min(Swift.max(newStart, earliest), latest)
        update(id) { region in
            let delta = clamped - region.timelineStart
            region.timelineStart = clamped
            region.sourceStart += delta
            region.duration -= delta
        }
    }

    /// 오른쪽 끝을 newEnd로 (왼쪽 끝은 고정). 원본 파일 끝보다 더 늘리진 못한다.
    mutating func trimRegionEnd(_ id: UUID, to newEnd: TimeInterval, fileDuration: TimeInterval) {
        guard let n = neighbors(of: id), let r = first(where: { $0.id == id }) else { return }
        let latest = Swift.min(n.nextStart, r.timelineStart + (fileDuration - r.sourceStart))
        let clamped = Swift.min(Swift.max(newEnd, r.timelineStart + TimelineEditing.minLength), latest)
        update(id) { $0.duration = clamped - $0.timelineStart }
    }

    /// 재생헤드 time이 양끝에서 최소 길이 이상 떨어진 리전 (분할 가능한 리전).
    func regionSplittable(at time: TimeInterval) -> TrackRegion? {
        first {
            time > $0.timelineStart + TimelineEditing.minLength && time < $0.timelineEnd - TimelineEditing.minLength
        }
    }

    /// time 위치에서 리전을 둘로 자른다. 잘린 두 리전의 id를 돌려준다.
    mutating func splitRegion(at time: TimeInterval) -> (left: UUID, right: UUID)? {
        guard let r = regionSplittable(at: time), let i = firstIndex(where: { $0.id == r.id }) else { return nil }
        let left = TrackRegion(timelineStart: r.timelineStart, sourceStart: r.sourceStart, duration: time - r.timelineStart)
        let right = TrackRegion(timelineStart: time, sourceStart: r.sourceStart + (time - r.timelineStart), duration: r.timelineEnd - time)
        replaceSubrange(i...i, with: [left, right])
        return (left.id, right.id)
    }

    /// 실제로 재생할 원본 조각들 = 리전들에서 켜진 패치 구간들을 뺀 나머지.
    func playbackPieces(excluding patchRanges: [ClosedRange<TimeInterval>]) -> [PlaybackPiece] {
        var pieces: [PlaybackPiece] = []
        for region in self {
            var parts = [(region.timelineStart, region.timelineEnd)]
            for pr in patchRanges {
                parts = parts.flatMap { (a, b) -> [(TimeInterval, TimeInterval)] in
                    var out: [(TimeInterval, TimeInterval)] = []
                    if a < pr.lowerBound { out.append((a, Swift.min(b, pr.lowerBound))) }
                    if b > pr.upperBound { out.append((Swift.max(a, pr.upperBound), b)) }
                    return out
                }
            }
            for (a, b) in parts where b > a {
                pieces.append(PlaybackPiece(songStart: a, songEnd: b, sourceStart: region.sourceStart + (a - region.timelineStart)))
            }
        }
        return pieces
    }
}

/// 곡의 [songStart, songEnd]에서 원본 파일의 sourceStart부터 재생하는 조각.
struct PlaybackPiece: Equatable {
    let songStart: TimeInterval
    let songEnd: TimeInterval
    let sourceStart: TimeInterval
}

// MARK: - 패치

extension Patch {
    /// 길이는 그대로 두고 newStart로 옮긴다 (곡 범위 안에서).
    mutating func move(to newStart: TimeInterval, songDuration: TimeInterval) {
        let len = duration
        let clamped = min(max(0, newStart), max(0, songDuration - len))
        startTime = clamped
        endTime = clamped + len
    }

    /// 왼쪽 끝을 newStart로 (오른쪽 끝 고정). 녹음 파일 맨 앞보다 더 늘리진 못한다.
    mutating func trimStart(to newStart: TimeInterval) {
        let earliest = max(0, startTime - sourceStart)
        let clamped = min(max(newStart, earliest), endTime - TimelineEditing.minLength)
        sourceStart += clamped - startTime
        startTime = clamped
    }

    /// 오른쪽 끝을 newEnd로 (왼쪽 끝 고정). 녹음 파일 끝보다 더 늘리진 못한다.
    mutating func trimEnd(to newEnd: TimeInterval, fileDuration: TimeInterval) {
        let latest = startTime + (fileDuration - sourceStart)
        endTime = min(max(newEnd, startTime + TimelineEditing.minLength), latest)
    }
}
