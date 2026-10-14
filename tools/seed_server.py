"""
유저테스트용 샘플 피드백으로 동기화 서버를 초기화한다 (모든 iPad에 그대로 반영됨).

  python tools/seed_server.py [서버주소=http://127.0.0.1:8756]
  (피드백·코멘트는 한국어 원문 + 영어 번역을 함께 넣는다 — 앱 표시 언어에 따라 골라 보인다)

- 피드백 14개: 박자 · 볼륨·밸런스 · 하모니 · 표현 · 그 외 종류별로, 연습 필요 / 코멘트 요청 / 통과 골고루
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


def T(pair):
    """(한국어, 영어) → 한국어 원문 + 영어 번역. 앱이 표시 언어에 맞춰 고른다."""
    ko, en = pair
    return ko, {"en": en}


def C(author, pair, created_at):
    text, tr = T(pair)
    return {"id": U(), "author": author, "text": text, "translations": tr, "createdAt": created_at}


def fb(start, end, targets, pair, created, kind=None, mix=None, reference=None, confirmed=(),
       attempts=(), comments=(), passed_index=None):
    """reference: 시범 녹음을 올릴 세션 id (음·연주 피드백). mix: 밸런스 피드백의 목표 믹스."""
    text, tr = T(pair)
    item = {"id": U(), "startTime": start, "endTime": end, "createdAt": created, "text": text, "translations": tr,
            "targetSessionIds": targets, "attempts": [], "comments": list(comments), "confirmedBy": list(confirmed)}
    if kind:
        item["kind"] = kind
    if mix:
        item["targetMix"] = mix
    if reference:
        pid = U()
        patches.append({"id": pid, "sessionId": reference, "startTime": start, "endTime": end,
                        "createdAt": created, "sourceStart": 0, "isAdopted": False, "isReference": True})
        item["referencePatchId"] = pid
    for i, (session, t, cmts) in enumerate(attempts):
        pid = U()
        patches.append({"id": pid, "sessionId": session, "startTime": start, "endTime": end,
                        "createdAt": t, "sourceStart": 0, "isAdopted": passed_index == i})
        item["attempts"].append({"id": U(), "sessionId": session, "patchId": pid, "createdAt": t, "comments": list(cmts)})
    if passed_index is not None:
        item["passedAttemptId"] = item["attempts"][passed_index]["id"]
    feedback.append(item)


d0 = now - 5 * DAY
LOUD = {"vocals": 0.85, "drums": 0.7, "bass": 0.8, "guitar": 0.8, "piano": 0.8}
# 문장은 앱 작성 화면(FeedbackComposerSheet)이 만드는 형식 그대로 쓴다.

# 볼륨·밸런스: 목표 믹스가 같이 간다
fb(8, 16, ["drums"],
   ("이 구간에서 드럼이 많이 튀어요.", "In this section: Drums — sticking out a lot."),
   d0, kind="balance", mix={**LOUD, "drums": 0.45},
   comments=[C("drums", ("하이햇 세기 줄여서 다시 쳐볼게요", "I'll bring the hi-hat down and play it again"), d0 + 1500)])
fb(96, 104, ["guitar", "piano"],
   ("이 구간에서 기타가 조금 튀어요, 피아노가 많이 묻혀요.", "In this section: Guitar — slightly sticking out, Piano — very buried."),
   d0 + DAY + 600, kind="balance", mix={**LOUD, "guitar": 0.6, "piano": 1.0},
   attempts=[("piano", d0 + 2 * DAY + 300, [C("leader", ("좋아요! 근데 왼손 베이스음은 빼주세요", "Nice! But please drop the left-hand bass notes."), d0 + 2 * DAY + 5000)]),
             ("piano", d0 + 3 * DAY, [])])
# 박자: 마디·박마다 빨라요/느려요
fb(45, 53, [],
   ("마디 2의 3박, 마디 2의 4박이 빨라요.", "Bar 2 beat 3, Bar 2 beat 4: rushing."),
   d0 + 1200, kind="tempo",
   comments=[C("piano", ("저도 여기서 같이 달려가는 느낌이에요", "I feel like I rush along with it here too."), d0 + 2000)])
fb(110, 118, ["drums"],
   ("마디 1의 1박이 느려요.", "Bar 1 beat 1: dragging."),
   d0 + 2 * DAY, kind="tempo",
   attempts=[("drums", d0 + 3 * DAY, [C("leader", ("크래시는 맞았는데 이번엔 킥이 밀려요", "The crash is right, but now the kick is dragging."), d0 + 3 * DAY + 3000),
                                       C("drums", ("메트로놈 켜고 다시 해볼게요", "I'll try again with the metronome on."), d0 + 3 * DAY + 3600)])])
# 하모니: 박마다 칠 코드
fb(33, 41, ["bass"],
   ("C | C | Am | Am 코드로 쳐 주세요.", "Please play C | C | Am | Am."),
   d0 + 3 * DAY, kind="harmony",
   attempts=[("bass", d0 + 3 * DAY + 2000, [C("leader", ("음은 맞는데 박자가 앞으로 쏠려요", "The notes are right, but the timing is rushing."), d0 + 3 * DAY + 4000)]),
             ("bass", d0 + 4 * DAY, [C("leader", ("완벽해요 👍", "Perfect 👍"), d0 + 4 * DAY + 1000)])], passed_index=1)
fb(72, 80, ["bass"],
   ("F | F | G | G 코드로 쳐 주세요.", "Please play F | F | G | G."),
   d0 + DAY, kind="harmony", attempts=[("bass", d0 + 2 * DAY, [])])
# 표현: 악보 기호 + 톤
fb(21, 29, ["vocals"],
   ("이 구간은 ‘이어서’ 연주해 주세요. 톤: 밝게", "In this section, play it “Connected”. Tone: Bright"),
   d0 + 600, kind="expression",
   comments=[C("vocals", ("혹시 키를 반음 내리는 건 어때요?", "How about lowering the key by a half step?"), d0 + 3600),
             C("leader", ("일단 원키로 한 번 더 해보고 결정해요", "Let's try the original key once more, then decide."), d0 + 4000)])
fb(170, 178, ["piano"],
   ("이 구간은 ‘점점 작아지게’ 연주해 주세요. 톤: 따뜻하게", "In this section, play it “Getting softer”. Tone: Warm"),
   d0 + 3 * DAY + 500, kind="expression",
   attempts=[("piano", d0 + 4 * DAY + 500, [C("leader", ("딱 좋아요", "Just right."), d0 + 4 * DAY + 900)])], passed_index=0)
fb(215, 225, ["vocals"],
   ("이 구간은 ‘또렷하게’ 연주해 주세요.", "In this section, play it “Accented”."),
   d0 + 4 * DAY + 600, kind="expression", attempts=[("vocals", d0 + 4 * DAY + 3000, [])])
# 그 외: 글로만
fb(58, 66, ["guitar"],
   ("코드 전환할 때 뮤트가 안 돼서 지저분해요.", "The muting isn't clean on chord changes, so it sounds messy."), d0 + 1800, kind="free")
fb(128, 136, ["vocals"],
   ("브릿지 고음 부분 가사 전달이 잘 안 돼요.", "The lyrics are hard to understand in the high part of the bridge."),
   d0 + DAY + 1200, kind="free", attempts=[("vocals", d0 + 3 * DAY + 700, [])])
fb(150, 158, ["guitar"],
   ("솔로 앞부분 벤딩 음이 덜 올라가요.", "The bent note at the start of the solo doesn't go up far enough."),
   d0 + 2 * DAY + 600, kind="free",
   attempts=[("guitar", d0 + 3 * DAY + 1000, [C("leader", ("많이 좋아졌어요. 마지막 음만 조금 더", "Much better. Just a bit more on the last note."), d0 + 3 * DAY + 8000)]),
             ("guitar", d0 + 4 * DAY, [C("piano", ("비브라토 조금 줄이면 더 깔끔할 것 같아요", "I think it'd be cleaner with a little less vibrato."), d0 + 4 * DAY + 2000)])])
fb(182, 190, [],
   ("시작 신호는 드럼이 줘요. 4박 카운트 듣고 들어와요.", "Drums give the start cue. Come in after the four-beat count."),
   d0 + 4 * DAY, kind="free")
fb(200, 212, [],
   ("마지막 엔딩 다 같이 끝 음 맞추기! 드럼 신호 보고 끊어요.", "Let's all land the final note together at the ending! Cut off on the drum cue."),
   d0 + 4 * DAY + 100, kind="free",
   comments=[C("drums", ("4박 카운트 후에 심벌 잡을게요", "I'll catch the cymbal after a four-beat count."), d0 + 4 * DAY + 300)])
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
