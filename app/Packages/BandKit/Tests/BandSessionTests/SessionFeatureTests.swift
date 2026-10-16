import BandFoundation
import BandServices
import ComposableArchitecture
import Foundation
import Testing
@testable import BandSession

/// 곡 분리·열기 흐름. 서버와 저장소는 가짜로 바꾼다.
@MainActor
struct SessionFeatureTests {
    let server = URL(string: "http://127.0.0.1:8756")!

    private func stemURL(_ job: String, _ stem: String) -> URL { URL(fileURLWithPath: "/songs/\(job)/\(stem).mp3") }

    // MARK: 서버 없이 저장된 곡 열기

    @Test func 서버가_없어도_저장된_곡은_네트워크_없이_열린다() async {
        var state = SessionFeature.State()
        state.cachedSongJobID = "job-1"
        let opened = LockIsolated<[String]>([])
        let store = TestStore(initialState: state) { SessionFeature() } withDependencies: {
            // separationClient는 설정하지 않는다 → 네트워크를 부르면 테스트가 실패한다
            $0.songCacheClient.cachedURL = { job, stem in self.stemURL(job, stem) }
            $0.songCacheClient.markOpened = { job in opened.withValue { $0.append(job) } }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.loadSongTapped)
        for _ in 1...5 { await store.receive(\.stemDownloaded) }
        await store.receive(\.downloadFinished)
        await store.receive(\.delegate.songReady) {
            $0.flow = .ready
        }
        #expect(opened.value == ["job-1"])
        #expect(store.state.flow == .ready)
    }

    @Test func 공유_곡이_있으면_저장된_곡보다_우선한다() {
        var state = SessionFeature.State()
        state.cachedSongJobID = "old"
        #expect(state.openableJobID == "old")
        state.sharedSongJobID = "shared"
        #expect(state.openableJobID == "shared")
    }

    // MARK: 분리 흐름

    @Test func 파일을_고르고_분리하면_곡이_열린다() async {
        let clock = TestClock()
        let polls = LockIsolated(0)
        let store = TestStore(initialState: SessionFeature.State()) { SessionFeature() } withDependencies: {
            $0.continuousClock = clock
            $0.separationClient.upload = { _, _ in "job-9" }
            $0.separationClient.status = { _, _ in
                polls.withValue { $0 += 1 }
                return polls.value < 2 ? JobStatus(state: .processing) : JobStatus(state: .done, stems: Song.stemKeys)
            }
            $0.separationClient.downloadStem = { job, stem, _ in URL(fileURLWithPath: "/tmp/\(job)-\(stem).mp3") }
            $0.songCacheClient.cachedURL = { _, _ in nil }
            $0.songCacheClient.store = { temp, _, _ in temp }
            $0.songCacheClient.markOpened = { _ in }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        let file = URL(fileURLWithPath: "/tmp/rehearsal.m4a")

        await store.send(.fileSelected(file)) { $0.pickedFile = file; $0.flow = .fileSelected(name: "rehearsal.m4a") }
        await store.send(.startSeparationTapped) { $0.flow = .uploading }
        await store.receive(\.uploadResponse.success) { $0.jobID = "job-9"; $0.flow = .separating }
        await store.receive(\.pollRequested)
        await store.receive(\.statusPolled.success)          // 아직 분리 중
        await clock.advance(by: .seconds(1.5))
        await store.receive(\.pollRequested)
        await store.receive(\.statusPolled.success)          // 완료
        for _ in 1...5 { await store.receive(\.stemDownloaded) }
        await store.receive(\.downloadFinished)
        await store.receive(\.delegate.songReady)

        #expect(store.state.flow == .ready)
        #expect(store.state.jobID == "job-9")
    }

    @Test func 분리가_실패하면_실패_상태가_된다() async {
        struct Boom: Error, LocalizedError { var errorDescription: String? { "서버 오류" } }
        let store = TestStore(initialState: SessionFeature.State()) { SessionFeature() } withDependencies: {
            $0.separationClient.upload = { _, _ in throw Boom() }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        let file = URL(fileURLWithPath: "/tmp/rehearsal.m4a")

        await store.send(.fileSelected(file))
        await store.send(.startSeparationTapped) { $0.flow = .uploading }
        await store.receive(\.uploadResponse.failure) { $0.flow = .failed("서버 오류") }
    }

    @Test func 분리_중에_처음으로_돌아가면_폴링이_취소된다() async {
        let clock = TestClock()
        let store = TestStore(initialState: SessionFeature.State()) { SessionFeature() } withDependencies: {
            $0.continuousClock = clock
            $0.separationClient.upload = { _, _ in "job-1" }
            $0.separationClient.status = { _, _ in JobStatus(state: .processing) }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.fileSelected(URL(fileURLWithPath: "/tmp/a.m4a")))
        await store.send(.startSeparationTapped)
        await store.receive(\.uploadResponse.success)
        await store.receive(\.pollRequested)
        await store.receive(\.statusPolled.success)
        await store.send(.resetTapped) { $0 = SessionFeature.State() }
        await clock.advance(by: .seconds(10))   // 취소됐으므로 더 이상 폴링하지 않는다
    }

    // MARK: 서버 찾기

    @Test func 응답한_후보_서버를_쓴다() async {
        var state = SessionFeature.State()
        let wifi = URL(string: "http://192.168.0.5:8756")!
        let hotspot = URL(string: "http://172.20.10.2:8756")!
        state.serverCandidates = [wifi, hotspot]
        let store = TestStore(initialState: state) { SessionFeature() } withDependencies: {
            $0.separationClient.health = { url in url == hotspot }
            $0.songCacheClient.lastJobID = { nil }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.task)
        await store.receive(\.serverDetected) { $0.serverURL = hotspot; $0.serverStatus = "서버 연결됨" }
        await store.receive(\.delegate.serverChanged)
    }

    @Test func 직접_입력한_주소가_있으면_자동으로_바꾸지_않는다() async {
        let manual = URL(string: "http://10.0.0.7:8756")!
        let store = TestStore(initialState: SessionFeature.State()) { SessionFeature() }

        await store.send(.serverURLEntered(manual)) {
            $0.serverURL = manual
            $0.isManualServer = true
            $0.serverStatus = "직접 입력한 주소 사용"
        }
        await store.receive(\.delegate.serverChanged)
        await store.send(.serverDetected(URL(string: "http://192.168.0.5:8756")!))   // 무시된다
    }
}
