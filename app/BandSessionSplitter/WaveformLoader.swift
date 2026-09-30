import Foundation
import AVFoundation
import Accelerate

/// 트랙 레인에 그릴 파형(구간별 최대 진폭)을 백그라운드에서 계산한다.
enum WaveformLoader {
    static func peaks(url: URL, bins: Int) async -> [Float] {
        await Task.detached(priority: .utility) {
            computePeaks(url: url, bins: bins)
        }.value
    }

    private static func computePeaks(url: URL, bins: Int) -> [Float] {
        guard bins > 0, let file = try? AVAudioFile(forReading: url) else { return [] }
        let total = file.length
        guard total > 0 else { return [] }
        let framesPerBin = max(1, Int(total) / bins)
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(framesPerBin)) else { return [] }

        var peaks: [Float] = []
        peaks.reserveCapacity(bins + 1)
        while file.framePosition < total {
            do {
                try file.read(into: buffer, frameCount: AVAudioFrameCount(framesPerBin))
            } catch {
                break
            }
            let n = vDSP_Length(buffer.frameLength)
            guard n > 0, let channels = buffer.floatChannelData else { break }
            var peak: Float = 0
            for c in 0..<Int(format.channelCount) {
                var channelPeak: Float = 0
                vDSP_maxmgv(channels[c], 1, &channelPeak, n)
                peak = max(peak, channelPeak)
            }
            peaks.append(peak)
        }

        let maxPeak = peaks.max() ?? 0
        guard maxPeak > 0 else { return peaks }
        return peaks.map { $0 / maxPeak }
    }
}
