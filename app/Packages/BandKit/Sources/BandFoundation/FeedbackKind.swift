import Foundation

/// 피드백 종류. 리더가 종류를 먼저 고르면 그 종류에 맞는 입력창이 열리고(FeedbackComposerSheet),
/// 받는 사람에게는 종류에 맞는 연습 방법이 같이 간다.
///
/// 새로 쓸 수 있는 종류는 `composable`(박자 · 볼륨·밸런스 · 하모니 · 표현 · 그 외).
/// dynamics/playing/cue는 예전에 쓴 피드백을 읽기 위해 남겨 둔다.
public enum FeedbackKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case tempo
    case balance
    case harmony
    case expression
    case free
    // 예전 종류 (읽기 전용)
    case dynamics
    case playing
    case cue

    /// 작성 화면에서 고를 수 있는 종류 (화이트보드 회의 2026-10-14 기준)
    public static let composable: [FeedbackKind] = [.tempo, .balance, .harmony, .expression, .free]

    public var id: String { rawValue }

    /// 받는 사람에게 같이 가는 연습 방법.
    public var plan: PracticePlan {
        switch self {
        case .tempo: return PracticePlan(countIn: true, ladder: [0.8, 0.9, 1.0])
        case .harmony: return PracticePlan(countIn: true, ladder: [0.7, 0.85, 1.0])
        case .expression: return PracticePlan(countIn: true, ladder: [])
        case .dynamics: return PracticePlan(countIn: true, ladder: [])
        case .balance: return PracticePlan(countIn: false, ladder: [], usesTargetMix: true)
        case .playing: return PracticePlan(countIn: true, ladder: [0.7, 0.85, 1.0], usesReference: true)
        case .cue: return PracticePlan(countIn: false, ladder: [], confirmOnly: true)
        case .free: return PracticePlan(countIn: false, ladder: [])
        }
    }
}

/// 피드백 종류가 정하는 연습 방법. 받는 사람은 "연습 시작" 한 번으로 이대로 연습한다.
public struct PracticePlan: Equatable, Sendable {
    public var countIn: Bool
    /// 템포 사다리 속도들 (비어 있으면 원래 속도로 반복)
    public var ladder: [Float]
    public var usesTargetMix = false
    public var usesReference = false
    /// 연습 없이 확인만 받는 피드백 (약속)
    public var confirmOnly = false


    public init(countIn: Bool = false, ladder: [Float] = [], usesTargetMix: Bool = false,
                usesReference: Bool = false, confirmOnly: Bool = false) {
        self.countIn = countIn
        self.ladder = ladder
        self.usesTargetMix = usesTargetMix
        self.usesReference = usesReference
        self.confirmOnly = confirmOnly
    }
}
