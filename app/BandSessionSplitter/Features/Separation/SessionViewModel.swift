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

/// 시뮬레이터는 이 Mac 위에서 직접 돌기 때문에 127.0.0.1로 접근해야 한다.
/// 192.168.x.x 같은 Mac 자신의 LAN IP로 접근하면 라우터의 hairpin NAT 문제로
/// 요청이 아예 도달하지 못하고 타임아웃 날 수 있다(실제로 겪은 문제).
/// 실기기는 반대로 127.0.0.1이 기기 자신을 가리키므로 Mac의 LAN IP가 필요하다.
/// 매번 수동으로 주소를 바꾸다 틀리는 걸 막기 위해 빌드 대상에 따라 기본값을 분기한다.
///
/// 주의: Mac의 LAN IP는 Wi-Fi를 다시 연결하거나 네트워크를 옮기면 바뀔 수 있다.
/// 실기기에서 "The request timed out"이 나면 제일 먼저 이 IP가 지금도 맞는지
/// (Mac에서 `ipconfig getifaddr en0`) 확인할 것 — 앱 안에서는 ⚙️ 버튼으로 바로 수정 가능.
#if targetEnvironment(simulator)
private let defaultServerURL = "http://127.0.0.1:8756"
#else
private let defaultServerURL = "http://10.141.52.89:8756"
#endif

@MainActor
final class SessionViewModel: ObservableObject {
    @Published var state: FlowState = .idle
    @Published var serverURLText: String = defaultServerURL
    @Published var playerController = StemPlayerController()

    private var pickedFileURL: URL?
    private var service: SeparationService {
        SeparationService(baseURL: URL(string: serverURLText) ?? URL(string: defaultServerURL)!)
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
    }
}
