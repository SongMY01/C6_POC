"""
유저테스트 버전(A/B/C …)을 모든 iPad에서 한 번에 전환한다. iPad는 3초 안에 반영.

  python tools/set_variant.py list            버전 목록
  python tools/set_variant.py get             지금 서버에 설정된 버전
  python tools/set_variant.py A               모든 iPad를 버전 A로
  python tools/set_variant.py clear            서버 설정 해제 (기본 버전으로)
  python tools/set_variant.py A --server http://172.20.10.2:8756

iPad의 ⚙️ 설정에서 "이 기기만 직접 선택"한 기기는 서버 전환을 따르지 않는다.
버전 id·이름은 앱의 AppVariant.swift와 같아야 한다.
"""
import json
import sys
import urllib.request

VARIANTS = {
    "base": "현재 프로토타입 (게임 요소 없음)",
    "A": "정복 지도 — 연습한 구간이 지도처럼 채워지는 성취 수집",
    "B": "같이 하는 밴드 — 지금 연습 중 · 리액션 · 칭호 · 팀 D-day 링",
    "C": "워밍업 챌린지 — 오늘의 구간 뽑기 · 카운트인 · 템포 사다리",
}

args = [a for a in sys.argv[1:] if not a.startswith("--")]
server = "http://127.0.0.1:8756"
if "--server" in sys.argv:
    server = sys.argv[sys.argv.index("--server") + 1]
    args = [a for a in args if a != server]
command = args[0] if args else "get"


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(server + path, data=data, method=method,
                                     headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=5) as r:
        return json.loads(r.read())


if command == "list":
    for key, name in VARIANTS.items():
        print(f"  {key:5} {name}")
elif command == "get":
    current = call("GET", "/sync/state?since=-1").get("variant")
    print(f"서버 설정 버전: {current or '(없음 → 기본)'}" + (f" — {VARIANTS.get(current, '?')}" if current else ""))
elif command == "clear":
    call("POST", "/sync/admin/variant", {"variant": None})
    print("서버 설정 해제 → 모든 iPad가 기본 버전")
else:
    key = next((k for k in VARIANTS if k.lower() == command.lower()), None)
    if key is None:
        sys.exit(f"알 수 없는 버전: {command} (list로 확인)")
    call("POST", "/sync/admin/variant", {"variant": key})
    print(f"모든 iPad → 버전 {key}: {VARIANTS[key]}")
