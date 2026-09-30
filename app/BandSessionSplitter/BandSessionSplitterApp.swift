import SwiftUI

@main
struct BandSessionSplitterApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}

/// 여러 POC를 한 앱에서 나란히 검증하기 위한 루트 탭.
struct RootTabView: View {
    var body: some View {
        TabView {
            ContentView()
                .tabItem { Label("세션 분리", systemImage: "waveform") }
            YouTubeSyncView()
                .tabItem { Label("유튜브 싱크", systemImage: "play.tv") }
            HandwritingScoreView()
                .tabItem { Label("손글씨", systemImage: "pencil.and.scribble") }
        }
    }
}
