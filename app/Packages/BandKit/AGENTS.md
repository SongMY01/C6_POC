# BandKit — 작업 규칙

합주 앱의 TCA 패키지. 사람과 AI 에이전트가 같은 규칙으로 일한다.

## 모듈 지도

```
Foundation  ←  Services  ←  Features(Session·Player·Rehearsal·Sync·Practice)  ←  App
                  UI(디자인 토큰·공용 뷰)  ←  Features, App
```

| 모듈 | 들어 있는 것 | import 해도 되는 것 |
|---|---|---|
| `BandFoundation` | 데이터 모델, 순수 규칙(합의·채택·영역 편집) | 표준 라이브러리만 |
| `BandServices` | `@DependencyClient` 인터페이스 + live/test/preview 값 | Foundation, Dependencies |
| `BandUI` | 색·간격, 공용 뷰 | SwiftUI |
| `Band<Feature>` | Reducer + State/Action + View (+ 테스트) | Foundation, Services, UI, TCA |
| `BandApp` | `AppFeature`(Super), 연결 표 | 전부 |

- **Feature끼리는 서로 import하지 않는다.** `Package.swift`가 컴파일 단계에서 막는다.
- Feature 사이 연결은 `AppFeature`의 연결 표에서만 한다. 한 Feature가 다른 Feature에 알릴 일은 `delegate` 액션으로 내보낸다.
- 의존성이 필요한 새 외부 동작(네트워크·파일·오디오·시계)은 `BandServices`에 Client를 만들고 `@Dependency`로 쓴다. Reducer에서 `URLSession`, `Date()`, `UUID()`, `Task.sleep`를 직접 부르지 않는다.

## Feature 작성 규칙

1. `@Reducer` + `@ObservableState`. State는 `Equatable`, Action은 `Sendable`.
2. 사용자 의도는 `...Tapped`, 결과는 `...Received/Finished`, 부모에게 알리는 건 `delegate(Delegate)` 안(`@CasePathable`).
3. 재생 위치처럼 초당 여러 번 바뀌는 값은 State에 넣지 않는다(View가 `AudioClient.position` 스트림을 구독).
4. 오래 도는 Effect는 `cancellable(id:)`를 붙이고 끝내는 액션을 만든다.
5. 시간은 `@Dependency(\.continuousClock)`, 고유값은 `\.uuid`, 현재 시각은 `\.date`.
6. `me`(이 기기의 사람)는 `AppFeature`가 정해서 내려준다. Feature가 스스로 역할을 읽지 않는다.

## 테스트 규칙

- 새 Action을 만들면 `TestStore` 테스트를 같이 쓴다(Swift Testing, `@Test`).
- 연결 표를 바꾸면 `Tests/BandAppTests/AppFeatureTests.swift`도 같이 바꾼다.
- 주기 작업이 있는 테스트는 `TestClock`을 주입한다. 안 하면 "Unimplemented: ContinuousClock" 오류가 난다.
- 확인: `swift test` (이 폴더에서). 전부 초록이어야 PR을 연다.

## 소유

| 영역 | 담당 |
|---|---|
| 뼈대, `AppFeature`, 연결 표, Services 인터페이스, 이 문서 | Martin |
| Feature 내부(State/Action 세부, Reducer, View, 테스트) | 각 Feature 담당 팀원 |
| `Client`의 `liveValue`(기존 앱 코드 감싸기) | 해당 Feature 담당 팀원 |

Services의 인터페이스(함수 시그니처)를 바꿔야 하면 먼저 Martin과 이야기한다 — 여러 Feature가 같이 쓴다.

## 아직 남은 TODO

- `BandServices`의 `liveValue`는 전부 placeholder다. 기존 앱의 `SeparationService`, `SyncClient.shared`, `StemPlayerController`, `FeedbackStore/PatchStore/RegionStore`, `DeviceRole`, `SongCache`를 감싸서 채운다.
- `SyncFeature`: 서버에서 새로 받은 녹음 파일을 내려받은 뒤 적용하기.
- `RehearsalFeature`: 결론을 제안할 수 있는 사람의 범위(지금은 누구나).
- `BandApp/AppView.swift`와 각 Feature View.
