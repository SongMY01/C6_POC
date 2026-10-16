import BandFoundation
import ComposableArchitecture
import Foundation
import Testing
@testable import BandSync

/// 동기화 규칙: 큐 보존, 오프라인 재시도, 내 변경이 남아 있으면 서버 상태를 적용하지 않기.
@MainActor
struct SyncFeatureTests {
    let url = URL(string: "http://127.0.0.1:8756")!
    let date = Date(timeIntervalSince1970: 1_000)
    let op = SyncOp.feedbackDeleted(UUID())

    private func store(
        queue: [SyncOp] = [],
        lastVersion: Int = -1,
        songJobID: String? = nil,
        status: SyncFeature.State.Status = .offline,
        dependencies: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<SyncFeature> {
        var initial = SyncFeature.State()
        initial.serverURL = url
        initial.queue = queue
        initial.lastVersion = lastVersion
        initial.songJobID = songJobID
        initial.status = status
        return TestStore(initialState: initial) { SyncFeature() } withDependencies: {
            $0.date.now = date
            dependencies(&$0)
        }
    }

    @Test func 변경을_쌓으면_바로_보내고_성공하면_큐가_빈다() async {
        let sent = LockIsolated<[SyncOp]>([])
        let store = store { $0.syncClient.send = { ops, _ in sent.withValue { $0 += ops } } }

        await store.send(.enqueue(op)) {
            $0.queue = [self.op]
            $0.isFlushing = true
            $0.status = .syncing
        }
        await store.receive(\.flushResponse.success) {
            $0.queue = []
            $0.isFlushing = false
            $0.status = .synced(self.date)
        }
        #expect(sent.value == [op])
    }

    @Test func 전송이_실패하면_큐를_보존하고_오프라인이_된다() async {
        struct Down: Error {}
        let store = store { $0.syncClient.send = { _, _ in throw Down() } }

        await store.send(.enqueue(op)) {
            $0.queue = [self.op]
            $0.isFlushing = true
            $0.status = .syncing
        }
        await store.receive(\.flushResponse.failure) {
            $0.isFlushing = false
            $0.status = .offline
        }
        #expect(store.state.queue == [op])   // 다시 연결되면 보낸다
    }

    @Test func 보낼_변경이_남아_있으면_서버_상태를_적용하지_않는다() async {
        let store = store(queue: [op])
        let remote = RemoteState(version: 5)
        // 큐가 비어 있지 않으므로 받은 상태를 무시한다 (상태 변화도, delegate도 없다)
        await store.send(.pullResponse(.success(remote)))
    }

    @Test func 서버_버전이_같으면_적용하지_않는다() async {
        let store = store(lastVersion: 5)
        await store.send(.pullResponse(.success(RemoteState(version: 5))))
    }

    @Test func 새_서버_상태는_Rehearsal에_넘기고_곡이_바뀌면_알린다() async {
        let store = store(lastVersion: 4, songJobID: "old")
        let remote = RemoteState(version: 5, songJobId: "new")

        await store.send(.pullResponse(.success(remote))) {
            $0.lastVersion = 5
            $0.status = .synced(self.date)
            $0.songJobID = "new"
        }
        await store.receive(\.delegate.remoteReceived)
        await store.receive(\.delegate.songJobChanged)
    }

    @Test func 서버가_안_되면_오프라인이_된다() async {
        struct Down: Error {}
        let store = store(status: .synced(date))
        await store.send(.pullResponse(.failure(Down()))) { $0.status = .offline }
    }

    @Test func 폴링은_3초마다_서버_상태를_받는다() async {
        let clock = TestClock()
        let pulls = LockIsolated(0)
        let store = store {
            $0.continuousClock = clock
            $0.syncClient.pull = { _, _ in pulls.withValue { $0 += 1 }; return nil }
        }

        await store.send(.task)
        await clock.advance(by: .seconds(3))
        await store.receive(\.pollTick)
        await store.receive(\.pullResponse.success) { $0.status = .synced(self.date) }
        #expect(pulls.value == 1)
        await store.send(.teardown)   // 화면이 사라지면 폴링을 멈춘다
    }
}
