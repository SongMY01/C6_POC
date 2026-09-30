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
│       │   ├── Feedback/         # 구간 피드백: 받는 세션 지정, 녹음 답변·코멘트 스레드, 겹침 묶음 표시
│       │   └── Score/            # 악보 PDF 표시, 재생 위치↔페이지 싱크
│       └── Resources/            # 악보 PDF
├── server/                       # FastAPI + Demucs(htdemucs_6s) 분리 서버
│   └── data/                     #   업로드·분리 결과 (git 미포함)
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
