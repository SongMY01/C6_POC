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
│       │   ├── Feedback/         # 구간 피드백: 받는 세션 지정, 녹음 답변·코멘트 스레드, 겹침 묶음 표시
│       │   └── Score/            # 악보 PDF 표시, 재생 위치↔페이지 싱크
│       └── Resources/            # 악보 PDF
├── server/                       # FastAPI + Demucs(htdemucs_6s) 분리 서버 + 동기화 서버(sync.py)
│   └── data/                     #   업로드·분리 결과, sync/ 공유 상태 (git 미포함)
├── tools/seed_server.py          # 유저테스트용 샘플 피드백으로 동기화 서버 초기화
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
