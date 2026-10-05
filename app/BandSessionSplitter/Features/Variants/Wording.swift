import Foundation

/// 피드백 진행 규칙과 말투. 버전(기능 플래그)에 따라 바뀌는 부분을 한곳에 모아 둔다.
///
/// 목적: "받은 피드백을 어떻게 하면 잘 시작할 수 있을까?" — 숙제·검사처럼 들리는 말과
/// 끝이 없는 반복을 없애고, 한 피드백당 녹음 기회를 정해 둔다.
enum FeedbackRules {
    /// 피드백 하나에 올릴 수 있는 녹음(시도) 수. `limitTwoTakes`가 켜진 버전에서만 적용.
    static let maxTakes = 2

    static var limitTakes: Bool { VariantStore.enabled(.limitTwoTakes) }

    /// 더 올릴 수 있는가? (제한이 없으면 항상 true — 통과 후에도 새 시도가 피드백을 다시 연다)
    static func canAddTake(to item: FeedbackItem) -> Bool {
        guard limitTakes else { return true }
        return item.attempts.count < maxTakes && item.passedAttemptId == nil
    }

    /// 남은 기회 "1/2" 표시용 (제한이 없으면 nil)
    static func takeCounter(for item: FeedbackItem) -> String? {
        guard limitTakes else { return nil }
        return "\(min(item.attempts.count, maxTakes))/\(maxTakes)"
    }

    /// 방금 올린 시도로 피드백을 자동 완료해야 하는가? (마지막 기회까지 썼을 때)
    static func shouldAutoFinish(_ item: FeedbackItem) -> Bool {
        limitTakes && item.attempts.count >= maxTakes && item.passedAttemptId == nil
    }

    /// 완료를 누를 수 있는 사람: 제한 버전은 누구나("이 정도면 됐어요"), 아니면 리더만 ("통과").
    static var anyoneCanFinish: Bool { limitTakes }
}

enum Wording {
    static var friendly: Bool { VariantStore.enabled(.friendlyWording) }

    static func statusLabel(_ status: FeedbackStatus) -> String {
        if friendly {
            switch status {
            case .needsPractice: return "해볼 차례"
            case .awaitingComment: return "들어봐 주세요"
            case .passed: return "준비 완료"
            }
        }
        switch status {
        case .needsPractice: return "연습 필요"
        case .awaitingComment: return "코멘트 요청"
        case .passed: return "통과"
        }
    }

    static var finishButton: String { friendly || FeedbackRules.limitTakes ? "이 정도면 됐어요" : "통과" }
    static var reopenButton: String { "다시 열기 (추가 연습 필요)" }

    /// "N차 시도 녹음하기" / "한 번 더 쳐볼게요 (1/2)"
    static func recordButton(sessionName: String, emoji: String, item: FeedbackItem) -> String {
        if friendly {
            let counter = FeedbackRules.takeCounter(for: item).map { " (\($0))" } ?? ""
            return item.attempts.isEmpty
                ? "\(emoji) \(sessionName) 한 번 쳐볼게요\(counter)"
                : "\(emoji) \(sessionName) 한 번 더 쳐볼게요\(counter)"
        }
        return "\(emoji) \(sessionName) \(item.attempts.count + 1)차 시도 녹음하기"
    }

    static func recordHeader(hasAttempts: Bool) -> String {
        if friendly { return hasAttempts ? "한 번 더 해보고 싶다면" : "해보고 올리기" }
        return hasAttempts ? "다시 연습해서 올리기" : "연습해서 올리기"
    }

    static var waitingForReply: String { friendly ? "답장을 기다리는 중" : "코멘트를 기다리는 중" }

    static var allDoneFooter: String {
        "녹음은 한 피드백에 \(FeedbackRules.maxTakes)번까지예요. 마지막 녹음을 올리면 자동으로 마무리돼요."
    }
}
