import Foundation

/// 트랙 위의 오디오 조각(GarageBand의 "리전"). 원본 스템 파일의 [sourceStart, sourceStart+duration]
/// 부분을 곡 타임라인의 timelineStart 위치에서 재생한다. 옮기기·양끝 자르기·분할은 이 값만 바꾼다
/// (원본 파일은 건드리지 않음).
public struct TrackRegion: Identifiable, Equatable, Codable, Sendable {
    public var id = UUID()
    public var timelineStart: TimeInterval
    public var sourceStart: TimeInterval
    public var duration: TimeInterval
    public var timelineEnd: TimeInterval { timelineStart + duration }

    public init(id: UUID = UUID(), timelineStart: TimeInterval, sourceStart: TimeInterval, duration: TimeInterval) {
        self.id = id
        self.timelineStart = timelineStart
        self.sourceStart = sourceStart
        self.duration = duration
    }

    /// 파일 전체를 0초부터 놓은 편집 전 상태.
    public static func whole(duration: TimeInterval) -> TrackRegion {
        TrackRegion(timelineStart: 0, sourceStart: 0, duration: duration)
    }
}
