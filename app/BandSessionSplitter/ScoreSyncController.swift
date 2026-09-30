import Foundation
import Combine

/// 녹음 재생 위치 ↔ 악보 페이지 동기화.
///
/// 기본값은 악보에 적힌 템포(BPM)·마디 수로 계산한 "이론상" 페이지 시작 시각이다.
/// 하지만 실제 합주 녹음은 인트로 카운트인, 리핏 처리, 곡 해석에 따라
/// 표기 템포와 어긋나기 쉽다 (이번 곡: 이론상 188초 vs 실제 233초, ~19% 오차).
/// 그래서 재생 중 "지금 넘김"을 눌러 실제 시각으로 기준점을 덮어쓰는
/// 보정 모드를 함께 제공한다 — 한 번 보정하면 다음부터는 정확히 맞는다.
@MainActor
final class ScoreSyncController: ObservableObject {
    struct Song {
        let title: String
        let pdfResourceName: String   // Bundle 안의 파일명 (확장자 제외)
        let bpm: Double
        let beatsPerMeasure: Double
        let measuresPerPage: [Int]    // 페이지별 마디 수

        static let hangHae = Song(
            title: "항해",
            pdfResourceName: "항해",
            bpm: 185,
            beatsPerMeasure: 4,
            measuresPerPage: [20, 25, 24, 24, 28, 24]
        )
    }

    let song: Song
    let pageCount: Int

    /// 각 페이지가 "시작"하는 재생 시각(초). index 0 = 1페이지 시작(보통 0초).
    @Published private(set) var cueStartTimes: [TimeInterval]
    @Published private(set) var isCalibrated: [Bool]
    @Published var calibrationModeOn: Bool = false

    private let defaultsKey: String

    /// 같은 곡이라도 재생 소스(내 녹음 vs YouTube 원곡)에 따라 실제 템포·편곡이
    /// 다를 수 있어 보정값을 따로 저장한다.
    init(song: Song = .hangHae, source: String = "default") {
        self.song = song
        self.pageCount = song.measuresPerPage.count
        self.defaultsKey = "scoreCueTimes.\(song.title).\(source)"

        let baseline = Self.baselineCueTimes(song: song)
        if let saved = UserDefaults.standard.array(forKey: defaultsKey) as? [Double], saved.count == baseline.count {
            self.cueStartTimes = saved
            self.isCalibrated = saved.enumerated().map { i, v in v != baseline[i] || i == 0 }
        } else {
            self.cueStartTimes = baseline
            self.isCalibrated = Array(repeating: false, count: baseline.count)
        }
    }

    private static func baselineCueTimes(song: Song) -> [TimeInterval] {
        let secondsPerMeasure = 60.0 / song.bpm * song.beatsPerMeasure
        var result: [TimeInterval] = []
        var cumulativeMeasures = 0
        for count in song.measuresPerPage {
            result.append(Double(cumulativeMeasures) * secondsPerMeasure)
            cumulativeMeasures += count
        }
        return result
    }

    /// 현재 재생 시각에 맞는 페이지 인덱스(0-based)를 계산.
    func pageIndex(for time: TimeInterval) -> Int {
        var page = 0
        for (i, start) in cueStartTimes.enumerated() {
            if time >= start { page = i } else { break }
        }
        return page
    }

    /// 보정 모드: "지금 넘김" — 다음 페이지의 시작 시각을 현재 재생 시각으로 기록.
    func markNextPageStart(currentTime: TimeInterval, currentPageIndex: Int) {
        let nextPage = currentPageIndex + 1
        guard nextPage < cueStartTimes.count else { return }
        cueStartTimes[nextPage] = currentTime
        isCalibrated[nextPage] = true
        persist()
    }

    func resetToBaseline() {
        cueStartTimes = Self.baselineCueTimes(song: song)
        isCalibrated = Array(repeating: false, count: cueStartTimes.count)
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    private func persist() {
        UserDefaults.standard.set(cueStartTimes, forKey: defaultsKey)
    }
}
