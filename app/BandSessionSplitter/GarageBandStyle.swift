import SwiftUI

/// GarageBand 트랙 뷰 느낌의 색·버튼 스타일과 트랙별 색/아이콘.
enum GB {
    static let background = Color(white: 0.11)
    static let toolbar = Color(white: 0.17)
    static let panel = Color(white: 0.24)
    static let headerColumn = Color(white: 0.15)
    static let headerSelected = Color(white: 0.27)
    static let lane = Color(white: 0.12)
    static let laneSelected = Color(white: 0.16)
    static let ruler = Color(white: 0.2)
    static let cycle = Color(red: 1.0, green: 0.8, blue: 0.1)
    static let muteOn = Color(red: 0.3, green: 0.6, blue: 1.0)
}

struct GBToolButtonStyle: ButtonStyle {
    var isOn: Bool = false
    var onColor: Color = .accentColor
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(isOn ? onColor : Color.white.opacity(isEnabled ? 0.9 : 0.35))
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 9).fill(GB.panel.opacity(configuration.isPressed ? 0.6 : 1)))
    }
}

struct GBTransportButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 24, weight: .bold))
            .foregroundStyle(Color.white.opacity(isEnabled ? 1 : 0.35))
            .frame(width: 64, height: 46)
            .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0))
            .opacity(isEnabled ? 1 : 0.5)
    }
}

extension StemTrack {
    var tint: Color {
        switch colorName {
        case "vocals": return Color(red: 0.85, green: 0.3, blue: 0.45)
        case "drums": return Color(red: 0.9, green: 0.55, blue: 0.15)
        case "bass": return Color(red: 0.6, green: 0.35, blue: 0.85)
        case "guitar": return Color(red: 0.2, green: 0.65, blue: 0.3)
        case "piano": return Color(red: 0.2, green: 0.5, blue: 0.9)
        default: return .gray
        }
    }

    var instrumentEmoji: String {
        switch colorName {
        case "vocals": return "🎤"
        case "drums": return "🥁"
        case "bass": return "🎸"
        case "guitar": return "🎸"
        case "piano": return "🎹"
        default: return "🎵"
        }
    }
}

func formatTime(_ t: TimeInterval) -> String {
    guard t.isFinite, t >= 0 else { return "0:00" }
    return String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
}
