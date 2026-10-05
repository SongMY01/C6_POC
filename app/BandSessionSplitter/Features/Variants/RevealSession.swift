import Foundation
import AVFoundation
import SwiftUI

/// 구간을 정복했을 때(피드백 마무리) 보여 주는 비포/애프터 장면.
///
/// 처음 소리 → 지금 내 연주 순서로 그 구간을 한 번씩 들려주고, 합주본에 들어갔다는 문구와 함께
/// 효과음을 낸다. "해냈다"를 눈과 귀로 확인하는 순간이 연습의 마무리 보상이 되게 한다.
@MainActor
final class RevealSession: ObservableObject {
    enum Phase: Equatable {
        case idle
        case before     // 처음 소리 (패치를 끈 상태)
        case after      // 지금 내 연주 (패치를 켠 상태)
        case done
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var feedbackId: UUID?
    @Published private(set) var sessionName = ""
    @Published private(set) var region: ClosedRange<TimeInterval>?

    private weak var controller: StemPlayerController?
    private var showOriginal: (() -> Void)?
    private var showNew: (() -> Void)?
    private var chime: AVAudioPlayer?

    var isActive: Bool { phase != .idle }

    /// - showOriginal: 이 세션 트랙을 원본 소리로 (패치 끄기)
    /// - showNew: 이 세션 트랙을 내 연주로 (패치 켜기 — 곡에 반영된 상태)
    func start(feedbackId: UUID, sessionName: String, region: ClosedRange<TimeInterval>,
               controller: StemPlayerController,
               showOriginal: @escaping () -> Void, showNew: @escaping () -> Void) {
        stop()
        self.controller = controller
        self.feedbackId = feedbackId
        self.sessionName = sessionName
        self.region = region
        self.showOriginal = showOriginal
        self.showNew = showNew
        chime = SoundSynth.conquestChime()

        controller.pause()
        controller.setPlaybackRate(1)
        controller.loopRegion = region
        controller.isLoopEnabled = true
        controller.onLoopWrap = { [weak self] in self?.loopWrapped() }
        phase = .before
        showOriginal()
        controller.seek(to: region.lowerBound)
        controller.play()
        SyncClient.shared.log("reveal_start")
    }

    /// 한 번 더 보기
    func replay() {
        guard let controller, let region, let showOriginal else { return }
        controller.pause()
        controller.isLoopEnabled = true
        controller.onLoopWrap = { [weak self] in self?.loopWrapped() }
        phase = .before
        showOriginal()
        controller.seek(to: region.lowerBound)
        controller.play()
    }

    func stop() {
        guard phase != .idle else { return }
        controller?.onLoopWrap = nil
        controller?.pause()
        // 어디서 멈추든 곡은 "내 연주가 반영된" 상태로 돌려놓는다.
        showNew?()
        chime?.stop()
        phase = .idle
        feedbackId = nil
        region = nil
        showOriginal = nil
        showNew = nil
    }

    private func loopWrapped() {
        guard let controller else { return }
        switch phase {
        case .before:
            phase = .after
            showNew?()
        case .after:
            controller.onLoopWrap = nil
            controller.pause()
            phase = .done
            chime?.currentTime = 0
            chime?.play()
            SyncClient.shared.log("reveal_done")
        default:
            break
        }
    }
}

/// 비포/애프터 진행 띠 (플레이어 위쪽).
struct RevealBar: View {
    @ObservedObject var session: RevealSession
    let progressText: String

    var body: some View {
        HStack(spacing: 12) {
            switch session.phase {
            case .before:
                Text("🎧 처음 소리").font(.system(size: 16, weight: .bold))
                Text("→").foregroundStyle(.white.opacity(0.4))
                Text("지금 내 연주").font(.system(size: 14)).foregroundStyle(.white.opacity(0.45))
            case .after:
                Text("🎧 처음 소리").font(.system(size: 14)).foregroundStyle(.white.opacity(0.45))
                Text("→").foregroundStyle(.white.opacity(0.4))
                Text("✨ 지금 내 연주").font(.system(size: 16, weight: .bold))
            case .done:
                Text("🎉 \(session.sessionName) 구간 정복!").font(.system(size: 17, weight: .heavy))
                Text("합주본에 들어갔어요 · \(progressText)")
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.75))
            case .idle:
                EmptyView()
            }
            Spacer(minLength: 8)
            if session.phase == .done {
                Button("한 번 더 듣기") { session.replay() }
                    .buttonStyle(GBToolButtonStyle())
            }
            Button(session.phase == .done ? "닫기" : "건너뛰기") { session.stop() }
                .buttonStyle(GBToolButtonStyle())
        }
        .foregroundStyle(.white)
        .lineLimit(1)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(session.phase == .done ? Color(red: 0.12, green: 0.32, blue: 0.2) : Color(red: 0.2, green: 0.17, blue: 0.3))
        .clipped()
    }
}
