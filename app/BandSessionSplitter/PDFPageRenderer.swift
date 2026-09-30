import PDFKit
import UIKit

/// PDF 페이지를 "고정된 포인트 크기"의 이미지로 렌더링한다.
///
/// PDFView의 autoScales를 쓰면 화면 크기·줌 배율에 따라 페이지가
/// 화면에 그려지는 실제 크기가 계속 바뀌어서, 그 위에 손글씨 좌표를
/// 겹치기가 까다롭다. 그래서 손글씨 POC에서는 페이지 자체를 한 번
/// 고정 크기(PDF 자신의 포인트 크기)로 렌더링해 이미지로 쓰고,
/// PencilKit 캔버스를 정확히 같은 프레임으로 겹쳐서 좌표가 항상
/// 1:1로 맞게 만든다.
enum PDFPageRenderer {
    /// - Returns: 렌더링된 이미지와, 그 이미지가 나타내는 "포인트 크기"
    ///   (뷰에 .frame(width:height:)로 그대로 써야 좌표가 어긋나지 않는다)
    static func image(for page: PDFPage, scale: CGFloat = 2.0) -> (image: UIImage, size: CGSize)? {
        let bounds = page.bounds(for: .mediaBox)
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return nil }

        let pixelSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: pixelSize)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: pixelSize))

            let cg = ctx.cgContext
            cg.saveGState()
            // PDF 좌표계(원점 좌하단) -> UIKit 좌표계(원점 좌상단) 변환 + 배율 적용
            cg.translateBy(x: 0, y: pixelSize.height)
            cg.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: cg)
            cg.restoreGState()
        }
        return (image, size)
    }
}
