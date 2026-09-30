import SwiftUI
import YouTubePlayerKit

/// POC: YouTube 공식 영상을 (YouTubePlayerKit으로) 임베드 재생하면서,
/// 그 재생 위치에 맞춰 악보가 자동으로 넘어가는지 검증하는 화면.
///
/// 분리(Demucs) 파이프라인과는 무관하다 — 여기서 YouTube는 어디까지나
/// "참고 음원 재생 소스"이고, 원본 파형을 앱이 가져오지 않는다.
struct YouTubeSyncView: View {
    @State private var videoIdInput: String = "lz61GEAnbl0"   // 유다빈밴드 - 항해 (MBC Show MusicCore 방송 클립)
    @StateObject private var playerSource = YouTubeSyncPlayerSource(videoId: "lz61GEAnbl0")
    @StateObject private var scoreSync = ScoreSyncController(source: "youtube")

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            ScoreView(scoreSync: scoreSync, currentTime: playerSource.currentTime)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 16) {
                Text("YouTube 연동 검증 (YouTubePlayerKit)")
                    .font(.headline)

                YouTubePlayerView(playerSource.player)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                HStack {
                    TextField("YouTube 영상 ID", text: $videoIdInput)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("불러오기") {
                        playerSource.load(videoId: videoIdInput.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    .buttonStyle(.borderedProminent)
                }

                HStack(spacing: 8) {
                    Circle()
                        .fill(playerSource.isReady ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(playerSource.isReady ? "플레이어 준비됨" : "로딩 중…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatted(playerSource.currentTime))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if let errorDescription = playerSource.errorDescription {
                    Label(errorDescription, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Text("영상 재생 화면 안의 재생/일시정지/탐색 버튼을 그대로 쓰면 됩니다. 이 앱은 오디오 파형을 가져오지 않고, 공식 플레이어의 '지금 몇 초인지'만 읽어서 악보 자동 넘김에 씁니다.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .frame(width: 420)
        }
        .padding(24)
    }

    private func formatted(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}
