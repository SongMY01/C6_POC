import SwiftUI
import PDFKit
import PencilKit

/// 지금 지정된 구간반복 구간(loopRegion)에 손글씨 메모를 남기는 화면.
/// 손글씨 POC와 같은 원리(페이지 고정 크기 렌더링 + 같은 크기 캔버스 겹치기)를
/// 재사용해서, 메모 위치가 화면 크기와 무관하게 항상 정확히 맞도록 한다.
struct FeedbackComposerSheet: View {
    let page: Int
    let timeRange: ClosedRange<TimeInterval>
    let document: PDFDocument?
    let onSave: (PKDrawing) -> Void
    let onCancel: () -> Void

    @State private var drawing = PKDrawing()

    // 캔버스 영역을 고정된 작은 크기로 잘라서(clip) 표시한다.
    // 페이지 전체 크기를 다 보여주려다 시트 크기가 매번 달라져서
    // 버튼 위치를 예측하기 어려웠던 문제를 없애기 위한 조치 —
    // 이 영역은 항상 이 크기이므로 버튼은 항상 바로 아래 고정된 위치에 온다.
    private let canvasWidth: CGFloat = 700
    private let canvasHeight: CGFloat = 620

    var body: some View {
        VStack(spacing: 16) {
            Text("\(formatted(timeRange.lowerBound)) ~ \(formatted(timeRange.upperBound)) 구간에 메모 남기기")
                .font(.headline)

            // 주의 (디버깅 기록):
            // 1) .scaleEffect로 축소 → PKCanvasView 터치 좌표 변환이 깨져서 그리기가 안 먹음
            // 2) ScrollView로 감싸서 원본 크기 유지 → ScrollView의 팬 제스처가
            //    한 손가락 드래그(그리기)를 스크롤로 가로채서 역시 안 그려짐
            // 3) 시트를 .large로 키워서 원본 크기 그대로 → 그리기는 되지만 시트
            //    전체 높이가 페이지 크기에 따라 달라져 버튼 위치 예측이 어려움
            // 그래서 캔버스를 고정 크기로 클립해서 보여준다 — 항상 같은 레이아웃.
            if let document, let pdfPage = document.page(at: page),
               let rendered = PDFPageRenderer.image(for: pdfPage) {
                ZStack(alignment: .topLeading) {
                    Image(uiImage: rendered.image)
                        .resizable()
                        .frame(width: rendered.size.width, height: rendered.size.height)
                    PageCanvasView(drawing: $drawing)
                        .frame(width: rendered.size.width, height: rendered.size.height)
                }
                .frame(width: canvasWidth, height: canvasHeight, alignment: .topLeading)
                .clipped()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))
            } else {
                Text("악보를 불러올 수 없습니다").foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Button("취소", action: onCancel)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                Button("피드백 저장") { onSave(drawing) }
                    .buttonStyle(.borderedProminent)
                    .disabled(drawing.strokes.isEmpty)
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .frame(width: canvasWidth)
        }
        .padding(24)
    }

    private func formatted(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}
