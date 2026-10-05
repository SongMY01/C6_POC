# 합주 세션 분리 PoC

합주 통합 녹음본을 세션(보컬·드럼·베이스·기타·피아노)별로 분리해서, iPad에서 GarageBand처럼
트랙별로 듣고 · 구간마다 특정 세션에게 텍스트 피드백을 남기고 · 내 세션만 구간 재녹음(패치)해서 비교해 보는 프로토타입.
검증 결과와 결정 사항은 [docs/PoC_요약.md](docs/PoC_요약.md) 참고.

## 디렉토리 구조

```
PoC/
├── app/                          # iPad SwiftUI 앱 (xcodegen)
│   ├── project.yml               # Xcode 프로젝트 정의 — .xcodeproj는 여기서 생성 (git 미포함)
│   └── BandSessionSplitter/
│       ├── App/                  # 앱 진입점, 세션 분리 흐름 화면, Info.plist
│       ├── Features/
│       │   ├── Separation/       # 분리 서버 클라이언트 + 업로드→분리→다운로드 흐름
│       │   ├── Player/           # 멀티트랙 플레이어 (GarageBand식 트랙 뷰)
│       │   │   ├── Model/        #   트랙·리전 모델, 리전/패치 편집 계산 규칙 (순수 로직)
│       │   │   ├── Audio/        #   AVAudioEngine 재생·편집 적용·구간 재녹음, 파형 계산
│       │   │   ├── Storage/      #   패치(재녹음본)·리전 편집 저장
│       │   │   └── Views/        #   트랙 화면, 레인, 헤더, 스타일
│       │   ├── Sync/             # 여러 iPad 동기화 클라이언트, 기기 역할(리더/세션)
│       │   ├── Variants/         # 유저테스트용 버전(A/B/C) 전환 틀 — 기능 플래그, 말투·녹음 횟수 규칙
│       │   ├── Practice/         # 오늘의 구간 뽑기, 카운트인, 템포 사다리(70→85→100%)
│       │   ├── Feedback/         # 구간 피드백: 받는 세션 지정, 녹음 답변·코멘트 스레드, 겹침 묶음 표시
│       │   └── Score/            # 악보 PDF 표시, 재생 위치↔페이지 싱크
│       └── Resources/            # 악보 PDF
├── server/                       # FastAPI + Demucs(htdemucs_6s) 분리 서버 + 동기화 서버(sync.py)
│   └── data/                     #   업로드·분리 결과, sync/ 공유 상태 (git 미포함)
├── tools/                        # 유저테스트 도구
│   ├── seed_server.py            #   샘플 피드백으로 동기화 서버 초기화
│   ├── set_variant.py            #   모든 iPad의 테스트 버전을 Mac에서 한 번에 전환
│   └── test_report.py            #   앱 행동 기록(이벤트) 요약
├── research/                     # 분리 품질 분석 스크립트 (오디오·결과물은 git 미포함)
└── docs/                         # PoC 검증 요약
```

## 실행

```bash
# 분리 서버 (PoC/ 에서)
source .venv/bin/activate
uvicorn server.server:app --host 0.0.0.0 --port 8756

# 앱 (app/ 에서) — 파일을 추가/이동했으면 다시 생성
xcodegen generate
open BandSessionSplitter.xcodeproj
```

- 시뮬레이터는 `127.0.0.1:8756`, 실기기는 Mac의 LAN IP로 접속한다 (`SessionViewModel.swift`의 기본값,
  앱 ⚙️에서 변경 가능). Mac IP 확인: `ipconfig getifaddr en0`
- 분석 스크립트는 `research/` 안에서 실행한다 (`input.m4a`, `separated/`를 상대 경로로 읽음).

## 유저테스트 (iPad 여러 대)

Mac이 동기화 서버 역할을 한다. 모든 기기가 같은 네트워크에 있어야 한다.

1. iPhone 개인용 핫스팟을 켜고 Mac과 iPad 4대를 모두 연결한다
   (학교·카페 Wi-Fi는 기기끼리 통신을 막는 경우가 많다).
2. Mac에서 서버 실행 — 잠자기 방지를 위해 `caffeinate`로 감싼다.
   ```bash
   caffeinate -i .venv/bin/uvicorn server.server:app --host 0.0.0.0 --port 8756
   ```
   macOS 방화벽이 "들어오는 연결 허용?"을 물으면 허용.
3. (선택) 샘플 피드백으로 초기화: `.venv/bin/python tools/seed_server.py`
4. 리더 iPad: 앱 첫 화면에서 역할 "👑 리더" → 녹음 파일 선택 → 분리 (한 번만).
   분리된 곡이 공유 곡이 된다. (이미 분리한 곡이 있으면 "합주 곡 열기")
5. 나머지 iPad: 역할을 각자 세션으로 고르고 "합주 곡 열기 (공유됨)".

- 서버 주소는 집 Wi-Fi / 학교 / 핫스팟(172.20.10.x) / Mac 인터넷 공유(192.168.2.1) 중 응답하는 곳을 자동으로 찾는다.
  안 되면 ⚙️에서 Mac IP(`ipconfig getifaddr en0`)를 직접 입력.
- 화면 왼쪽 위 역할 옆 점: 초록 = 동기화됨, 노랑 = 보내는 중, 빨강 = 서버 연결 안 됨(변경은 기기에 보관했다가 다시 연결되면 전송).
- 동기화되는 것: 피드백·시도·코멘트·통과, 재녹음(녹음 파일 포함), 곡에 반영 여부, 공유 곡.
  동기화되지 않는 것: 트랙 리전 편집(옮기기·자르기), 볼륨·뮤트, 악보 페이지 보정.

### 테스트 버전(A/B/C) 전환

한 앱 안에서 기능 묶음만 바꿔 끼운다. 같은 서버 데이터를 공유하므로 버전을 바꿔도 피드백·녹음은 그대로다.

```bash
.venv/bin/python tools/set_variant.py list     # 버전 목록
.venv/bin/python tools/set_variant.py A        # 모든 iPad를 A로 (3초 안에 반영)
.venv/bin/python tools/set_variant.py clear    # 기본 버전으로
```

- iPad 화면에는 이름 대신 코드(`버전 A`)만 작게 표시된다 (참가자가 의도를 짐작하지 않도록).
- ⚙️ 설정 → "테스트 버전"에서 이 기기만 따로 고정할 수 있다 (예: 2대는 A, 2대는 B로 비교). 고정한 기기는 서버 전환을 따르지 않는다.
- 새 게임 요소를 만들 때: `Variants/AppVariant.swift`의 `Feature`에 항목을 추가하고, 버전별 묶음에 넣고,
  화면에서는 `VariantStore.shared.isOn(.기능)`으로 켜고 끈다. 버전 id·이름은 `tools/set_variant.py`와 맞춘다.
- 행동 기록(앱 열기·곡 열기·피드백 열기·녹음 시작·시도 올리기·코멘트·통과)이 `server/data/sync/events.jsonl`에 쌓이고,
  `tools/test_report.py`로 기기·버전별 요약을 본다.

### 버전별로 켜지는 기능

| 기능(`Feature`) | 내용 | 버전 |
|---|---|---|
| `limitTwoTakes` | 피드백당 녹음 2번까지. 마지막 녹음을 올리면 자동 마무리(곡에 반영), "이 정도면 됐어요"는 누구나 | A B C |
| `friendlyWording` | "연습 필요 / 코멘트 요청 / 통과" → "해볼 차례 / 들어봐 주세요 / 준비 완료" 등 | A B C |
| `coverageMap` | 🗺 정복 지도: 곡 전체를 칸으로 나눠 피드백 구간을 해볼 곳(주황 테두리) → 진행 중(반투명) → 정복(세션 색)으로 채움. 내 몫만 셈(세션 연주자는 내 세션, 리더는 전체). 칸을 누르면 그 피드백이 열림 | A |
| `revealMoment` | 구간을 마무리하면 "처음 소리 → 지금 내 연주"를 구간 한 번씩 들려주고 "구간 정복!" 문구와 상승 차임 효과음 | A |
| `dailyPick` | 🎲 오늘의 구간 뽑기 (해볼 차례인 피드백 중 하나, 쉬움/보통/어려움·예상 시간 표시) | C |
| `startCountIn` | "바로 해보기" 시 하나·둘·셋·넷 클릭 소리와 함께 시작 | C |
| `tempoLadder` | 70% → 85% → 100% 속도로 구간 반복 (70·85%는 두 바퀴, 100%는 한 바퀴), 끝나면 "👏 해봤어요!" | C |

느린 재생은 트랙마다 타임스트레치 장치를 거친다(평소엔 우회). 느리게 재생할 때는 기기 시계 예약이 어긋나서
즉시 시작 + 무음 앞붙임 방식으로 맞춘다 — `StemPlayerController.play()`의 주석 참고.
