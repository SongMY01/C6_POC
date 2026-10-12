import Foundation

/// 피드백 종류. 리더가 종류를 고르면 그 종류에 맞는 칩(상황 고르기)이 열리고,
/// 고른 칩으로 보낼 문장이 만들어지며, 받는 사람에게는 종류에 맞는 연습 방법이 같이 간다.
///
/// 종류 이름은 리더가 합주 중에 실제로 떠올리는 말로 붙였다. 분류가 애매하면 "그냥 말로".
enum FeedbackKind: String, Codable, CaseIterable, Identifiable {
    case tempo
    case dynamics
    case balance
    case playing
    case cue
    case free

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tempo: return "박자"
        case .dynamics: return "세기"
        case .balance: return "밸런스"
        case .playing: return "음·연주"
        case .cue: return "약속"
        case .free: return "그냥 말로"
        }
    }

    /// SF Symbol
    var icon: String {
        switch self {
        case .tempo: return "metronome"
        case .dynamics: return "speaker.wave.3"
        case .balance: return "slider.vertical.3"
        case .playing: return "music.note"
        case .cue: return "hand.raised"
        case .free: return "text.bubble"
        }
    }

    /// 종류별 칩 질문. 보기 문구는 실제 합주에서 나오는 말투로.
    func questions(tracks: [StemTrack], targets: [String]) -> [FeedbackQuestion] {
        let others = tracks.filter { !targets.contains($0.id) }.map(\.displayName)
        switch self {
        case .tempo:
            return [
                FeedbackQuestion(title: "어떻게", options: ["빨라져요", "늦어져요", "흔들려요", "들어오는 게 늦어요", "들어오는 게 빨라요"]),
                FeedbackQuestion(title: "무엇에 맞춰", options: others + ["클릭"]),
            ]
        case .dynamics:
            return [
                FeedbackQuestion(title: "어떻게", options: ["더 크게", "더 작게", "점점 크게", "점점 작게", "세게 치고 바로 줄이기"]),
                FeedbackQuestion(title: "얼마나", options: ["살짝", "확실히"]),
            ]
        case .balance:
            return [
                FeedbackQuestion(title: "어떻게 들려요", options: ["너무 커요", "너무 작아요", "다른 소리에 묻혀요"]),
                FeedbackQuestion(title: "왜 그런 것 같아요", options: ["세게 쳐서", "소리 설정 때문에", "다른 악기랑 겹쳐서"]),
            ]
        case .playing:
            return [
                FeedbackQuestion(title: "무엇이", options: ["음이 틀려요", "코드가 틀려요", "리듬이 달라요", "너무 많이 쳐요", "너무 비어요"]),
            ]
        case .cue:
            return [
                FeedbackQuestion(title: "무슨 약속", options: ["시작 신호", "끝내는 신호", "브레이크", "반복 횟수", "템포 바꾸기"]),
                FeedbackQuestion(title: "누가 신호", options: tracks.map(\.displayName) + ["리더"]),
            ]
        case .free:
            return []
        }
    }

    /// 고른 칩으로 보낼 문장을 만든다. picks[i] = i번째 질문에서 고른 보기 (안 골랐으면 nil).
    func sentence(picks: [String?], hasReference: Bool) -> String {
        let a = picks.first ?? nil
        let b = picks.count > 1 ? picks[1] : nil
        switch self {
        case .tempo:
            guard let a else { return "" }
            if let b { return "이 구간에서 \(a). \(b)에 맞춰 주세요." }
            return "이 구간에서 \(a)."
        case .dynamics:
            guard let a else { return "" }
            let how = a == "세게 치고 바로 줄이기" ? "세게 치고 바로 줄여 주세요" : "\(a) 해 주세요"
            return "이 구간은 \(b.map { "\($0) " } ?? "")\(how)."
        case .balance:
            guard let a else { return "목표 믹스를 들어 보세요." }
            return "이 구간에서 소리가 \(a)\(b.map { " (\($0) 그런 것 같아요)" } ?? ""). 목표 믹스를 들어 보세요."
        case .playing:
            let ref = hasReference ? " 시범 녹음을 들어 보세요." : ""
            guard let a else { return hasReference ? "시범 녹음을 들어 보세요." : "" }
            return "이 구간 \(a).\(ref)"
        case .cue:
            guard let a else { return "" }
            let who = b ?? "리더"
            return "\(a.withJosa("은", "는")) \(who.withJosa("이", "가")) 줘요. 확인 눌러 주세요."
        case .free:
            return ""
        }
    }

    /// 받는 사람에게 같이 가는 연습 방법.
    var plan: PracticePlan {
        switch self {
        case .tempo: return PracticePlan(countIn: true, ladder: [0.8, 0.9, 1.0])
        case .dynamics: return PracticePlan(countIn: true, ladder: [])
        case .balance: return PracticePlan(countIn: false, ladder: [], usesTargetMix: true)
        case .playing: return PracticePlan(countIn: true, ladder: [0.7, 0.85, 1.0], usesReference: true)
        case .cue: return PracticePlan(countIn: false, ladder: [], confirmOnly: true)
        case .free: return PracticePlan(countIn: false, ladder: [])
        }
    }
}

struct FeedbackQuestion {
    let title: String
    let options: [String]
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
        if confirmOnly { return ["연습 없음", "확인만 누르기"] }
        var steps: [String] = []
        if usesReference && hasReference { steps.append("시범 듣기") }
        if usesTargetMix { steps += ["목표 믹스로 듣기", "지금 ↔ 목표 비교"] }
        steps.append("구간 반복")
        if countIn { steps.append("카운트인") }
        if let first = ladder.first, ladder.count > 1 {
            steps.append("\(Int((first * 100).rounded()))% → 100% 속도")
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
