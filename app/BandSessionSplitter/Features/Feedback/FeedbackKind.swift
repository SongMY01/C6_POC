import Foundation

/// 피드백 종류. 리더가 종류를 먼저 고르면 그 종류에 맞는 입력창이 열리고(FeedbackComposerSheet),
/// 받는 사람에게는 종류에 맞는 연습 방법이 같이 간다.
///
/// 새로 쓸 수 있는 종류는 `composable`(박자 · 볼륨·밸런스 · 하모니 · 표현 · 그 외).
/// dynamics/playing/cue는 예전에 쓴 피드백을 읽기 위해 남겨 둔다.
enum FeedbackKind: String, Codable, CaseIterable, Identifiable {
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
    static let composable: [FeedbackKind] = [.tempo, .balance, .harmony, .expression, .free]

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tempo: return L("박자")
        case .balance: return L("볼륨·밸런스")
        case .harmony: return L("하모니")
        case .expression: return L("표현")
        case .free: return L("그 외")
        case .dynamics: return L("세기")
        case .playing: return L("음·연주")
        case .cue: return L("약속")
        }
    }

    /// SF Symbol
    var icon: String {
        switch self {
        case .tempo: return "metronome"
        case .balance: return "slider.vertical.3"
        case .harmony: return "music.note.list"
        case .expression: return "waveform.path"
        case .free: return "text.bubble"
        case .dynamics: return "speaker.wave.3"
        case .playing: return "music.note"
        case .cue: return "hand.raised"
        }
    }

    /// 받는 사람에게 같이 가는 연습 방법.
    var plan: PracticePlan {
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
struct PracticePlan {
    var countIn: Bool
    /// 템포 사다리 속도들 (비어 있으면 원래 속도로 반복)
    var ladder: [Float]
    var usesTargetMix = false
    var usesReference = false
    /// 연습 없이 확인만 받는 피드백 (약속)
    var confirmOnly = false

    /// 화면에 보여줄 단계 설명 (예: "구간 반복", "카운트인", "80% → 100% 속도").
    func steps(hasReference: Bool) -> [String] {
        if confirmOnly { return [L("연습 없음"), L("확인만 누르기")] }
        var steps: [String] = []
        if usesReference && hasReference { steps.append(L("시범 듣기")) }
        if usesTargetMix { steps += [L("목표 믹스로 듣기"), L("지금 ↔ 목표 비교")] }
        steps.append(L("구간 반복"))
        if countIn { steps.append(L("카운트인")) }
        if let first = ladder.first, ladder.count > 1 {
            steps.append(L("\(Int((first * 100).rounded()))% → 100% 속도"))
        }
        return steps
    }
}

extension String {
    /// 받침 유무에 따라 조사를 붙인다. 예: "브레이크".withJosa("은", "는") → "브레이크는"
    func withJosa(_ withBatchim: String, _ withoutBatchim: String) -> String {
        guard let last = unicodeScalars.last, (0xAC00...0xD7A3).contains(last.value) else {
            return self + withoutBatchim
        }
        let hasBatchim = (last.value - 0xAC00) % 28 != 0
        return self + (hasBatchim ? withBatchim : withoutBatchim)
    }
}
