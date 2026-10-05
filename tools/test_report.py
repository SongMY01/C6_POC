"""
유저테스트 행동 기록 요약 (server/data/sync/events.jsonl).

  python tools/test_report.py

기기·버전별로 어떤 행동이 몇 번 있었는지, 곡을 연 뒤 첫 행동까지 걸린 시간을 보여준다.
"""
import json
from collections import defaultdict
from pathlib import Path

path = Path(__file__).resolve().parent.parent / "server" / "data" / "sync" / "events.jsonl"
if not path.exists():
    raise SystemExit("기록이 없습니다 (아직 앱에서 보낸 이벤트가 없음)")

events = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
events.sort(key=lambda e: e.get("serverTime", 0))

counts = defaultdict(lambda: defaultdict(int))
first_action = {}
song_open = {}
ACTIONS = {"record_start", "attempt_added", "comment_added", "feedback_open"}

for e in events:
    key = (e.get("variant", "?"), e.get("role", "?"), e.get("device", "?"))
    counts[key][e["name"]] += 1
    if e["name"] == "song_open":
        song_open[key] = e["serverTime"]
        first_action.pop(key, None)
    elif e["name"] in ACTIONS and key in song_open and key not in first_action:
        first_action[key] = e["serverTime"] - song_open[key]

print(f"이벤트 {len(events)}개\n")
for key in sorted(counts):
    variant, role, device = key
    wait = first_action.get(key)
    print(f"[버전 {variant}] {role} ({device})  곡 연 뒤 첫 행동까지: " + (f"{wait:.0f}초" if wait is not None else "-"))
    print("   " + ", ".join(f"{n} {c}" for n, c in sorted(counts[key].items())))
