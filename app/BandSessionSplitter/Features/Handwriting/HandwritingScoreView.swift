import SwiftUI
import PDFKit
import PencilKit

/// POC: 악보 위에 손글씨를 쓰고, 그 위치가 페이지별로 저장/복원되는지 검증.
///
/// 페이지를 고정 포인트 크기 이미지로 렌더링 + 같은 크기 캔버스를 겹치는
/// 방식이라, 화면 회전/기기가 달라져도(scaleEffect로 비율만 조정) 저장된
/// 좌표가 항상 원래 위치에 그대로 맞는다.
struct HandwritingScoreView: View {
    @StateObject private var annotations = ScoreAnnotationController()
    @State private var document: PDFDocument?
    @State private var pageIndex: Int = 0
    @State private var currentDrawing = PKDrawing()

    private let pageCount = ScoreSyncController.Song.hangHae.measuresPerPage.count

    var body: some View {
        VStack(spacing: 16) {
            Text("악보 위 손글씨 메모 (페이지별 위치 자동 저장)")
                .font(.headline)

            canvasArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))

            controls
        }
        .padding(24)
        .onAppear(perform: loadDocumentIfNeeded)
        .onChange(of: currentDrawing) { _, newValue in
            annotations.saveDrawing(newValue, page: pageIndex)
        }
    }

    private var canvasArea: some View {
        GeometryReader { geo in
            if let document,
               let page = document.page(at: pageIndex),
               let rendered = PDFPageRenderer.image(for: page) {
                let scale = min(geo.size.width / rendered.size.width, geo.size.height / rendered.size.height, 1.0)
                ZStack {
                    Image(uiImage: rendered.image)
                        .resizable()
                        .frame(width: rendered.size.width, height: rendered.size.height)
                    PageCanvasView(drawing: $currentDrawing)
                        .frame(width: rendered.size.width, height: rendered.size.height)
                }
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
            } else {
                Text("악보 PDF를 불러올 수 없습니다").foregroundStyle(.secondary)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button { changePage(to: pageIndex - 1) } label: {
                Image(systemName: "chevron.left.circle.fill")
            }
            .disabled(pageIndex == 0)

            Text("\(pageIndex + 1) / \(pageCount) 페이지")
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 90)

            Button { changePage(to: pageIndex + 1) } label: {
                Image(systemName: "chevron.right.circle.fill")
            }
            .disabled(pageIndex == pageCount - 1)

            if annotations.hasDrawing(page: pageIndex) {
                Label("이 페이지에 저장된 메모 있음", systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Spacer()

            Button("이 페이지 지우기", role: .destructive) {
                currentDrawing = PKDrawing()
                annotations.clearDrawing(page: pageIndex)
            }
            .buttonStyle(.bordered)
        }
        .font(.title2)
    }

    private func loadDocumentIfNeeded() {
        if document == nil, let url = Bundle.main.url(forResource: "항해", withExtension: "pdf") {
            document = PDFDocument(url: url)
        }
        currentDrawing = annotations.loadDrawing(page: pageIndex)
    }

    private func changePage(to newIndex: Int) {
        guard newIndex >= 0, newIndex < pageCount else { return }
        pageIndex = newIndex
        currentDrawing = annotations.loadDrawing(page: pageIndex)
    }
}
