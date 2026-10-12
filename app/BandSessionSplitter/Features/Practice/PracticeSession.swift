import Foundation
import AVFoundation

/// 피드백 하나를 "바로 시작해서" 연습하는 흐름: (카운트인) → (템포 사다리) → 끝.
///
/// 어떻게 연습할지는 피드백 종류가 정한다(PracticePlan) — 받는 사람은 "연습 시작"만 누르면 된다.
/// - 카운트인: "하나, 둘, 셋, 넷" 클릭 소리 뒤 구간이 시작된다.
/// - 템포 사다리: 느린 속도부터 100%까지 구간을 반복한다. 느린 단계는 두 바퀴, 100%는 한 바퀴.
///   (타임스트레치라 음높이는 그대로, 다른 세션 소리도 같이 느려진다.)
/// - 끝이 정해져 있어서 "언제 끝나지?" 하는 부담이 없다.
@MainActor
final class PracticeSession: ObservableObject {
    enum Phase: Equatable {
        case idle
        case countIn(Int)   // 1...4
        case running
        case finished
    }

    static let loopsPerSlowRung = 2

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var region: ClosedRange<TimeInterval>?
    @Published private(set) var feedbackId: UUID?
    /// 비어 있으면 사다리 없이 원래 속도로 반복만 한다.
    @Published private(set) var rungs: [Float] = []
    @Published private(set) var rungIndex = 0
    /// 지금 단계에서 돈 바퀴 수
    @Published private(set) var loopsDone = 0

    private weak var controller: StemPlayerController?
    private var countInTask: Task<Void, Never>?
    private let clicker = Clicker()
    private var useCountIn = false

    var isActive: Bool { phase != .idle }
    var hasLadder: Bool { !rungs.isEmpty }
    var currentRate: Float { rungs.isEmpty ? 1 : rungs[rungIndex] }
    /// 지금 단계에서 필요한 바퀴 수 (마지막 100%는 한 바퀴)
    var loopsNeeded: Int { rungIndex == rungs.count - 1 ? 1 : Self.loopsPerSlowRung }

    // MARK: - 시작 / 끝

    func start(region: ClosedRange<TimeInterval>, feedbackId: UUID?, controller: StemPlayerController,
               countIn: Bool, ladder: [Float]) {
        stop()
        self.controller = controller
        self.region = region
        self.feedbackId = feedbackId
        self.useCountIn = countIn
        rungs = ladder
        rungIndex = 0
        loopsDone = 0

        controller.pause()
        controller.loopRegion = region
        controller.isLoopEnabled = true
        controller.setPlaybackRate(currentRate)
        controller.seek(to: region.lowerBound)
        controller.onLoopWrap = { [weak self] in self?.loopWrapped() }
        begin()
    }

    /// 카운트인(켜져 있으면) 뒤 재생을 시작한다.
    private func begin() {
        guard let controller else { return }
        countInTask?.cancel()
        guard useCountIn else {
            phase = .running
            controller.play()
            return
        }
        countInTask = Task { [weak self] in
            guard let self else { return }
            let interval = max(0.45, 60.0 / ScoreSyncController.Song.hangHae.bpm / Double(self.currentRate))
            for beat in 1...4 {
                if Task.isCancelled { return }
                self.phase = .countIn(beat)
                self.clicker.click(accent: beat == 1)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
            if Task.isCancelled { return }
            self.phase = .running
            controller.play()
        }
    }

    /// 사다리 중간에 원하는 단계로 건너뛴다.
    func jump(to index: Int) {
        guard hasLadder, rungs.indices.contains(index), let controller, let region else { return }
        rungIndex = index
        loopsDone = 0
        controller.pause()
        controller.setPlaybackRate(currentRate)
        controller.seek(to: region.lowerBound)
        begin()
    }

    /// 한 번 더 (처음 단계부터)
    func restart() {
        guard let controller, let region else { return }
        start(region: region, feedbackId: feedbackId, controller: controller,
              countIn: useCountIn, ladder: rungs)
    }

    func stop() {
        countInTask?.cancel()
        countInTask = nil
        if let controller {
            controller.onLoopWrap = nil
            if phase != .idle {
                controller.pause()
                controller.setPlaybackRate(1)
            }
        }
        phase = .idle
        region = nil
        feedbackId = nil
        rungs = []
    }

    // MARK: - 한 바퀴가 끝났을 때

    private func loopWrapped() {
        guard phase == .running, let controller else { return }
        loopsDone += 1
        guard loopsDone >= loopsNeeded else { return }
        if hasLadder && rungIndex < rungs.count - 1 {
            rungIndex += 1
            loopsDone = 0
            controller.setPlaybackRate(currentRate)
        } else if hasLadder {
            finish()
        }
        // 사다리가 없으면 "그만"을 누를 때까지 반복한다.
    }

    private func finish() {
        guard let controller else { return }
        controller.onLoopWrap = nil
        controller.pause()
        controller.setPlaybackRate(1)
        phase = .finished
    }
}

/// 카운트인용 클릭 소리. 짧은 사인파를 메모리에서 만들어 AVAudioPlayer로 낸다 (메인 엔진과 별개).
private final class Clicker {
    private let normal = Clicker.make(frequency: 1000)
    private let accent = Clicker.make(frequency: 1600)

    func click(accent isAccent: Bool) {
        let player = isAccent ? accent : normal
        player?.currentTime = 0
        player?.play()
    }

    /// 70ms짜리 감쇠 사인파를 16bit mono WAV로 만들어 재생기에 담는다.
    private static func make(frequency: Double) -> AVAudioPlayer? {
        let sampleRate = 44100
        let count = Int(0.07 * Double(sampleRate))
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        let dataSize = UInt32(count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16))
        append(UInt16(1)); append(UInt16(1)); append(UInt32(sampleRate)); append(UInt32(sampleRate * 2))
        append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(dataSize)
        for i in 0..<count {
            let t = Double(i) / Double(sampleRate)
            let attack = min(1, t / 0.004)  // 부드러운 시작(클릭 노이즈 방지)
            let v = sin(2 * .pi * frequency * t) * exp(-t * 55) * attack * 0.85
            append(Int16(v * 32767))
        }
        let player = try? AVAudioPlayer(data: data)
        player?.prepareToPlay()
        return player
    }
}
