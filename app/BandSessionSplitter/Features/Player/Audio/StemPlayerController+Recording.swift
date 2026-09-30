import Foundation
import AVFoundation

// MARK: - 구간 재녹음 (재생 + 마이크 동시 녹음)
//
// 재생과 녹음이 같은 AVAudioEngine의 같은 시계를 쓰기 때문에
// "레퍼런스를 들으며 그 위에 다시 연주해서 녹음"이 프레임 단위로 어긋나지 않는다.
// 흐름: 권한 → playAndRecord 세션 → 준비 시간(pre-roll) 재생 → 구간 시작부터 탭으로 녹음
//      → 정지 → 재생 전용 엔진으로 재구성 → 지연 보정 → "들어보기/저장/다시 녹음" 대기.

extension StemPlayerController {
    enum PatchRecordingError: LocalizedError {
        case permissionDenied
        case inputUnavailable
        case step(String, Error)

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "마이크 권한이 거부됨 — 설정 → 개인정보 보호 → 마이크에서 이 앱을 켜주세요."
            case .inputUnavailable:
                return "마이크 입력을 찾을 수 없음 (입력 포맷 샘플레이트 0)"
            case let .step(name, error):
                let ns = error as NSError
                return "\(name) 단계 실패: \(ns.localizedDescription) [\(ns.domain) \(ns.code)]"
            }
        }
    }

    /// 녹음 종료 후, 저장하기 전에 "미리듣기 → 저장 / 다시 녹음"을 고르는 대기 상태.
    struct PendingPatchRecording {
        let trackId: String
        let region: ClosedRange<TimeInterval>
        let tempURL: URL
    }

    /// 녹음 시작 전 레퍼런스가 먼저 흘러나오는 준비 시간(count-in). 이 구간은 녹음되지 않는다.
    private static let recordingPreRoll: TimeInterval = 2.0
    /// 구간 끝나고도 자동으로 끊기지 않고 여유를 두는 시간(잘라내기 편하도록 여백을 둔다).
    private static let recordingTailMargin: TimeInterval = 1.0

    private func recordingStep<T>(_ name: String, _ body: () throws -> T) throws -> T {
        do { return try body() } catch { throw PatchRecordingError.step(name, error) }
    }

    private func requestRecordPermission() async -> Bool {
        await withCheckedContinuation { cont in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in cont.resume(returning: granted) }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in cont.resume(returning: granted) }
            }
        }
    }

    /// target 세션의 region 구간을 재녹음한다. target 자신의 소리는 뮤트하고
    /// 나머지 세션을 레퍼런스로 재생하면서, 동시에 마이크를 녹음한다.
    func startPatchRecording(target: StemTrack, region: ClosedRange<TimeInterval>) async throws {
        guard await requestRecordPermission() else { throw PatchRecordingError.permissionDenied }
        do {
            try beginPatchRecording(target: target, region: region)
        } catch {
            // 중간에 실패하면 뮤트/세션/엔진을 원래 재생 상태로 되돌린다.
            if let (track, wasMuted) = recordingMutedTrack { track.isMuted = wasMuted }
            recordingMutedTrack = nil
            recordingFile = nil
            isRecording = false
            rebuildEngineForPlayback()
            throw error
        }
    }

    private func beginPatchRecording(target: StemTrack, region: ClosedRange<TimeInterval>) throws {
        if !recordingSessionConfigured {
            // 녹음이 가능하려면 카테고리를 playAndRecord로 올려야 한다.
            // 엔진이 돌고 있는 채로 카테고리를 바꾸면 그래프가 깨질 수 있어 잠깐 멈췄다 다시 시작한다.
            engine.stop()
            let session = AVAudioSession.sharedInstance()
            try recordingStep("세션 카테고리 설정") {
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            }
            try recordingStep("세션 활성화") { try session.setActive(true) }
            // inputNode는 처음 접근할 때 그래프에 추가된다. 엔진이 돌고 있을 때 처음 접근하면
            // 그래프가 재구성되며 시작이 꼬일 수 있어, 멈춘 상태에서 먼저 만들어 둔다.
            _ = engine.inputNode
            engine.prepare()
            try recordingStep("엔진 재시작") { try engine.start() }
            recordingSessionConfigured = true
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw PatchRecordingError.inputUnavailable }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("patch_rec_\(UUID().uuidString).caf")
        let file = try recordingStep("녹음 파일 생성") {
            try AVAudioFile(forWriting: tempURL, settings: inputFormat.settings)
        }
        recordingFile = file
        recordingTempURL = tempURL

        recordingMutedTrack = (target, target.isMuted)
        target.isMuted = true

        // 구간 밖에서도 레퍼런스가 잘리지 않도록 반복은 끄고 한 번만 재생.
        isLoopEnabled = false
        loopRegion = region
        let preRollStart = max(0, region.lowerBound - Self.recordingPreRoll)
        seek(to: preRollStart)
        play()

        // 준비 시간(count-in)이 지나 구간 시작에 도달하면 그때부터 탭을 걸어 녹음 시작.
        let actualPreRoll = region.lowerBound - preRollStart
        isRecording = true
        DispatchQueue.main.asyncAfter(deadline: .now() + actualPreRoll) { [weak self] in
            guard let self, self.isRecording, self.recordingFile != nil else { return }
            inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
                try? self?.recordingFile?.write(from: buffer)
            }
        }

        // 구간 끝 + 여백까지도 안 멈추면 자동으로 정지.
        let regionLength = region.upperBound - region.lowerBound
        DispatchQueue.main.asyncAfter(deadline: .now() + actualPreRoll + regionLength + Self.recordingTailMargin) { [weak self] in
            guard let self, self.isRecording else { return }
            self.stopPatchRecording()
        }
    }

    /// 녹음을 멈추고 "미리듣기 → 저장/다시 녹음" 대기 상태로 전환한다.
    func stopPatchRecording() {
        guard isRecording else { return }
        if recordingFile != nil { engine.inputNode.removeTap(onBus: 0) }
        let finishedFile = recordingFile
        recordingFile = nil // 닫히면서 디스크에 flush됨
        isRecording = false

        if let (track, wasMuted) = recordingMutedTrack {
            track.isMuted = wasMuted
        }
        let trackId = recordingMutedTrack?.track.id
        recordingMutedTrack = nil

        pause()

        // .playAndRecord 상태로 계속 두면 이후 일반 재생에서 소리가 끊겼다 나왔다 하는
        // 문제가 있어서, 녹음이 끝나면 재생 전용 세션·엔진으로 되돌린다.
        let session = AVAudioSession.sharedInstance()
        let totalLatency = session.inputLatency + session.outputLatency
        rebuildEngineForPlayback()

        guard let trackId, let tempURL = recordingTempURL, finishedFile != nil else { return }
        let region = loopRegion ?? (0...0)
        let alignedURL = Self.latencyCompensated(tempURL: tempURL, latency: totalLatency)
        pendingRecording = PendingPatchRecording(trackId: trackId, region: region, tempURL: alignedURL)
    }

    /// 입력+출력 지연시간만큼 녹음 파일 앞부분을 잘라내서, 실제로 들린 레퍼런스 타이밍에
    /// 더 가깝게 맞춘다 (마이크가 실제로 소리를 "들은" 시점은 스피커가 소리를 낸 시점보다
    /// outputLatency만큼 늦고, 그 소리가 버퍼에 기록되기까지 inputLatency만큼 더 늦는다).
    private static func latencyCompensated(tempURL: URL, latency: TimeInterval) -> URL {
        guard latency > 0, let source = try? AVAudioFile(forReading: tempURL) else { return tempURL }
        let trimFrames = AVAudioFramePosition(latency * source.processingFormat.sampleRate)
        guard trimFrames > 0, trimFrames < source.length else { return tempURL }

        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent("patch_rec_trimmed_\(UUID().uuidString).caf")
        guard let dest = try? AVAudioFile(forWriting: outURL, settings: source.fileFormat.settings),
              let buffer = AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: AVAudioFrameCount(source.length - trimFrames))
        else { return tempURL }

        source.framePosition = trimFrames
        guard (try? source.read(into: buffer)) != nil, (try? dest.write(from: buffer)) != nil else { return tempURL }
        try? FileManager.default.removeItem(at: tempURL)
        return outURL
    }

    /// 대기 중인 녹음을 그냥 재생해서 들어본다 (메인 엔진과 무관한 별도 플레이어).
    func previewPendingRecording() {
        guard let pending = pendingRecording else { return }
        previewPlayer = try? AVAudioPlayer(contentsOf: pending.tempURL)
        previewPlayer?.play()
    }

    /// 대기 중인 녹음을 버리고 처음부터 다시 녹음할 수 있게 한다.
    func discardPendingRecording() {
        guard let pending = pendingRecording else { return }
        try? FileManager.default.removeItem(at: pending.tempURL)
        clearPendingRecording()
    }

    /// 대기 상태를 비운다. 저장(파일 이동/manifest 기록)은 PatchStore가 한 뒤 호출한다.
    func clearPendingRecording() {
        previewPlayer?.stop()
        previewPlayer = nil
        pendingRecording = nil
    }
}
