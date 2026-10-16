import SwiftUI

/// 모든 Feature 화면이 같이 쓰는 디자인 토큰. 색·간격·글자 크기는 여기서만 정한다.
/// (Feature 안에서 색 값을 직접 쓰지 않는다 — 디자인이 바뀌면 이 파일만 고치면 되도록)
public enum BandTheme {
    public enum Spacing {
        public static let small: CGFloat = 8
        public static let medium: CGFloat = 16
        public static let large: CGFloat = 24
    }

    /// 세션(악기)별 트랙 색
    public static func trackColor(for sessionKey: String) -> Color {
        switch sessionKey {
        case "vocals": .pink
        case "drums": .orange
        case "bass": .blue
        case "guitar": .red
        case "piano": .green
        default: .gray
        }
    }
}
