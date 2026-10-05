import Foundation

/// 테스트할 수 있는 기능 하나. 게임 요소를 만들 때마다 여기에 추가하고,
/// 화면에서는 `VariantStore.shared.isOn(.feature)`로 켜고 끈다.
/// (아직 구현되지 않은 기능도 미리 이름을 정해 두었다 — 구현되면 그 화면에서 이 값을 확인하면 된다.)
enum Feature: String, CaseIterable {
    // 공통 기반
    case limitTwoTakes      // 피드백당 녹음 2번까지, 2번째에서 자동 완료
    case friendlyWording    // "연습 필요/통과" → "합주 때 만나요/준비 완료" 같은 친근한 말투

    // A. 정복 지도
    case coverageMap        // 곡 타임라인이 지도처럼, 연습한 구간이 색으로 채워짐
    case revealMoment       // 끝나면 원본 → 내 연주 비포/애프터 + 완료 사운드

    // B. 같이 하는 밴드
    case presence           // "베이스 지금 연습 중" 실시간 표시
    case reactions          // 🔥🎯👏 리액션 스티커 (리더 컨펌 대신)
    case peerTitles         // 동료가 붙여 주는 칭호
    case teamRing           // 다음 합주 D-day 팀 진행 링

    // C. 워밍업 챌린지
    case dailyPick          // 오늘의 구간 뽑기
    case startCountIn       // 카운트인으로 바로 시작
    case tempoLadder        // 70% → 85% → 100% 템포 사다리
}

/// 유저테스트용 앱 버전. 한 앱 안에서 기능 묶음만 바꿔 끼운다 — 같은 서버 데이터를 공유하므로
/// 버전을 바꿔도 피드백·녹음은 그대로이고, 같은 조건에서 비교할 수 있다.
///
/// id·이름은 tools/set_variant.py 와 같아야 한다.
struct AppVariant: Identifiable, Equatable {
    let id: String
    /// 화면에 작게 표시하는 코드 (참가자가 의도를 짐작하지 않도록 이름 대신 코드만 보여준다)
    let code: String
    let name: String
    let summary: String
    let features: Set<Feature>

    static let base = AppVariant(
        id: "base", code: "기본", name: "현재 프로토타입",
        summary: "게임 요소 없음 (비교 기준)", features: []
    )

    static let all: [AppVariant] = [
        base,
        AppVariant(
            id: "A", code: "A", name: "정복 지도",
            summary: "연습한 구간이 지도처럼 채워지는 성취 수집",
            features: [.limitTwoTakes, .friendlyWording, .coverageMap, .revealMoment]
        ),
        AppVariant(
            id: "B", code: "B", name: "같이 하는 밴드",
            summary: "지금 연습 중 · 리액션 · 칭호 · 팀 D-day 링",
            features: [.limitTwoTakes, .friendlyWording, .presence, .reactions, .peerTitles, .teamRing]
        ),
        AppVariant(
            id: "C", code: "C", name: "워밍업 챌린지",
            summary: "오늘의 구간 뽑기 · 카운트인 · 템포 사다리",
            features: [.limitTwoTakes, .friendlyWording, .dailyPick, .startCountIn, .tempoLadder]
        ),
    ]

    static func find(_ id: String?) -> AppVariant? {
        guard let id else { return nil }
        return all.first { $0.id.lowercased() == id.lowercased() }
    }
}

/// 이 iPad가 지금 어떤 버전인지.
/// 우선순위: ⚙️에서 "이 기기만 직접 선택" > 서버(진행자가 Mac에서 전환) > 기본.
@MainActor
final class VariantStore: ObservableObject {
    static let shared = VariantStore()

    private static let overrideKey = "variantOverride"

    /// 서버가 알려 준 버전 id (SyncClient가 채운다)
    @Published var serverVariantId: String? {
        didSet { publishFeatures() }
    }
    /// 이 기기만 직접 고른 버전 id. nil이면 서버를 따른다.
    @Published private(set) var overrideId: String? = UserDefaults.standard.string(forKey: VariantStore.overrideKey) {
        didSet { publishFeatures() }
    }

    private init() {
        publishFeatures()
    }

    var current: AppVariant {
        AppVariant.find(overrideId) ?? AppVariant.find(serverVariantId) ?? .base
    }

    var isFollowingServer: Bool { AppVariant.find(overrideId) == nil }

    func isOn(_ feature: Feature) -> Bool {
        current.features.contains(feature)
    }

    func setOverride(_ id: String?) {
        overrideId = id
        UserDefaults.standard.set(id, forKey: Self.overrideKey)
    }

    // MARK: 어느 곳에서든 읽을 수 있는 기능 목록
    //
    // 열거형의 계산 속성(말투 등)은 메인 액터 밖에서도 불리므로, 현재 버전의 기능 목록을
    // 잠금 없이 읽을 수 있는 곳에도 복사해 둔다. 값은 메인 스레드에서만 바뀌고 읽기만 흔하다.
    nonisolated(unsafe) private static var activeFeatures: Set<Feature> = []

    private func publishFeatures() {
        Self.activeFeatures = current.features
    }

    /// 화면 코드 어디서든 쓸 수 있는 확인 함수.
    nonisolated static func enabled(_ feature: Feature) -> Bool {
        activeFeatures.contains(feature)
    }
}
