import BandUI
import ComposableArchitecture
import SwiftUI

/// 앱의 루트 화면. 지금은 뼈대라서 각 Feature 화면이 들어갈 자리만 잡아 둔다.
/// 팀원이 자기 Feature의 View를 만들면 `// TODO(Feature)` 자리에 끼운다.
public struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>

    public init(store: StoreOf<AppFeature>) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: BandTheme.Spacing.medium) {
            // TODO(Session): 곡 고르기 · 분리 진행 화면
            // TODO(Player): 트랙 줄 · 재생바 · 믹서
            // TODO(Rehearsal): 핀 목록 · 핀 대화
            // TODO(Practice): 연습 사다리
            // TODO(Sync): 연결 상태 표시
            Text("BandKit skeleton")
        }
        .task { store.send(.task) }
    }
}
