import Foundation

/// Practice가 Player에게 보내는 명령. 재생을 직접 조작하지 않고 이 값만 보낸다.
public enum PracticeCommand: Equatable, Sendable {
    /// 구간을 반복 재생하기 시작한다 (속도 포함)
    case start(ClosedRange<TimeInterval>, rate: Float)
    case setRate(Float)
    case stop
}
