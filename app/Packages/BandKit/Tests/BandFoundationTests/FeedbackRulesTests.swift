import Foundation
import Testing
@testable import BandFoundation

/// 피드백(핀)의 순수 규칙. 모델이 지키는 규칙이라 화면이나 서버 없이 검증한다.
struct FeedbackRulesTests {
    private func pin(targets: [String] = ["bass"], author: String = Person.leaderID) -> FeedbackItem {
        var item = FeedbackItem(timeRange: 10...18, text: "후렴 들어갈 때 킥을 한 박 늦게", targetSessionIds: targets)
        item.author = author
        return item
    }

    private func attempt() -> FeedbackAttempt {
        FeedbackAttempt(sessionId: "bass", patchId: UUID())
    }

    // MARK: 녹음으로 답하기는 최대 2번

    @Test func 녹음으로_답하기는_두_번까지() {
        var item = pin()
        #expect(item.canAddRecording)
        item.attempts = [attempt()]
        #expect(item.canAddRecording)
        item.attempts.append(attempt())
        #expect(item.remainingRecordings == 0)
        #expect(!item.canAddRecording)
    }

    // MARK: 결론은 관련자 전원이 동의해야 정리된다

    @Test func 관련자는_핀을_남긴_사람과_받는_세션() {
        let item = pin(targets: ["bass", "drums"], author: "leader")
        #expect(item.participants == ["leader", "bass", "drums"])
    }

    @Test func 결론_제안은_제안자만_동의한_상태로_시작한다() {
        var item = pin(targets: ["bass"])
        item.conclusion = FeedbackConclusion(text: "킥을 한 박 늦게", kind: .tempo, attemptId: nil, proposer: "leader")
        #expect(item.status == .proposed)
        #expect(item.pendingAgreers == ["bass"])
    }

    @Test func 관련자_전원이_동의하면_정리된다() {
        var item = pin(targets: ["bass"])
        var conclusion = FeedbackConclusion(text: "킥을 한 박 늦게", kind: .tempo, attemptId: nil, proposer: "leader")
        conclusion.agreedBy.append("bass")
        item.conclusion = conclusion
        #expect(item.status == .concluded)
    }

    @Test func 결론이_없으면_이야기_중() {
        #expect(pin().status == .discussing)
    }

    // MARK: 내가 봐야 하는 핀

    @Test func 내_동의를_기다리는_결론은_내가_봐야_한다() {
        var item = pin(targets: ["bass"])
        item.conclusion = FeedbackConclusion(text: "킥을 한 박 늦게", kind: nil, attemptId: nil, proposer: "leader")
        #expect(item.needsAttention(from: "bass"))
        #expect(!item.needsAttention(from: "leader"))
    }

    // MARK: 예전 데이터와 호환

    @Test func 서버에_보내는_op_이름은_서버와_같다() {
        #expect(SyncOp.conclusionAgreed(feedback: UUID(), conclusion: UUID(), by: .leader).wireName == "conclusion.agree")
        #expect(SyncOp.patchDeleted(UUID()).wireName == "patch.delete")
    }

    @Test func 사람_ID는_문자열로_오간다() {
        #expect(Person(id: "leader") == .leader)
        #expect(Person(id: "bass") == .session("bass"))
        #expect(Person.session("bass").id == "bass")
    }
}
