import Foundation
import Combine
import YouTubePlayerKit

/// YouTubePlayerKit(SvenTiigi) 기반 어댑터.
///
/// 이전엔 WKWebView + 손으로 짠 IFrame API 브릿지를 직접 구현했는데,
/// 실제 재생이 시뮬레이터 WKWebView의 서드파티 쿠키 차단(ITP) 이슈로 막혔다.
/// YouTubePlayerKit은 이런 문제들을 이미 다뤄본 검증된 오픈소스 라이브러리라
/// 직접 디버깅하는 대신 이걸로 교체해서 재생 가능 여부를 다시 검증한다.
///
/// 여전히 원본 파형(오디오)은 가져오지 않는다 — 공식 플레이어가 재생하는
/// 화면/소리를 그대로 보여주고, 그 플레이어의 현재 재생 시각만 구독한다.
@MainActor
final class YouTubeSyncPlayerSource: ObservableObject {
    let player: YouTubePlayer

    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var state: YouTubePlayer.State = .idle

    var isReady: Bool { state.isReady }
    var errorDescription: String? {
        guard case .error(let error) = state else { return nil }
        switch error {
        case .embeddedVideoPlayingNotAllowed:
            return "이 영상은 소유자가 임베드 재생을 막아둔 영상입니다 (다른 영상으로 시도해보세요)."
        case .notFound:
            return "영상을 찾을 수 없습니다 (삭제되었거나 비공개 영상)."
        case .invalidSource:
            return "영상 ID가 올바르지 않습니다."
        case .html5NotSupported:
            return "이 플레이어 환경에서 재생할 수 없는 영상입니다."
        case .iFrameAPIFailedToLoad, .webContentProcessDidTerminate, .setupFailed:
            return "플레이어 로딩에 실패했습니다."
        }
    }

    private var cancellables: Set<AnyCancellable> = []

    init(videoId: String) {
        self.player = YouTubePlayer(
            source: .video(id: videoId),
            configuration: .init(autoPlay: false, playInline: true)
        )
        observe()
    }

    func load(videoId: String) {
        player.source = .video(id: videoId)
    }

    private func observe() {
        player.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.state = state
            }
            .store(in: &cancellables)

        player.currentTimePublisher(updateInterval: 0.25)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] measurement in
                self?.currentTime = measurement.converted(to: .seconds).value
            }
            .store(in: &cancellables)
    }
}
