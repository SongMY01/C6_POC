import SwiftUI
import PencilKit

/// PKCanvasView를 SwiftUI에서 쓰기 위한 래퍼.
/// 애플펜슬 + 손가락 모두 허용(시뮬레이터/실기기 테스트 편의를 위해),
/// 그려질 때마다 바인딩된 drawing을 갱신한다.
struct PageCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawing = drawing
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if canvas.drawing != drawing {
            canvas.drawing = drawing
        }
        // 캔버스가 화면에 붙은 뒤 도구 팔레트를 띄운다.
        DispatchQueue.main.async {
            guard let window = canvas.window else { return }
            canvas.becomeFirstResponder()
            let toolPicker = PKToolPicker.shared(for: window)
            toolPicker?.setVisible(true, forFirstResponder: canvas)
            toolPicker?.addObserver(canvas)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PageCanvasView
        init(_ parent: PageCanvasView) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}
