import Foundation
import Combine

enum FlowState: Equatable {
    case idle
    case fileSelected(name: String)
    case uploading
    case separating          // 서버가 Demucs로 분리 중
    case downloadingStems(done: Int, total: Int)
    case ready
    case failed(String)
}

/// 분리 서버 후보. 시뮬레이터는 이 Mac 위에서 직접 돌기 때문에 127.0.0.1로 접근해야 한다
/// (Mac 자신의 LAN IP로 접근하면 라우터의 hairpin NAT 문제로 타임아웃 날 수 있음 — 실제로 겪음).
/// 실기기는 Mac의 LAN IP가 필요한데, 개발하는 네트워크마다 Mac IP가 달라서
/// 후보를 모두 두고 분리 시작 전에 /health에 응답하는 쪽을 자동으로 고른다.
/// 새 장소가 생기면 여기에 추가 (Mac에서 `ipconfig getifaddr en0`로 IP 확인).
struct ServerCandidate: Identifiable {
    let name: String
    let url: String
    var id: String { url }
}

#if targetEnvironment(simulator)
let serverCandidates = [ServerCandidate(name: "이 Mac", url: "http://127.0.0.1:8756")]
#else
let serverCandidates = [
    ServerCandidate(name: "집 Wi-Fi", url: "http://192.168.0.5:8756"),
    ServerCandidate(name: "학교", url: "http://10.141.52.89:8756"),
    // Mac의 "인터넷 공유"로 Mac이 직접 Wi-Fi를 만들 때 Mac 주소
    ServerCandidate(name: "Mac 인터넷 공유", url: "http://192.168.2.1:8756"),
] + (2...14).map {
    // iPhone 개인용 핫스팟은 연결된 기기에 172.20.10.2~14를 나눠준다 (유저테스트 현장용)
    ServerCandidate(name: "핫스팟", url: "http://172.20.10.\($0):8756")
}
#endif

@MainActor
final class SessionViewModel: ObservableObject {
    @Published var state: FlowState = .idle
    @Published private(set) var serverURLText: String = serverCandidates[0].url
    /// 설정 화면에 보여줄 서버 연결 상태 ("학교 서버 연결됨" 등).
    @Published private(set) var serverStatus: String?
    /// ⚙️에서 주소를 직접 입력했으면 자동 선택을 하지 않는다.
    @Published private(set) var isManualServer = false
    @Published var playerController = StemPlayerController()
    /// 서버에 연결되지 않아도 열 수 있도록 이 기기에 저장해 둔 곡이 있는지.
    @Published private(set) var hasCachedSong = SongCache.lastJobId.map(SongCache.isComplete) ?? false

    private var pickedFileURL: URL?
    private var service: SeparationService {
        SeparationService(baseURL: URL(string: serverURLText) ?? URL(string: serverCandidates[0].url)!)
    }

    // MARK: - 서버 주소

    func setManualServer(_ url: String) {
        serverURLText = url
        isManualServer = true
        serverStatus = "직접 입력한 주소 사용"
        connectSync()
    }

    /// 지금 고른 서버로 여러 iPad 동기화를 연결한다.
    private func connectSync() {
        if let url = URL(string: serverURLText) {
            SyncClient.shared.configure(baseURL: url)
        }
    }

    /// 후보들 중 지금 응답하는 서버를 찾아 고른다. 모두 응답이 없으면 주소는 그대로 둔다.
    func detectServer() async {
        isManualServer = false
        serverStatus = "서버 찾는 중…"
        if let found = await Self.firstReachable(serverCandidates) {
            serverURLText = found.url
            serverStatus = "\(found.name) 서버 연결됨"
            connectSync()
        } else {
            serverStatus = "응답하는 서버 없음 — 서버가 켜져 있는지, 같은 Wi-Fi인지 확인"
        }
    }

    /// 후보 모두에 동시에 /health를 보내 가장 먼저 응답한 후보를 돌려준다.
    private static func firstReachable(_ candidates: [ServerCandidate]) async -> ServerCandidate? {
        await withTaskGroup(of: ServerCandidate?.self) { group in
            for candidate in candidates {
                group.addTask {
                    guard let url = URL(string: candidate.url)?.appendingPathComponent("health") else { return nil }
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 2
                    guard let (_, response) = try? await URLSession.shared.data(for: request),
                          (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
                    return candidate
                }
            }
            for await result in group {
                if let result {
                    group.cancelAll()
                    return result
                }
            }
            return nil
        }
    }

    func fileWasPicked(_ url: URL) {
        pickedFileURL = url
        state = .fileSelected(name: url.lastPathComponent)
    }

    func reset() {
        pickedFileURL = nil
        state = .idle
        playerController = StemPlayerController()
    }

    func startSeparation() {
        guard let fileURL = pickedFileURL else { return }
        state = .uploading
        Task {
            do {
                if !isManualServer { await detectServer() }
                let svc = service
                let jobId = try await svc.uploadRecording(fileURL: fileURL)
                state = .separating
                try await pollUntilDone(jobId: jobId, service: svc)
                try await downloadAllStems(jobId: jobId, service: svc)
                state = .ready
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// 리더가 이미 분리해 둔 공유 곡을 업로드·분리 없이 바로 내려받는다.
    /// 서버에 연결되지 않아 공유 곡을 모르면, 이 기기에 저장해 둔 마지막 곡을 연다.
    func loadSharedSong() {
        guard let jobId = SyncClient.shared.songJobId ?? SongCache.lastJobId else { return }
        Task {
            do {
                try await downloadAllStems(jobId: jobId, service: service)
                state = .ready
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func pollUntilDone(jobId: String, service: SeparationService) async throws {
        while true {
            let status = try await service.fetchStatus(jobId: jobId)
            switch status.status {
            case .done:
                return
            case .error:
                throw SeparationError.serverError(status.error ?? "알 수 없는 오류")
            case .queued, .processing:
                try await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    private func downloadAllStems(jobId: String, service: SeparationService) async throws {
        var tracks: [StemTrack] = []
        for (index, def) in sessionStems.enumerated() {
            state = .downloadingStems(done: index, total: sessionStems.count)
            let localURL = try await service.downloadStem(jobId: jobId, stemKey: def.key)
            if let track = StemTrack(definition: def, fileURL: localURL) {
                tracks.append(track)
            }
        }
        playerController.load(tracks: tracks)
        SongCache.markOpened(jobId: jobId)
        hasCachedSong = true
    }
}
