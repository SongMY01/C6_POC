import Foundation
import AVFoundation

/// 짧은 효과음을 메모리에서 합성한다 (파일 없이). 메인 오디오 엔진과 별개인 AVAudioPlayer로 재생한다.
enum SoundSynth {
    struct Note {
        let frequency: Double
        /// 시작 시각(초)
        let start: Double
        /// 길이(초)
        let length: Double
        /// 지수 감쇠 속도 (클수록 빨리 사라짐)
        var decay: Double = 6
        var volume: Double = 0.8
    }

    /// 음표들을 겹쳐 하나의 소리로 합성한다.
    static func player(notes: [Note]) -> AVAudioPlayer? {
        let sampleRate = 44100
        let total = notes.map { $0.start + $0.length }.max() ?? 0
        var mix = [Double](repeating: 0, count: Int(total * Double(sampleRate)) + 1)
        for note in notes {
            let first = Int(note.start * Double(sampleRate))
            for i in 0..<Int(note.length * Double(sampleRate)) where first + i < mix.count {
                let t = Double(i) / Double(sampleRate)
                // 부드러운 시작(클릭 노이즈 방지) + 지수 감쇠
                let attack = min(1, t / 0.004)
                mix[first + i] += sin(2 * .pi * note.frequency * t) * exp(-t * note.decay) * attack * note.volume
            }
        }
        let peak = max(1, mix.map { abs($0) }.max() ?? 1)
        let samples = mix.map { Int16(($0 / peak) * 0.85 * 32767) }

        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        let dataSize = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16))
        append(UInt16(1)); append(UInt16(1)); append(UInt32(sampleRate)); append(UInt32(sampleRate * 2))
        append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(dataSize)
        for sample in samples { append(sample) }

        let player = try? AVAudioPlayer(data: data)
        player?.prepareToPlay()
        return player
    }

    /// 구간 정복 효과음: 도-미-솔-높은 도로 올라가는 짧은 차임.
    static func conquestChime() -> AVAudioPlayer? {
        let freqs: [Double] = [523.25, 659.25, 783.99, 1046.5]
        return player(notes: freqs.enumerated().map { index, f in
            Note(frequency: f, start: Double(index) * 0.11, length: index == 3 ? 0.9 : 0.4, decay: index == 3 ? 4.5 : 9)
        })
    }
}
