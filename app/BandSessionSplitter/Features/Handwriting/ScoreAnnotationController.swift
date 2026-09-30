import Foundation
import PencilKit

/// 페이지별 손글씨(PKDrawing)를 로컬에 영속화한다.
///
/// 좌표는 PDFPageRenderer가 만든 "PDF 페이지 자체의 포인트 크기" 프레임
/// 안에서 그려지므로, 저장된 PKDrawing을 다시 같은 크기 프레임에 올리면
/// 화면 크기·기기가 달라져도 위치가 그대로 맞는다.
@MainActor
final class ScoreAnnotationController: ObservableObject {
    private let baseDir: URL

    init(songTitle: String = "항해") {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("annotations", isDirectory: true)
            .appendingPathComponent(songTitle, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.baseDir = dir
    }

    private func fileURL(page: Int) -> URL {
        baseDir.appendingPathComponent("page_\(page).drawing")
    }

    func loadDrawing(page: Int) -> PKDrawing {
        guard let data = try? Data(contentsOf: fileURL(page: page)) else { return PKDrawing() }
        return (try? PKDrawing(data: data)) ?? PKDrawing()
    }

    func saveDrawing(_ drawing: PKDrawing, page: Int) {
        let url = fileURL(page: page)
        if drawing.strokes.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? drawing.dataRepresentation().write(to: url)
    }

    func clearDrawing(page: Int) {
        try? FileManager.default.removeItem(at: fileURL(page: page))
    }

    func hasDrawing(page: Int) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(page: page).path)
    }
}
