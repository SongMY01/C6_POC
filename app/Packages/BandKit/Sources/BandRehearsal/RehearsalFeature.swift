import BandFoundation
import BandServices
import ComposableArchitecture
import Foundation

/// 핀 대화 · 결론 합의 · 녹음으로 답하기 · 곡에 반영(채택). 이 앱의 핵심 규칙이 여기 있다.
///
/// 핀(`FeedbackItem`)과 재녹음(`Patch`)을 **한 Feature가 함께 소유**한다.
/// 결론이 정리되면 그 시도의 녹음이 곡에 반영되어서, 두 데이터의 규칙이 서로 걸쳐 있기 때문이다.
///
/// 모든 로컬 변경은 "상태 변경 + 저장 + `delegate(.opProduced)`"를 한 Action 처리에서 한다.
/// 서버 전송은 부모가 `opProduced`를 `SyncFeature`로 이어 준다.
@Reducer
public struct RehearsalFeature {
    /// 새 핀을 만들 때 화면이 모아서 보내는 값
    public struct PinDraft: Equatable, Sendable {
        public var timeRange: ClosedRange<TimeInterval>
        public var text: String
        public var targetSessionIDs: [String]
        public var kind: FeedbackKind?
        public var targetMix: [String: Float]?
        public var referencePatchID: Patch.ID?

        public init(timeRange: ClosedRange<TimeInterval>, text: String, targetSessionIDs: [String],
                    kind: FeedbackKind? = nil, targetMix: [String: Float]? = nil, referencePatchID: Patch.ID? = nil) {
            self.timeRange = timeRange
            self.text = text
            self.targetSessionIDs = targetSessionIDs
            self.kind = kind
            self.targetMix = targetMix
            self.referencePatchID = referencePatchID
        }
    }

    /// 오른쪽 핀 패널에 지금 보여 주는 것 (nil이면 닫힘)
    public enum Panel: Equatable, Sendable {
        case newPin(track: String, range: ClosedRange<TimeInterval>)
        case thread(FeedbackItem.ID)
        /// 겹치거나 붙어 있는 핀 묶음에서 고르기
        case list([FeedbackItem.ID])
    }

    @ObservableState
    public struct State: Equatable {
        /// 이 기기의 사람. 부모(AppFeature)가 내려준다.
        public var me: Person = .leader
        public var songID: String?
        public var pins: IdentifiedArrayOf<FeedbackItem> = []
        public var patches: IdentifiedArrayOf<Patch> = []
        public var panel: Panel?
        /// 지금 구간 반복이 잡힌 핀
        public var selectedPinID: FeedbackItem.ID?
        /// 녹음으로 답하는 중인 핀
        public var replyingTo: FeedbackItem.ID?
        public var errorMessage: String?

        public init() {}

        /// 내가 봐야 하는 핀 (모델 규칙을 그대로 쓴다)
        public func needsAttention(_ pin: FeedbackItem) -> Bool { pin.needsAttention(from: me.id) }
    }

    public enum Action: Sendable {
        case songOpened(String)
        case pinsLoaded(Result<Loaded, any Error>)
        case meChanged(Person)

        case pinAdded(PinDraft)
        case pinDeleted(FeedbackItem.ID)
        case commentPosted(pin: FeedbackItem.ID, attempt: FeedbackAttempt.ID?, text: String,
                           stance: FeedbackStance?, tool: FeedbackToolValue?)
        case commentDeleted(pin: FeedbackItem.ID, comment: FeedbackComment.ID)

        /// 녹음으로 답하기 (핀 하나에 최대 2번)
        case replyByRecordingTapped(pin: FeedbackItem.ID)
        case recordingFinished(file: URL, track: String, range: ClosedRange<TimeInterval>)
        case recordingSaved(Result<Patch, any Error>)
        case attemptDeleted(pin: FeedbackItem.ID, attempt: FeedbackAttempt.ID)

        /// 결론은 관련자 전원이 동의해야 정리된다
        case conclusionProposed(pin: FeedbackItem.ID, text: String, kind: FeedbackKind?,
                                attempt: FeedbackAttempt.ID?, tool: FeedbackToolValue?)
        case conclusionAgreed(pin: FeedbackItem.ID, conclusion: FeedbackConclusion.ID)
        case conclusionCleared(pin: FeedbackItem.ID)

        case adoptToggled(Patch.ID)
        case patchPlacementChanged(Patch)
        case patchDeleted(Patch.ID)

        case practiceTapped(pin: FeedbackItem.ID)
        case pinSelected(FeedbackItem.ID?)
        case panelShown(Panel?)

        /// 서버 상태 (Sync에서 부모를 거쳐 온다)
        case remoteReplaced(feedback: [FeedbackItem], patches: [Patch])
        case persistFailed(String)
        case delegate(Delegate)

        public struct Loaded: Sendable {
            public var feedback: [FeedbackItem]
            public var patches: [Patch]
            public init(feedback: [FeedbackItem], patches: [Patch]) {
                self.feedback = feedback
                self.patches = patches
            }
        }

        @CasePathable
        public enum Delegate: Equatable, Sendable {
            /// 서버로 보낼 변경 하나
            case opProduced(SyncOp)
            /// 곡에 반영(채택)된 녹음이 바뀌었다 → Player가 재생에 켜고 끈다
            case adoptionChanged(Patch, on: Bool)
            /// 이 트랙의 이 구간을 녹음해 달라 → Player가 녹음한다
            case recordRequested(track: String, range: ClosedRange<TimeInterval>)
            case practiceRequested(FeedbackItem)
        }
    }

    @Dependency(\.storageClient) var storage
    @Dependency(\.uuid) var uuid
    @Dependency(\.date.now) var now

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            // MARK: 불러오기
            case let .songOpened(songID):
                state.songID = songID
                return .run { [storage] send in
                    do {
                        let feedback = try await storage.loadFeedback(songID)
                        let patches = try await storage.loadPatches(songID)
                        await send(.pinsLoaded(.success(.init(feedback: feedback, patches: patches))))
                    } catch {
                        await send(.pinsLoaded(.failure(error)))
                    }
                }

            case let .pinsLoaded(.success(loaded)):
                state.pins = IdentifiedArray(uniqueElements: loaded.feedback)
                state.patches = IdentifiedArray(uniqueElements: loaded.patches)
                return .none

            case let .pinsLoaded(.failure(error)):
                state.errorMessage = error.localizedDescription
                return .none

            case let .meChanged(person):
                state.me = person
                return .none

            // MARK: 핀과 코멘트
            case let .pinAdded(draft):
                var pin = FeedbackItem(
                    id: uuid(), timeRange: draft.timeRange, text: draft.text,
                    targetSessionIds: draft.targetSessionIDs, kind: draft.kind,
                    targetMix: draft.targetMix, referencePatchId: draft.referencePatchID, createdAt: now
                )
                pin.author = state.me.id
                state.pins.append(pin)
                state.pins.sort { $0.startTime < $1.startTime }
                return .concatenate(.send(.delegate(.opProduced(.feedbackAdded(pin)))), persist(state))

            case let .pinDeleted(id):
                guard let pin = state.pins.remove(id: id) else { return .none }
                if state.panel == .thread(pin.id) { state.panel = nil }
                return .concatenate(.send(.delegate(.opProduced(.feedbackDeleted(id)))), persist(state))

            case let .commentPosted(pinID, attemptID, text, stance, tool):
                guard state.pins[id: pinID] != nil else { return .none }
                let comment = FeedbackComment(id: uuid(), author: state.me.id, text: text, createdAt: now, stance: stance, tool: tool)
                if let attemptID, let i = state.pins[id: pinID]?.attempts.firstIndex(where: { $0.id == attemptID }) {
                    state.pins[id: pinID]?.attempts[i].comments.append(comment)
                } else {
                    state.pins[id: pinID]?.comments.append(comment)
                }
                return .concatenate(
                    .send(.delegate(.opProduced(.commentAdded(feedback: pinID, attempt: attemptID, comment)))),
                    persist(state)
                )

            case let .commentDeleted(pinID, commentID):
                guard state.pins[id: pinID] != nil else { return .none }
                state.pins[id: pinID]?.comments.removeAll { $0.id == commentID }
                if let attempts = state.pins[id: pinID]?.attempts.indices {
                    for i in attempts { state.pins[id: pinID]?.attempts[i].comments.removeAll { $0.id == commentID } }
                }
                return .concatenate(.send(.delegate(.opProduced(.commentDeleted(feedback: pinID, commentID)))), persist(state))

            // MARK: 녹음으로 답하기
            case let .replyByRecordingTapped(pinID):
                guard let pin = state.pins[id: pinID], pin.canAddRecording else { return .none }   // 최대 2번
                let track = pin.isFor(sessionId: state.me.id) && !state.me.isLeader
                    ? state.me.id : pin.targetSessionIds.first
                guard let track else { return .none }
                state.replyingTo = pinID
                return .send(.delegate(.recordRequested(track: track, range: pin.timeRange)))

            case let .recordingFinished(file, track, range):
                let patch = Patch(id: uuid(), sessionId: track, startTime: range.lowerBound,
                                  endTime: range.upperBound, createdAt: now)
                guard let songID = state.songID else {
                    return .send(.recordingSaved(.success(patch)))
                }
                return .run { [storage] send in
                    do {
                        _ = try await storage.savePatchFile(file, patch.id, songID)
                        await send(.recordingSaved(.success(patch)))
                    } catch {
                        await send(.recordingSaved(.failure(error)))
                    }
                }

            case let .recordingSaved(.success(patch)):
                state.patches.append(patch)
                var effects: [Effect<Action>] = [.send(.delegate(.opProduced(.patchUpserted(patch))))]
                if let pinID = state.replyingTo {
                    state.replyingTo = nil
                    // 규칙을 다시 확인한다: 그 사이 다른 기기에서 두 번을 채웠으면 시도로 붙이지 않는다
                    if let pin = state.pins[id: pinID], pin.canAddRecording {
                        let attempt = FeedbackAttempt(id: uuid(), sessionId: patch.sessionId, patchId: patch.id, createdAt: now)
                        state.pins[id: pinID]?.attempts.append(attempt)
                        state.pins[id: pinID]?.passedAttemptId = nil
                        effects.append(.send(.delegate(.opProduced(.attemptAdded(feedback: pinID, attempt)))))
                    }
                }
                effects.append(persist(state))
                return .concatenate(effects)

            case let .recordingSaved(.failure(error)):
                state.replyingTo = nil
                state.errorMessage = error.localizedDescription
                return .none

            case let .attemptDeleted(pinID, attemptID):
                guard state.pins[id: pinID] != nil else { return .none }
                let before = adoptedPatchID(of: state.pins[id: pinID])
                state.pins[id: pinID]?.attempts.removeAll { $0.id == attemptID }
                if state.pins[id: pinID]?.passedAttemptId == attemptID { state.pins[id: pinID]?.passedAttemptId = nil }
                return .concatenate(
                    .send(.delegate(.opProduced(.attemptDeleted(feedback: pinID, attemptID)))),
                    applyAdoption(&state, before: before, pin: pinID),
                    persist(state)
                )

            // MARK: 결론 합의
            case let .conclusionProposed(pinID, text, kind, attemptID, tool):
                guard state.pins[id: pinID] != nil else { return .none }
                // TODO(팀 결정): 누가 제안할 수 있는지 (관련자만 / 리더만 / 누구나). 지금은 누구나.
                let before = adoptedPatchID(of: state.pins[id: pinID])
                // 제안한 사람은 바로 동의한 것으로 친다. 새 제안은 기존 동의를 지우고 처음부터 다시 받는다.
                let conclusion = FeedbackConclusion(id: uuid(), text: text, kind: kind, attemptId: attemptID, tool: tool,
                                                    proposer: state.me.id, createdAt: now)
                state.pins[id: pinID]?.conclusion = conclusion
                return .concatenate(
                    .send(.delegate(.opProduced(.conclusionProposed(feedback: pinID, conclusion)))),
                    applyAdoption(&state, before: before, pin: pinID),
                    persist(state)
                )

            case let .conclusionAgreed(pinID, conclusionID):
                let me = state.me
                guard let pin = state.pins[id: pinID], let conclusion = pin.conclusion, conclusion.id == conclusionID,
                      pin.participants.contains(me.id),            // 관련자만 동의할 수 있다
                      !conclusion.agreedBy.contains(me.id)         // 이미 동의했으면 무시
                else { return .none }
                let before = adoptedPatchID(of: pin)
                state.pins[id: pinID]?.conclusion?.agreedBy.append(me.id)
                return .concatenate(
                    .send(.delegate(.opProduced(.conclusionAgreed(feedback: pinID, conclusion: conclusionID, by: me)))),
                    applyAdoption(&state, before: before, pin: pinID),
                    persist(state)
                )

            case let .conclusionCleared(pinID):
                guard state.pins[id: pinID] != nil else { return .none }
                let before = adoptedPatchID(of: state.pins[id: pinID])
                state.pins[id: pinID]?.conclusion = nil
                state.pins[id: pinID]?.passedAttemptId = nil
                return .concatenate(
                    .send(.delegate(.opProduced(.conclusionCleared(feedback: pinID)))),
                    applyAdoption(&state, before: before, pin: pinID),
                    persist(state)
                )

            // MARK: 재녹음(패치)
            case let .adoptToggled(patchID):
                guard let patch = state.patches[id: patchID] else { return .none }
                return .concatenate(adopt(&state, patchID: patchID, on: !patch.isAdopted), persist(state))

            case let .patchPlacementChanged(patch):
                guard state.patches[id: patch.id] != nil else { return .none }
                state.patches[id: patch.id] = patch
                return .concatenate(.send(.delegate(.opProduced(.patchUpserted(patch)))), persist(state))

            case let .patchDeleted(patchID):
                guard let patch = state.patches.remove(id: patchID) else { return .none }
                var effects: [Effect<Action>] = [.send(.delegate(.opProduced(.patchDeleted(patchID))))]
                if patch.isAdopted { effects.append(.send(.delegate(.adoptionChanged(patch, on: false)))) }
                effects.append(persist(state))
                return .concatenate(effects)

            // MARK: 연습과 화면
            case let .practiceTapped(pinID):
                guard let pin = state.pins[id: pinID], !pin.plan.confirmOnly else { return .none }
                return .send(.delegate(.practiceRequested(pin)))

            case let .pinSelected(id):
                state.selectedPinID = id
                return .none

            case let .panelShown(panel):
                state.panel = panel
                return .none

            // MARK: 서버 상태
            case let .remoteReplaced(feedback, patches):
                let old = state.patches
                state.pins = IdentifiedArray(uniqueElements: feedback)
                state.patches = IdentifiedArray(uniqueElements: patches)
                // 채택이 달라진 패치만 Player에 알린다 (새로 반영된 것은 켜고, 해제·삭제된 것은 끈다)
                var effects: [Effect<Action>] = []
                for patch in patches where patch.isAdopted != (old[id: patch.id]?.isAdopted ?? false) {
                    effects.append(.send(.delegate(.adoptionChanged(patch, on: patch.isAdopted))))
                }
                for patch in old where patch.isAdopted && state.patches[id: patch.id] == nil {
                    effects.append(.send(.delegate(.adoptionChanged(patch, on: false))))
                }
                effects.append(persist(state))
                return .concatenate(effects)

            case let .persistFailed(message):
                state.errorMessage = message
                return .none

            case .delegate:
                return .none
            }
        }
    }

    // MARK: - 채택(곡에 반영)

    /// 정리된(합의된) 결론이 가리키는 시도의 패치 ID. 예전 방식의 통과도 정리된 것으로 본다.
    private func adoptedPatchID(of pin: FeedbackItem?) -> Patch.ID? {
        guard let pin, pin.status == .concluded else { return nil }
        let attemptID = pin.conclusion?.attemptId ?? pin.passedAttemptId
        return pin.attempts.first { $0.id == attemptID }?.patchId
    }

    /// 결론이 바뀐 뒤 채택된 패치가 달라졌으면 해제하고 새로 반영한다.
    private func applyAdoption(_ state: inout State, before: Patch.ID?, pin pinID: FeedbackItem.ID) -> Effect<Action> {
        let after = adoptedPatchID(of: state.pins[id: pinID])
        guard before != after else { return .none }
        var effects: [Effect<Action>] = []
        if let before { effects.append(adopt(&state, patchID: before, on: false)) }
        if let after { effects.append(adopt(&state, patchID: after, on: true)) }
        return .concatenate(effects)
    }

    /// 패치 하나를 곡에 반영하거나 해제한다. 같은 세션에서 구간이 겹치는 기존 채택은 해제한다.
    private func adopt(_ state: inout State, patchID: Patch.ID, on: Bool) -> Effect<Action> {
        guard var patch = state.patches[id: patchID], patch.isAdopted != on else { return .none }
        var effects: [Effect<Action>] = []
        if on {
            let overlapping = state.patches.filter {
                $0.id != patchID && $0.isAdopted && $0.sessionId == patch.sessionId
                    && $0.startTime < patch.endTime && $0.endTime > patch.startTime
            }
            for other in overlapping {
                var released = other
                released.isAdopted = false
                state.patches[id: other.id] = released
                effects.append(.send(.delegate(.opProduced(.patchUpserted(released)))))
                effects.append(.send(.delegate(.adoptionChanged(released, on: false))))
            }
        }
        patch.isAdopted = on
        state.patches[id: patchID] = patch
        effects.append(.send(.delegate(.opProduced(.patchUpserted(patch)))))
        effects.append(.send(.delegate(.adoptionChanged(patch, on: on))))
        return .concatenate(effects)
    }

    // MARK: - 저장

    private func persist(_ state: State) -> Effect<Action> {
        guard let songID = state.songID else { return .none }
        let pins = Array(state.pins)
        let patches = Array(state.patches)
        return .run { [storage] send in
            do {
                try await storage.saveFeedback(songID, pins)
                try await storage.savePatches(songID, patches)
            } catch {
                await send(.persistFailed(error.localizedDescription))
            }
        }
    }
}
