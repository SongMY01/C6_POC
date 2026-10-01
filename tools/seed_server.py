"""
유저테스트용 샘플 피드백으로 동기화 서버를 초기화한다 (모든 iPad에 그대로 반영됨).

  python tools/seed_server.py [서버주소=http://127.0.0.1:8756]

- 피드백 12개: 연습 필요 7 / 코멘트 요청 3 / 통과 2 (세션 골고루)
- 시도에 붙는 녹음은 5초짜리 안내음(가짜)이다 — 실제 연주로 바꾸려면 앱에서 녹음해서 올리면 된다.
- 기존 피드백·패치는 지워진다. 공유 곡(분리 결과)은 그대로.
"""
import json
import math
import struct
import subprocess
import sys
import tempfile
import time
import urllib.request
import uuid
import wave
from pathlib import Path

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8756"
REF = 978307200  # Swift Date 기준(2001-01-01)
now = time.time() - REF
DAY = 86400
tmp = Path(tempfile.mkdtemp())

# 5초 안내음 (220Hz → 330Hz), 앱 녹음과 같은 CAF(Float32, 48kHz mono)
wav = tmp / "tone.wav"
with wave.open(str(wav), "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(48000)
    w.writeframes(b"".join(struct.pack("<h", int(9000 * math.sin(2 * math.pi * (220 if i < 120000 else 330) * i / 48000)))
                           for i in range(48000 * 5)))
tone = tmp / "tone.caf"
subprocess.run(["afconvert", "-f", "caff", "-d", "LEF32", str(wav), str(tone)], check=True)

feedback, patches = [], []


def U():
    return str(uuid.uuid4()).upper()


def C(author, text, t):
    return {"id": U(), "author": author, "text": text, "createdAt": t}


def fb(start, end, targets, text, created, attempts=(), comments=(), passed_index=None):
    item = {"id": U(), "startTime": start, "endTime": end, "createdAt": created, "text": text,
            "targetSessionIds": targets, "attempts": [], "comments": list(comments)}
    for i, (session, t, cmts) in enumerate(attempts):
        pid = U()
        patches.append({"id": pid, "sessionId": session, "startTime": start, "endTime": end,
                        "createdAt": t, "sourceStart": 0, "isAdopted": passed_index == i})
        item["attempts"].append({"id": U(), "sessionId": session, "patchId": pid, "createdAt": t, "comments": list(cmts)})
    if passed_index is not None:
        item["passedAttemptId"] = item["attempts"][passed_index]["id"]
    feedback.append(item)


d0 = now - 5 * DAY
fb(8, 16, ["drums"], "인트로 하이햇이 너무 커요. 킥이랑 스네어가 묻혀요.", d0)
fb(21, 29, ["vocals"], "첫 소절 음정이 살짝 플랫이에요. 숨을 더 받치고 들어가 주세요.", d0 + 600,
   comments=[C("vocals", "혹시 키를 반음 내리는 건 어때요?", d0 + 3600), C("leader", "일단 원키로 한 번 더 해보고 결정해요", d0 + 4000)])
fb(45, 53, [], "벌스 1 전체적으로 템포가 조금씩 빨라져요. 다들 클릭 듣고 맞춰봐요.", d0 + 1200)
fb(58, 66, ["guitar"], "코드 전환할 때 뮤트가 안 돼서 지저분해요.", d0 + 1800)
fb(72, 80, ["bass"], "프리코러스 들어가기 전 베이스 필인이 너무 길어요. 두 박으로 줄여 주세요.", d0 + DAY,
   attempts=[("bass", d0 + 2 * DAY, [])])
fb(96, 104, ["guitar", "piano"], "코러스에서 기타랑 피아노 음역이 겹쳐요. 피아노는 한 옥타브 올려볼까요?", d0 + DAY + 600,
   attempts=[("piano", d0 + 2 * DAY + 300, [C("leader", "좋아요! 근데 왼손 베이스음은 빼주세요", d0 + 2 * DAY + 5000)]),
             ("piano", d0 + 3 * DAY, [])])
fb(128, 136, ["vocals"], "브릿지 고음 부분 가사 전달이 잘 안 돼요.", d0 + DAY + 1200,
   attempts=[("vocals", d0 + 3 * DAY + 700, [])])
fb(110, 118, ["drums"], "코러스 2 크래시 타이밍이 반 박 늦어요.", d0 + 2 * DAY,
   attempts=[("drums", d0 + 3 * DAY, [C("leader", "크래시는 맞았는데 이번엔 킥이 밀려요", d0 + 3 * DAY + 3000),
                                       C("drums", "메트로놈 켜고 다시 해볼게요", d0 + 3 * DAY + 3600)])])
fb(150, 158, ["guitar"], "솔로 앞부분 벤딩 음이 덜 올라가요.", d0 + 2 * DAY + 600,
   attempts=[("guitar", d0 + 3 * DAY + 1000, [C("leader", "많이 좋아졌어요. 마지막 음만 조금 더", d0 + 3 * DAY + 8000)]),
             ("guitar", d0 + 4 * DAY, [C("piano", "비브라토 조금 줄이면 더 깔끔할 것 같아요", d0 + 4 * DAY + 2000)])])
fb(33, 41, ["bass"], "벌스 베이스 라인에서 3번째 마디 음 틀렸어요 (E → F#).", d0 + 3 * DAY,
   attempts=[("bass", d0 + 3 * DAY + 2000, [C("leader", "음은 맞는데 박자가 앞으로 쏠려요", d0 + 3 * DAY + 4000)]),
             ("bass", d0 + 4 * DAY, [C("leader", "완벽해요 👍", d0 + 4 * DAY + 1000)])], passed_index=1)
fb(170, 178, ["piano"], "아웃트로 피아노 페달을 너무 오래 밟아서 뭉개져요.", d0 + 3 * DAY + 500,
   attempts=[("piano", d0 + 4 * DAY + 500, [C("leader", "딱 좋아요", d0 + 4 * DAY + 900)])], passed_index=0)
fb(200, 212, [], "마지막 엔딩 다 같이 끝 음 맞추기! 드럼 신호 보고 끊어요.", d0 + 4 * DAY,
   comments=[C("drums", "4박 카운트 후에 심벌 잡을게요", d0 + 4 * DAY + 300)])
feedback.sort(key=lambda f: f["startTime"])


def request(method, path, data=None, content_type="application/json"):
    req = urllib.request.Request(BASE + path, data=data, method=method, headers={"Content-Type": content_type})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read()


audio = tone.read_bytes()
for p in patches:
    request("PUT", f"/sync/patches/{p['id']}/audio", audio, "application/octet-stream")
print(request("POST", "/sync/admin/replace", json.dumps({"feedback": feedback, "patches": patches}).encode()).decode())
print(f"피드백 {len(feedback)}개, 패치 {len(patches)}개 → {BASE}")
