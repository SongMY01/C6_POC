"""
여러 iPad 동기화 — 이 서버(Mac)가 공유 상태의 기준 저장소.

공유 상태 = 피드백(시도·코멘트 포함) + 재녹음 패치 목록(+ 녹음 파일) + 공유 곡(분리 job).
iPad는 바뀐 내용을 "작은 작업(op)" 단위로 보내고(POST /sync/ops), 3초마다 전체 상태를
받아 간다(GET /sync/state). 작업 단위로 반영하므로 두 기기가 동시에 같은 피드백에
코멘트를 달아도 서로 덮어쓰지 않는다.

  GET  /sync/state[?since=N]       -> {version, songJobId, feedback, patches}  (since==version이면 {version}만)
  POST /sync/ops  {ops:[...]}      -> {version}
  PUT  /sync/patches/{id}/audio    (녹음 파일 바이너리 업로드)
  GET  /sync/patches/{id}/audio
  POST /sync/admin/replace {feedback, patches}   (테스트 데이터 초기화용)
  POST /sync/admin/variant {variant}             (모든 iPad의 테스트 버전 전환, null이면 해제)
  POST /sync/events {events:[...]}               (앱 행동 기록 → data/sync/events.jsonl)
  POST /sync/presence {device, role, activity}   (지금 뭘 하고 있는지 알리고, 다른 사람들의 상태를 받는다 — 저장 안 함)
  POST /sync/admin/rehearsal {nextRehearsal, reset}  (다음 합주 시각 / 팀 시작 현황 초기화)

피드백·패치 JSON은 앱(Swift Codable)이 만든 모양 그대로 저장한다 — 서버는 id로 찾아
필요한 필드만 건드린다.
"""
import json
import threading
import time
from pathlib import Path

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import FileResponse

SYNC_DIR = Path(__file__).resolve().parent / "data" / "sync"
AUDIO_DIR = SYNC_DIR / "patches"
STATE_PATH = SYNC_DIR / "state.json"
EVENTS_PATH = SYNC_DIR / "events.jsonl"
AUDIO_DIR.mkdir(parents=True, exist_ok=True)

router = APIRouter(prefix="/sync")
_lock = threading.Lock()


def _load() -> dict:
    if STATE_PATH.exists():
        try:
            return json.loads(STATE_PATH.read_text())
        except json.JSONDecodeError:
            pass
    return {"version": 0, "songJobId": None, "variant": None, "feedback": [], "patches": []}


_state = _load()
_state.setdefault("variant", None)
# 버전 B용 공유 상태: 응원 리액션, 동료 칭호, 이번 합주 전 연습을 시작한 사람들, 다음 합주 시각(epoch 초)
_state.setdefault("reactions", [])
_state.setdefault("titles", [])
_state.setdefault("teamStarted", [])
_state.setdefault("nextRehearsal", time.time() + 3 * 86400)

# 지금 연습 중 표시(메모리만): device -> {role, activity, ts}
_presence: dict = {}
PRESENCE_TTL = 20  # 초


def _save():
    tmp = STATE_PATH.with_suffix(".tmp")
    tmp.write_text(json.dumps(_state, ensure_ascii=False))
    tmp.replace(STATE_PATH)


def _bump():
    _state["version"] += 1
    _save()


def set_song_job(job_id: str):
    with _lock:
        _state["songJobId"] = job_id
        _bump()


def current_song_job():
    with _lock:
        return _state.get("songJobId")


# MARK: - 작업(op) 적용

def _feedback(fid):
    return next((f for f in _state["feedback"] if f["id"] == fid), None)


def _apply(op: dict):
    t = op.get("type")
    p = op.get("payload") or {}

    if t == "feedback.add":
        item = p["item"]
        if _feedback(item["id"]) is None:
            _state["feedback"].append(item)
            _state["feedback"].sort(key=lambda f: f.get("startTime", 0))
    elif t == "feedback.delete":
        _state["feedback"] = [f for f in _state["feedback"] if f["id"] != p["id"]]
    elif t == "feedback.setPassed":
        f = _feedback(p["id"])
        if f is not None:
            if p.get("attemptId"):
                f["passedAttemptId"] = p["attemptId"]
            else:
                f.pop("passedAttemptId", None)
    elif t == "attempt.add":
        f = _feedback(p["feedbackId"])
        if f is not None and not any(a["id"] == p["attempt"]["id"] for a in f.setdefault("attempts", [])):
            f["attempts"].append(p["attempt"])
            f.pop("passedAttemptId", None)  # 새 시도가 오면 다시 열림
    elif t == "attempt.delete":
        f = _feedback(p["feedbackId"])
        if f is not None:
            f["attempts"] = [a for a in f.get("attempts", []) if a["id"] != p["attemptId"]]
            if f.get("passedAttemptId") == p["attemptId"]:
                f.pop("passedAttemptId", None)
    elif t == "comment.add":
        f = _feedback(p["feedbackId"])
        if f is not None:
            target = f.setdefault("comments", [])
            if p.get("attemptId"):
                attempt = next((a for a in f.get("attempts", []) if a["id"] == p["attemptId"]), None)
                if attempt is not None:
                    target = attempt.setdefault("comments", [])
            if not any(c["id"] == p["comment"]["id"] for c in target):
                target.append(p["comment"])
    elif t == "comment.delete":
        f = _feedback(p["feedbackId"])
        if f is not None:
            f["comments"] = [c for c in f.get("comments", []) if c["id"] != p["commentId"]]
            for a in f.get("attempts", []):
                a["comments"] = [c for c in a.get("comments", []) if c["id"] != p["commentId"]]
    elif t == "reaction.add":
        r = p["reaction"]
        if not any(x["id"] == r["id"] for x in _state["reactions"]):
            _state["reactions"].append(r)
    elif t == "reaction.remove":
        _state["reactions"] = [x for x in _state["reactions"] if x["id"] != p["id"]]
    elif t == "title.give":
        title = p["title"]
        if not any(x["id"] == title["id"] for x in _state["titles"]):
            _state["titles"].append(title)
    elif t == "member.started":
        if p["role"] not in _state["teamStarted"]:
            _state["teamStarted"].append(p["role"])
    elif t == "patch.upsert":
        patch = p["patch"]
        _state["patches"] = [x for x in _state["patches"] if x["id"] != patch["id"]] + [patch]
    elif t == "patch.delete":
        _state["patches"] = [x for x in _state["patches"] if x["id"] != p["id"]]
        (AUDIO_DIR / f"{p['id']}.caf").unlink(missing_ok=True)
    else:
        raise HTTPException(400, f"unknown op: {t}")


# MARK: - 엔드포인트

@router.get("/state")
async def get_state(since: int = -1):
    with _lock:
        if since == _state["version"]:
            return {"version": _state["version"]}
        return _state


@router.post("/ops")
async def post_ops(request: Request):
    body = await request.json()
    with _lock:
        for op in body.get("ops", []):
            _apply(op)
        _bump()
        return {"version": _state["version"]}


@router.put("/patches/{patch_id}/audio")
async def put_audio(patch_id: str, request: Request):
    data = await request.body()
    if not data:
        raise HTTPException(400, "empty body")
    (AUDIO_DIR / f"{patch_id}.caf").write_bytes(data)
    return {"ok": True, "bytes": len(data)}


@router.get("/patches/{patch_id}/audio")
async def get_audio(patch_id: str):
    path = AUDIO_DIR / f"{patch_id}.caf"
    if not path.exists():
        raise HTTPException(404, "audio not uploaded")
    return FileResponse(path, media_type="audio/x-caf")


@router.post("/admin/variant")
async def admin_variant(request: Request):
    """진행자가 Mac에서 모든 iPad의 테스트 버전(A/B/C …)을 한 번에 바꾼다. iPad는 3초 안에 반영."""
    body = await request.json()
    variant = body.get("variant")
    with _lock:
        _state["variant"] = variant or None
        _bump()
        return {"version": _state["version"], "variant": _state["variant"]}


@router.post("/events")
async def post_events(request: Request):
    """앱이 보내는 행동 기록(앱 열기, 곡 열기, 녹음 시작 …)을 한 줄씩 쌓는다. 서버 시각을 함께 남긴다."""
    body = await request.json()
    now = time.time()
    with _lock, EVENTS_PATH.open("a") as f:
        for event in body.get("events", []):
            event["serverTime"] = now
            f.write(json.dumps(event, ensure_ascii=False) + "\n")
    return {"ok": True}


@router.post("/presence")
async def post_presence(request: Request):
    """각 iPad가 3초마다 "나는 지금 이걸 하는 중"을 알리고, 다른 사람들의 지금 상태를 돌려받는다."""
    body = await request.json()
    now = time.time()
    device = body.get("device", "?")
    _presence[device] = {"device": device, "role": body.get("role"), "activity": body.get("activity"), "ts": now}
    active = [v for v in _presence.values() if now - v["ts"] < PRESENCE_TTL]
    for stale in [d for d, v in _presence.items() if now - v["ts"] >= PRESENCE_TTL * 6]:
        _presence.pop(stale, None)
    return {"presence": active}


@router.post("/admin/rehearsal")
async def admin_rehearsal(request: Request):
    """다음 합주 시각(epoch 초)을 정하거나, 이번 주기의 "연습 시작" 현황을 초기화한다."""
    body = await request.json()
    with _lock:
        if body.get("nextRehearsal") is not None:
            _state["nextRehearsal"] = body["nextRehearsal"]
        if body.get("reset"):
            _state["teamStarted"] = []
        _bump()
        return {"version": _state["version"], "nextRehearsal": _state["nextRehearsal"], "teamStarted": _state["teamStarted"]}


@router.post("/admin/replace")
async def admin_replace(request: Request):
    """유저테스트 전에 모든 기기의 피드백·패치를 한 번에 초기화한다 (공유 곡은 유지)."""
    body = await request.json()
    with _lock:
        _state["feedback"] = body.get("feedback", [])
        _state["patches"] = body.get("patches", [])
        _state["reactions"] = body.get("reactions", [])
        _state["titles"] = body.get("titles", [])
        _state["teamStarted"] = body.get("teamStarted", [])
        if body.get("nextRehearsal") is not None:
            _state["nextRehearsal"] = body["nextRehearsal"]
        keep = {p["id"] for p in _state["patches"]}
        for f in AUDIO_DIR.glob("*.caf"):
            if f.stem not in keep:
                f.unlink()
        _bump()
        return {"version": _state["version"]}
