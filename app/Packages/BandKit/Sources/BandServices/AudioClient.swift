import BandFoundation
import Dependencies
import DependenciesMacros
import Foundation

/// 오디오 엔진이 알려 주는 일. Player/Practice가 Action으로 받는다.
public enum AudioEvent: Equatable, Sendable {
    case ended
    /// 구간 반복이 한 바퀴 돌았다 (연습 사다리가 이걸로 단계를 센다)
    case loopWrapped
    case recordingFinished(file: URL, track: String, range: ClosedRange<TimeInterval>)
    case interrupted
}

/// 재생·녹음 엔진(AVAudioEngine). 담당: Player
///
/// **재생 위치는 State에 올리지 않는다.** 화면의 재생헤드가 `position` 스트림을 직접 구독한다.
@DependencyClient
public struct AudioClient: Sendable {
    /// 스템을 불러온다 — 곡 전체 길이(초)를 돌려준다
    public var load: @Sendable (_ tracks: [SongTrack]) async throws -> TimeInterval
    public var play: @Sendable () async throws -> Void
    public var pause: @Sendable () async -> Void
    public var seek: @Sendable (_ time: TimeInterval) async -> Void
    public var setRate: @Sendable (_ rate: Float) async -> Void
    public var setLoop: @Sendable (_ range: ClosedRange<TimeInterval>?) async -> Void
    public var setVolume: @Sendable (_ track: String, _ volume: Float) async -> Void
    public var setMuted: @Sendable (_ track: String, _ muted: Bool) async -> Void
    public var setSolo: @Sendable (_ track: String?) async -> Void
    /// 트랙의 구간 편집(옮기기·자르기)이 바뀌었다 — 재생 중이면 그 트랙만 다시 예약한다
    public var regionsChanged: @Sendable (_ track: String, _ regions: [TrackRegion]) async -> Void
    /// 재녹음(패치)을 해당 트랙에 켠다. 같은 세션에서 구간이 겹치는 패치는 엔진이 끈다.
    public var activatePatch: @Sendable (_ patch: Patch, _ file: URL) async -> Bool = { _, _ in false }
    public var deactivatePatch: @Sendable (_ patchID: Patch.ID, _ track: String) async -> Void
    /// 마이크 권한을 요청하고 녹음을 시작한다 (대상 트랙은 뮤트, 항상 원래 속도)
    public var startRecording: @Sendable (_ track: String, _ range: ClosedRange<TimeInterval>) async throws -> Void
    public var stopRecording: @Sendable () async -> Void
    /// 카운트인 클릭 소리
    public var click: @Sendable (_ accent: Bool) async -> Void
    public var events: @Sendable () -> AsyncStream<AudioEvent> = { .finished }
    public var position: @Sendable () -> AsyncStream<TimeInterval> = { .finished }
}

extension AudioClient: DependencyKey {
    // TODO(Player 담당): 기존 StemPlayerController(+Editing, +Recording)를 감싸서 구현한다.
    public static let liveValue = AudioClient()
    public static let testValue = AudioClient()
    public static let previewValue = AudioClient(
        load: { _ in 0 },
        play: {},
        pause: {},
        seek: { _ in },
        setRate: { _ in },
        setLoop: { _ in },
        setVolume: { _, _ in },
        setMuted: { _, _ in },
        setSolo: { _ in },
        regionsChanged: { _, _ in },
        activatePatch: { _, _ in true },
        deactivatePatch: { _, _ in },
        startRecording: { _, _ in },
        stopRecording: {},
        click: { _ in },
        events: { .finished },
        position: { .finished }
    )
}

extension DependencyValues {
    public var audioClient: AudioClient {
        get { self[AudioClient.self] }
        set { self[AudioClient.self] = newValue }
    }
}
