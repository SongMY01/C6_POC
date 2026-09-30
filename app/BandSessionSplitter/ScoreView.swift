import SwiftUI
import PDFKit

/// PDFKit PDFView를 SwiftUI에서 쓰기 위한 래퍼.
/// 외부에서 지정한 페이지 인덱스로만 이동한다 (자동 넘김 주체는 ScoreSyncController).
struct PDFPageView: UIViewRepresentable {
    let document: PDFDocument
    let pageIndex: Int

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.displayMode = .singlePage
        view.autoScales = true
        view.displayDirection = .horizontal
        view.backgroundColor = .clear
        if let page = document.page(at: pageIndex) {
            view.go(to: page)
        }
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        guard let page = document.page(at: pageIndex) else { return }
        if uiView.currentPage !== page {
            uiView.go(to: page)
        }
    }
}

/// 녹음 재생 위치에 맞춰 자동으로 넘어가는 악보 화면 + 보정 UI.
struct ScoreView: View {
    @ObservedObject var scoreSync: ScoreSyncController
    /// 재생 중인 트랙의 현재 시각 (StemPlayerController.currentTime)
    let currentTime: TimeInterval

    @State private var document: PDFDocument?
    @State private var manualOverridePage: Int?
    /// 보정 모드 전용 "지금 몇 페이지째 보정 중인지" 커서.
    /// 자동계산(autoPageIndex)이 아직 안 맞는 상태일 수 있어서, 보정 중에는
    /// 화면이 그 틀린 자동계산을 따라가지 않고 이 커서만 따라가게 분리한다.
    @State private var calibrationCursor: Int = 0

    private var autoPageIndex: Int {
        scoreSync.pageIndex(for: currentTime)
    }

    private var displayedPageIndex: Int {
        if scoreSync.calibrationModeOn {
            return calibrationCursor
        }
        return manualOverridePage ?? autoPageIndex
    }

    var body: some View {
        VStack(spacing: 12) {
            if let document {
                PDFPageView(document: document, pageIndex: displayedPageIndex)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )
            } else {
                ContentUnavailableFallback()
            }

            controls
        }
        .onAppear(perform: loadDocument)
        .onChange(of: autoPageIndex) { _, _ in
            // 자동 페이지가 바뀌면 수동 오버라이드는 해제해 다시 재생 위치를 따라간다.
            manualOverridePage = nil
        }
    }

    private func loadDocument() {
        guard document == nil else { return }
        if let url = Bundle.main.url(forResource: scoreSync.song.pdfResourceName, withExtension: "pdf") {
            document = PDFDocument(url: url)
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(displayedPageIndex + 1) / \(scoreSync.pageCount) 페이지")
                    .font(.subheadline.weight(.semibold))
                if scoreSync.isCalibrated[displayedPageIndex] {
                    Label("보정됨", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Label("템포 추정", systemImage: "waveform.path.ecg")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button {
                    if scoreSync.calibrationModeOn {
                        calibrationCursor = max(0, calibrationCursor - 1)
                    } else {
                        manualOverridePage = max(0, displayedPageIndex - 1)
                    }
                } label: {
                    Image(systemName: "chevron.left.circle")
                }
                Button {
                    if scoreSync.calibrationModeOn {
                        calibrationCursor = min(scoreSync.pageCount - 1, calibrationCursor + 1)
                    } else {
                        manualOverridePage = min(scoreSync.pageCount - 1, displayedPageIndex + 1)
                    }
                } label: {
                    Image(systemName: "chevron.right.circle")
                }
            }

            if scoreSync.calibrationModeOn {
                HStack {
                    Button {
                        // 화면에 보이는 건 항상 calibrationCursor 페이지 —
                        // 자동계산(autoPageIndex)이 얼마나 틀려서 앞서/뒤처져 있든 상관없이,
                        // "지금 이 순간 = calibrationCursor+1 페이지 시작"으로 정확히 기록한다.
                        scoreSync.markNextPageStart(currentTime: currentTime, currentPageIndex: calibrationCursor)
                        calibrationCursor = min(calibrationCursor + 1, scoreSync.pageCount - 1)
                    } label: {
                        Label("지금 다음 페이지로 넘김 기록", systemImage: "hand.tap.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(calibrationCursor >= scoreSync.pageCount - 1)

                    Button("템포 기준으로 초기화", role: .destructive) {
                        scoreSync.resetToBaseline()
                        calibrationCursor = 0
                    }
                    .buttonStyle(.bordered)
                }
                Text("지금 보이는 페이지(\(calibrationCursor + 1)페이지)에서 다음 페이지로 넘어가야 할 실제 순간에 위 버튼을 누르세요. 화면은 자동계산을 따라가지 않고 이 보정 진행 상황만 보여줍니다.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Toggle("싱크 보정 모드", isOn: Binding(
                get: { scoreSync.calibrationModeOn },
                set: { newValue in
                    scoreSync.calibrationModeOn = newValue
                    if newValue { calibrationCursor = 0 }
                }
            ))
            .font(.caption)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(uiColor: .tertiarySystemBackground)))
    }
}

private struct ContentUnavailableFallback: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("악보 PDF를 불러올 수 없습니다")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
